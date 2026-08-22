# AltivecIntelligence Deployment Specification

This document describes the logic and requirements of the `altivec-deploy` script, optimized for deploying applications to legacy and modern Apple systems.

## 1. Overview

The script automates the discovery, transfer, installation, and debugging of applications from the Altivec Linux container to an SSH-accessible Mac or iPhone. Local deployment is intentionally unsupported because the command runs inside the container rather than on the user's Apple device.

## 2. Command Line Interface

- **Usage:** `./bin/altivec-deploy <path_to_app_or_build_dir> --device <user@host> [options]`
- **Arguments:**
  - `<path_to_app_or_build_dir>`: Path to a `.app` bundle or a directory containing one.
  - `-d | --device <user@host>`: Required SSH target. Key authentication must already be configured.
  - `-y | --yes [seconds]`: (Optional) Skips the deployment summary and confirmation prompt for non-interactive use. The optional timeout preserves the original CLI behavior.
  - `--timeout <seconds>`: Sets the non-interactive timeout explicitly. The default is 60 seconds.
  - `-h | --help`: Prints usage information.

## 3. Architecture & Style

- **Runtime:** The executable is dependency-free CommonJS for the Node.js runtime already included in the Altivec image. It uses only `node:child_process`, `node:fs`, `node:os`, `node:path`, and `node:readline/promises`.
- **Subprocesses:** Commands and arguments are passed separately to `spawn`; local user-controlled values are not interpolated into a local shell command.
- **Modularity:** Logic is partitioned into functions for discovery, preflight, validation, debugger initialization, execution, and cleanup. Pure functions are exported for unit testing, but the command remains a single executable.
- **Cleanup:** The main deployment is wrapped in `try/finally`. Cleanup only occurs after a remote mutation has started, and generated debugger files are always removed.
- **Errors:** Every required subprocess must exit successfully. A failed transfer, extraction, installation, launch, or debugger now causes a nonzero command exit.
- **Non-TTY Use:** When standard input is not an interactive terminal, `--yes` is required. EOF can never authorize a deployment.

## 4. Preflight System (Validation)

### Application Preflight

1. **App Discovery:** Searches up to 2 levels deep for a `.app` bundle. An ambiguous result is rejected so the caller can pass the intended bundle explicitly.
2. **Payload Discovery:** Prefers an `.ipa` or `.zip` matching the app name. A lone differently named payload remains supported, while an ambiguous set is rejected.
3. **Symbol Discovery:** Finds all `.dSYM` bundles in the same directory.
4. **Debugger Init Discovery:** Locates `gdbinit` and `lldbinit` within the `templates` directory relative to the script.
5. **Executable Resolution:** Identifies the binary name from the `.app` bundle.

### Device Preflight

1. **SSH Connectivity:** Verifies the required target with `BatchMode=yes` and a 5-second timeout. Fails immediately if password authentication is required.
2. **OS/Type Detection:** Identifies the target OS via `uname` and device type (`ios` if `/var/mobile` exists, otherwise `mac`). Captures the OS even if not Darwin (e.g., Linux) for later validation.
3. **Utility Probing:** Uses `command -v` to robustly find `gdb`, `lldb`, `appinst`, and `ipainstaller`.
4. **Log Discovery:** Explicitly checks for both `/var/log/system.log` (Mac) and `/var/log/syslog` (iPhone).

### Go/No-Go Validation

Before the summary is presented, the script performs a final compatibility check:

- **OS Support:** Rejects deployments to non-Darwin systems (e.g., Linux).
- **Payload Match:** Fails if an `.ipa` is targeted at a Mac or if a Mac deployment is missing a `.zip` payload.
- **Installer Check:** Fails iPhone deployments if neither `appinst` nor `ipainstaller` is found on the target.

## 5. Deployment Summary & Authorization

The script displays a comprehensive summary of its intent:

- **Action:** Mac or iPhone SSH deployment.
- **Inventory:** List of files to be transferred (Archives, dSYMs, Inits).
- **User Prompt:** Requires an explicit `(Y/n)` input to continue.

## 6. Execution & Instruction System

To ensure a smooth user experience, the script displays context-aware `log_instructions` before critical actions.

### Debugger Instructions

- Displayed before launching `lldb` or `gdb`.
- Guides the user on how to `run`, pause (`Ctrl+C`), `kill`, and `quit`.
- **Remote Note:** Informs the user that remote files will be deleted automatically upon exit.

### Log Tailing Instructions

- Displayed before `tail -f`.
- **Line Buffering:** All `grep` commands use `--line-buffered` to ensure real-time log output, especially over SSH.
- **iPhone Cleanup Note:** Specifically notes that temporary installation files are deleted while the app remains on the device.

## 7. Execution Paths

### Remote Mac Deployment

- **Single-Shot Transfer:** Uses `scp -r` to move the payload, symbols, and inits in one connection.
- **Isolated Workspace:** Uses a unique directory beneath `~/Desktop/Altivec` for each deployment so concurrent runs do not overwrite one another.
- **Preparation:** Extracts the archive on the remote machine.
- **Debugging:** Launches the remote debugger via `ssh -t` (interactive tty) with the appropriate init flags.

### Remote iPhone Deployment

- **Transfer:** Copies the `.ipa` payload to `~/tmp_altivec`.
- **Isolated Workspace:** Uses a unique directory beneath `~/tmp_altivec` for each deployment.
- **Installation:** Uses `appinst` (preferred) or `ipainstaller` for installation.
- **Cleanup:** Deletes the temporary `.ipa` immediately after successful installation.

## 8. Error Handling & Safety

- **Guaranteed Cleanup:** Uses `try/finally` to clean generated local files and the run-specific remote workspace.
- **Private Temporary Files:** Uses an unpredictable `fs.mkdtemp` directory with mode `0700`; generated debugger init files use mode `0600` because they may contain `.env` values.
- **Validation:** Centralized plan validation prevents "half-baked" deployments.
- **Exit Status:** Required subprocess failures propagate to the caller instead of allowing deployment to continue and report success.
- **Transparency:** All utility paths and log locations are clearly printed during the preflight phase.
