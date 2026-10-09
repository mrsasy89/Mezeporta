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
if "--stdin-b64" in args:
    import pathlib, struct
    index = args.index("--stdin-b64") - 1
    source = pathlib.Path(args[index])
    data = bytearray(source.read_bytes())
    pe = struct.unpack_from("<I", data, 0x3c)[0]
    if data[:2] != b"MZ" or data[pe:pe+4] != b"PE\x00\x00":
        sys.exit("Invalid helper PE header")
    offset = pe + 24 + 68
    original = struct.unpack_from("<H", data, offset)[0]
    if original not in (2, 3):
        sys.exit("Unexpected helper subsystem")
    struct.pack_into("<H", data, offset, 3)
    target = source.with_name("meze-deps-console-debug.exe")
    target.write_bytes(data)
    args[index] = str(target)
    print("Diagnostic helper subsystem:", original, "-> 3", flush=True)
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
    # Relative generated paths keep game-folder spaces and shell characters
    # out of cmd.exe syntax. The private directory contains the credentials.
    with tempfile.TemporaryDirectory(prefix="launch-", dir="Mezeporta") as tmp:
        folder = pathlib.Path(tmp)
        (folder / "input.b64").write_bytes(payload)
        os.chmod(folder / "input.b64", 0o600)
        win = str(folder).replace("/", chr(92))
        line = ("Mezeporta" + chr(92) + "bin" + chr(92)
                + "meze-deps-console-debug.exe --stdin-b64 < "
                + win + chr(92) + "input.b64 > "
                + win + chr(92) + "output.log 2>&1")
        print("Transport: Windows file redirection from inherited host cwd", flush=True)
        proton_output = folder / "proton.log"
        with proton_output.open("wb") as proton_log:
            result = subprocess.run(
                [sys.executable, proton, "run", "cmd.exe", "/d", "/c", line],
                stdin=subprocess.DEVNULL,
                stdout=proton_log,
                stderr=subprocess.STDOUT,
            )
        output = folder / "output.log"
        print("Proton output bytes:", proton_output.stat().st_size, flush=True)
        if proton_output.stat().st_size:
            sys.stdout.flush()
            sys.stdout.buffer.write(proton_output.read_bytes())
            sys.stdout.buffer.flush()
        print("Helper output file exists:", output.exists(), flush=True)
        if output.exists():
            sys.stdout.flush()
            sys.stdout.buffer.write(output.read_bytes())
            sys.stdout.buffer.flush()
    sys.exit(result.returncode if result.returncode >= 0 else 128 - result.returncode)
os.execv(sys.executable, command)
' "$PWD" "$MEZEPORTA_HOST_PROTON" "$@" || status=$?
printf 'Proton host exit status: %s\n' "$status"
exit "$status"
