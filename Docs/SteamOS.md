# SteamOS port: baseline and validation plan

## Scope

Target: Steam Machine running SteamOS, with development in the Arch Distrobox
`mhfz-dev`. Server version reported by the maintainer: Erupe 9.6.1, upgraded
from 9.2.1. Desktop mode is the first validation target; Gaming Mode follows
after successful login, launch and exit in Desktop mode.

This document records source inspection, not a successful SteamOS test.

## Pinned sources

- Mezeporta upstream: https://github.com/LilButter/Mezeporta
  - Branch: `CLI-dev`
  - Baseline: `0d7712f99700ff643c834cc3fd668a4767ca5a05`
- Working implementation reference: https://github.com/mrsasy89/MHFZ-Launcher
  - Inspected revision: `1df702fbf6f08a764c249fdf855874a7a650f807`
  - Proton/Distrobox implementation: `src-tauri/src/lib_linux.rs`
- Related sources supplied by the maintainer (not yet audited):
  - https://github.com/mrsasy89/mhf-iel
  - https://github.com/mrsasy89/Erupe
  - https://github.com/mrsasy89/MHFZ-Patch-Server
  - https://github.com/LilButter/Mezeporta-Wrapper
  - https://github.com/Houmgaor/Erupe

Keep the upstream history. Use `steamos-dev` for the port, leaving the upstream
baseline available for comparison. Make one commit per verified milestone.

## Findings from the baseline

1. `src-tauri/src/main.rs` already implements a Proton runtime, Steam path
   discovery and `proton run`. Linux launches the bundled `meze-deps.exe`
   helper with a base64 configuration supplied through stdin. Preserve this
   interface; do not substitute the older launcher's helper without an audit.
2. Runtime commands are spawned directly. There is no Distrobox host dispatch,
   unlike MHFZ-Launcher. Proton must run in the host environment for the
   established development workflow, including registry and setup operations.
3. `src-tauri/src/cli.rs` passes `Default::default()` launcher preferences to
   `run_mhf`. The default prefix mode is `portable`, so the CLI does not select
   Proton through persisted GUI preferences or `MEZEPORTA_PROTON_CMD` alone.
4. Proton compat data defaults to `<game>/Mezeporta/ProtonData`. `apply_env`
   also sets `WINEPREFIX` to that same directory. Review this distinction:
   Proton's Windows prefix is normally the `pfx` child of its compat-data root.
5. Proton discovery scans common Steam locations but does not parse
   `steamapps/libraryfolders.vdf` for additional libraries. The reference
   launcher does inspect that file and prioritizes Proton Experimental.
6. Linux UI uses Tauri 1 with vendored WebKit bindings. Validate the existing
   Arch build scripts before choosing a packaging format.

## Milestones

1. Create the maintainer's GitHub fork with all branches and publish this
   baseline document on `steamos-dev`.
2. Verify the unmodified Linux UI in `mhfz-dev`: use the existing Arch build
   dependency verifier, install frontend dependencies with `npm ci`, then
   run `npm run tauri:dev:linux`. Record exact host/container tool versions
   and failures before changing runtime behavior.
3. Add explicit Proton selection to CLI and a shared host command builder
   for Distrobox. Preserve stdin, working directory and argument boundaries;
   avoid constructing shell commands from user or server input.
4. Validate Steam paths, Experimental discovery, compat-data creation and
   controller/font preparation. Keep the new prefix separate from the old
   launcher's working prefix.
5. Validate login, character selection, SD/HD launch, controller, fonts,
   clean exit and repeated launch against the actual Erupe 9.6.1 instance.
   Determine SignV1 versus Wrapper/API from the server configuration.
6. Validate Gaming Mode and packaging after Desktop mode passes.

## Baseline checks in the inspection environment

- Git checkout matches the pinned upstream SHA.
- `node scripts/check-linux-helper.mjs` succeeds.
- `src-tauri/bin/meze-deps.exe` is present and identified as a PE32 i386 helper.
- Rust/Cargo is unavailable in this inspection environment. No Rust build,
  GUI launch, Proton execution or server integration test has been performed.
- The selected Source folder could not be accessed, so uploaded source copies
  have not been compared against GitHub.

## Acceptance evidence for each runtime change

Record the commit, SteamOS version, container toolchain, Proton version,
runtime path, compat-data path, launch mode and sanitized logs. Never put
passwords, authentication tokens or private server configuration into Git.
Command-construction tests should cover spaces in paths, host dispatch,
stdin forwarding and the distinction between compat-data and `pfx`.
