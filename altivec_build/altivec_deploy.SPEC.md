# AltivecIntelligence Deployment Specification

This document describes the logic and requirements of the `altivec_deploy.sh` script, optimized for deploying applications to legacy and modern Apple systems.

## 1. Overview
The script automates the discovery, transfer, installation, and debugging of applications on local or remote Darwin-based devices (Mac and iPhone). It prioritizes clear logic, robust preflights, and interactive debugging.

## 2. Command Line Interface
- **Usage:** `./altivec_deploy.sh <path_to_app_or_build_dir> [-d <user@host>]`
- **Arguments:**
  - `<path_to_app_or_build_dir>`: Path to a `.app` bundle or a directory containing one.
  - `-d | --device <user@host>`: (Optional) SSH connection string for a remote target. If omitted, the script runs in Local Mode.

## 3. Architecture & Style
- **Variable Management:** Following a "C89 style" approach, all variables are declared and initialized at the top of the script. Constants (paths, remote roots) are grouped for easy auditing.
- **Modularity:** Logic is partitioned into distinct functions for Preflight, Summary, Cleanup, and Execution paths (Local, Remote Mac, Remote iPhone).
- **Cleanup:** A `trap` on `EXIT` triggers a `cleanup` function. Cleanup only occurs if a remote mutation has actually started (tracked via `DEV_NEEDS_CLEANUP`).

## 4. Preflight System (Validation)

### Application Preflight
1. **App Discovery:** Searches up to 2 levels deep for a `.app` bundle.
2. **Payload Discovery:** Finds the first `.ipa` or `.zip` file in the same directory as the `.app`.
3. **Symbol Discovery:** Finds all `.dSYM` bundles in the same directory.
4. **Debugger Init Discovery:** Locates `gdbinit` and `lldbinit` within the `altivec_build` directory relative to the script.
5. **Executable Resolution:** Identifies the binary name from the `.app` bundle.

### Device Preflight
1. **SSH Connectivity:** If remote, verifies connection with `BatchMode=yes` and a 5-second timeout. Fails immediately if password authentication is required.
2. **OS/Type Detection:** Identifies the target OS via `uname` and device type (`ios` if `/var/mobile` exists, otherwise `mac`). Captures the OS even if not Darwin (e.g., Linux) for later validation.
3. **Utility Probing:** Uses `command -v` to robustly find `gdb`, `lldb`, `appinst`, and `ipainstaller`.
4. **Log Discovery:** Explicitly checks for both `/var/log/system.log` (Mac) and `/var/log/syslog` (iPhone).

### Go/No-Go Validation (`preflight_go_nogo`)
Before the summary is presented, the script performs a final compatibility check:
- **OS Support:** Rejects deployments to non-Darwin systems (e.g., Linux).
- **Payload Match:** Fails if an `.ipa` is targeted at a Mac or if a remote Mac is missing a `.zip` payload.
- **Installer Check:** Fails iPhone deployments if neither `appinst` nor `ipainstaller` is found on the target.

## 5. Deployment Summary & Authorization
The script displays a comprehensive summary of its intent:
- **Action:** Local launch vs. Remote deployment.
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

### Local Deployment
- **Signal Handling:** Uses `exec` to replace the shell process with the debugger, ensuring `Ctrl+C` correctly interrupts the running app and returns the user to the debugger prompt.
- **Fallback:** If no debugger is found, uses `open` and tails the local system log.

### Remote Mac Deployment
- **Single-Shot Transfer:** Uses `scp -r` to move the payload, symbols, and inits in one connection.
- **Preparation:** Extracts the archive on the remote machine.
- **Debugging:** Launches the remote debugger via `ssh -t` (interactive tty) with the appropriate init flags.

### Remote iPhone Deployment
- **Transfer:** Copies the `.ipa` payload to `~/tmp_altivec`.
- **Installation:** Uses `appinst` (preferred) or `ipainstaller` for installation.
- **Cleanup:** Deletes the temporary `.ipa` immediately after successful installation.

## 8. Error Handling & Safety
- **Traps:** Uses `trap cleanup EXIT` to ensure the remote environment is left clean.
- **Validation:** Centralized `preflight_go_nogo` prevents "half-baked" deployments.
- **Transparency:** All utility paths and log locations are clearly printed during the preflight phase.
