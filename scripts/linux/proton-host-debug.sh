#!/usr/bin/env bash
# Diagnostic bridge for CLI-dev's MEZEPORTA_PROTON_CMD override.
# stdin belongs to meze-deps: validate in memory and forward unchanged.
set -euo pipefail
umask 077

log_dir="${MEZEPORTA_DEBUG_DIR:-${HOME}/.local/state/mezeporta}"
mkdir -p "$log_dir"
exec >>"$log_dir/proton-host.log" 2>&1
printf '\n[%s] Proton host invocation\n' "$(date -Is)"

: "${MEZEPORTA_HOST_PROTON:?Set the absolute host Proton script path}"
: "${STEAM_COMPAT_DATA_PATH:?Missing compat-data directory}"
: "${STEAM_COMPAT_CLIENT_INSTALL_PATH:?Missing Steam installation directory}"
command -v distrobox-host-exec >/dev/null

forward_env=(
  "STEAM_COMPAT_DATA_PATH=$STEAM_COMPAT_DATA_PATH"
  "STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAM_COMPAT_CLIENT_INSTALL_PATH"
)
for key in PROTON_USE_WINED3D WINEESYNC WINEFSYNC WINEDLLOVERRIDES; do
  if [[ -v $key ]]; then forward_env+=("$key=${!key}"); fi
done

# Python receives paths as arguments, not interpolated shell code. Its stdin
# is forwarded unchanged. Proton owns WINEPREFIX and creates compat-data/pfx.
status=0
distrobox-host-exec env "${forward_env[@]}" python3 -c '
import os, sys, base64, json, subprocess
cwd, proton = sys.argv[1:3]
if not os.path.isfile(proton):
    sys.exit("Host Proton script does not exist: " + proton)
os.chdir(cwd)
os.makedirs(os.environ["STEAM_COMPAT_DATA_PATH"], exist_ok=True)
os.environ.pop("WINEPREFIX", None)
print("Host cwd:", cwd, flush=True)
print("Proton:", proton, flush=True)
print("Compat data:", os.environ["STEAM_COMPAT_DATA_PATH"], flush=True)
args = sys.argv[3:]
print("Operation:", "helper stdin" if "--stdin-b64" in args else "runtime setup", flush=True)
command = [sys.executable, proton, *args]
if "--stdin-b64" in args:
    payload = sys.stdin.buffer.read()
    print("Helper stdin bytes:", len(payload), flush=True)
    try:
        config = json.loads(base64.b64decode(payload.strip(), validate=True).decode("utf-8"))
        if not isinstance(config, dict):
            raise ValueError("Expected object")
        print("Payload: valid base64 / UTF-8 / JSON object", flush=True)
        # Only field names and types; never print values or exception messages.
        for key, value in sorted(config.items()):
            print("Config field:", key, "type:", type(value).__name__, flush=True)
    except (ValueError, UnicodeError) as error:
        print("Payload validation failed:", type(error).__name__, flush=True)
        sys.exit(65)
    import tempfile, pathlib
    with tempfile.TemporaryDirectory(prefix="launch-", dir="Mezeporta") as tmp:
        folder = pathlib.Path(tmp)
        relative_folder = folder.relative_to(pathlib.Path.cwd())
        input_path = folder / "input.b64"
        input_path.write_bytes(payload)
        os.chmod(input_path, 0o600)

        option_index = args.index("--stdin-b64")
        windows_input = str(relative_folder / "input.b64").replace("/", chr(92))
        args[option_index:option_index + 1] = [
            "--config-b64-file",
            windows_input,
        ]
        command = [sys.executable, proton, *args]

        print("Transport: private config file to GUI helper", flush=True)
        with tempfile.TemporaryFile() as output_file:
            result = subprocess.run(
                command,
                stdin=subprocess.DEVNULL,
                stdout=output_file,
                stderr=subprocess.STDOUT,
            )
            output_file.seek(0)
            process_output = output_file.read()

        print("Process output bytes:", len(process_output), flush=True)
        if process_output:
            sys.stdout.flush()
            sys.stdout.buffer.write(process_output)
            sys.stdout.buffer.flush()

    sys.exit(result.returncode if result.returncode >= 0 else 128 - result.returncode)
os.execv(sys.executable, command)
' "$PWD" "$MEZEPORTA_HOST_PROTON" "$@" || status=$?
printf 'Proton host exit status: %s\n' "$status"
exit "$status"
