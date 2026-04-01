# AltivecIntelligence Deployment Specification (Current State)

This document describes the current logic and requirements of the `altivec_deploy.sh` script as of April 1, 2026.

## 1. Overview
The script automates the process of discovering, transferring, installing, and debugging applications on either a local machine or a remote device (Mac or iPhone) via SSH.

## 2. Command Line Interface
- **Usage:** `./altivec_deploy.sh <input_path> [-d <ssh_host>]`
- **Arguments:**
  - `<input_path>`: A path to a `.zip` file, an `.ipa` file, or a directory containing them (or a `build*` subdirectory).
  - `-d | --device <ssh_host>`: (Optional) The SSH alias or IP address of the target device. If omitted, the script operates in local mode.

## 3. Configuration (Constants)
- **iPhone Remote Root:** `~/Altivec`
- **Mac Remote Root:** `~/Desktop/Altivec`
- **Utility Check Commands:** Uses `uname`, `appinst`, `ipainstaller`, `lldb`, and `gdb`.

## 4. Discovery Logic (Preflight)
The script identifies the "Package" and related debug symbols using these rules:

1. **Input is a File:** Must end in `.ipa` or `.zip`.
2. **Input is a Directory:**
   - Cannot be a `.app` bundle directly.
   - Searches the top level for the first `.ipa` or `.zip`.
   - If not found, searches for the first directory named `build*` and looks inside it for a `.ipa` or `.zip`.
3. **App Type Detection:** Sets `APP_TYPE` to `ipa` or `zip`.
4. **Symbol Discovery:** Finds all `.dSYM` directories in the same folder as the discovered package.
5. **Asset Collection:** Adds the package and all found `.dSYMs` to a `FILES_TO_COPY` list.

## 5. Device Detection
The script determines the `DEVICE_TYPE` (`iphone` or `mac`) by checking:
- `uname -sm` (Looking for `Darwin`).
- Existence of `/var/mobile` (Hint for iOS).

## 6. Validation Rules
- **iPhone:** Requires `APP_TYPE` to be `ipa`.
- **Mac:** Requires `APP_TYPE` to be `zip`.
- **Utilities:** 
  - iPhone requires at least one installer (`appinst` or `ipainstaller`).
  - Mac checks for preferred debuggers (`lldb` then `gdb`).

## 7. Deployment Workflow

### Phase 1: Transfer (Remote Only)
1. Creates the remote destination directory.
2. Uses `scp -r` to copy all items in `FILES_TO_COPY`.
3. For Mac: Uploads `altivec_build/lldbinit` or `gdbinit` if they exist locally.

### Phase 2: Installation / Extraction
- **iPhone:** Runs the detected installer on the `.ipa`.
- **Mac:** 
  - If a `.zip` is used, it is unzipped on the target.
  - The script searches for the `.app` bundle inside the extracted content to resolve the executable path.

### Phase 3: Execution & Logging
- **iPhone:** If `syslog` is available, it tails the log and filters by the app name.
- **Mac:** 
  - Launches the application inside the detected debugger (`lldb` or `gdb`).
  - If no debugger is found, it tails `/var/log/system.log` (Remote only).

## 8. Cleanup
- On exit, if in remote mode, the script attempts to delete the temporary remote root directory created during deployment.
