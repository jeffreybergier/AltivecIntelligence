#!/usr/bin/env bash

# AltivecIntelligence Deployment Script
# Usage: ./altivec_deploy.sh -td <ssh_host> -tp <package_path>

set -e

# Initialize variables
TARGET_DEVICE=""
TARGET_PACKAGE=""

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -td|--targetDevice) TARGET_DEVICE="$2"; shift ;;
    -tp|--targetPackage) TARGET_PACKAGE="$2"; shift ;;
    *) echo "Unknown parameter passed: $1"; exit 1 ;;
  esac
  shift
done

# --- Local Preflight ---
echo "--- PREFLIGHT CHECK (Local) ---"
if [ -z "$TARGET_DEVICE" ] || [ -z "$TARGET_PACKAGE" ]; then
  echo "[FAIL] Missing required parameters."
  echo "Usage: ./altivec_deploy.sh -td <ssh_host> -tp <package_path>"
  exit 1
fi

if [ ! -f "$TARGET_PACKAGE" ]; then
  if [ -d "$TARGET_PACKAGE" ]; then
    echo "[FAIL] '$TARGET_PACKAGE' is a directory."
    echo "Please provide a .zip file (containing the .app) for Mac or an .ipa file for iPhone."
  else
    echo "[FAIL] Target package '$TARGET_PACKAGE' not found."
  fi
  exit 1
fi
echo "[OK] Local package found: $TARGET_PACKAGE"

# --- Remote Preflight ---
echo ""
echo "--- PREFLIGHT CHECK (Remote: $TARGET_DEVICE) ---"

# 1. Connection & OS Info
REMOTE_INFO=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$TARGET_DEVICE" "uname -sm; [ -d /var/mobile ] && echo 'iOS' || echo 'macOS'" 2>/dev/null)

if [ $? -ne 0 ]; then
  echo "[FAIL] Could not connect to '$TARGET_DEVICE' via SSH."
  exit 1
fi
echo "[OK] SSH Connection established."

UNAME_OUTPUT=$(echo "$REMOTE_INFO" | head -n 1)
TYPE_HINT=$(echo "$REMOTE_INFO" | tail -n 1)
OS_NAME=$(echo "$UNAME_OUTPUT" | awk '{print $1}')
MACHINE_ARCH=$(echo "$UNAME_OUTPUT" | awk '{print $2}')

DEVICE_TYPE="unknown"
if [[ "$OS_NAME" == "Darwin" ]]; then
  if [[ "$TYPE_HINT" == "iOS" ]] || [[ "$MACHINE_ARCH" == iPhone* ]] || [[ "$MACHINE_ARCH" == arm* ]]; then
    DEVICE_TYPE="iphone"
  else
    DEVICE_TYPE="mac"
  fi
fi
echo "[OK] Detected Device Type: $DEVICE_TYPE ($UNAME_OUTPUT)"

# 2. iPhone-Specific Checks
HAS_IPAINSTALLER=false
HAS_SYSLOG=false

if [[ "$DEVICE_TYPE" == "iphone" ]]; then
  if ssh -o BatchMode=yes "$TARGET_DEVICE" "which ipainstaller" &>/dev/null; then
    echo "[OK] found 'ipainstaller' utility."
    HAS_IPAINSTALLER=true
  else
    echo "[FAIL] 'ipainstaller' NOT found. (Install via Cydia)"
  fi

  if ssh -o BatchMode=yes "$TARGET_DEVICE" "[ -f /var/log/syslog ]" &>/dev/null; then
    echo "[OK] found '/var/log/syslog' for log tailing."
    HAS_SYSLOG=true
  else
    echo "[WARN] '/var/log/syslog' NOT found. (Install 'syslogd' via Cydia for logs)"
  fi
fi

# 3. Mac-Specific Checks
HAS_LLDB=false
HAS_GDB=false

if [[ "$DEVICE_TYPE" == "mac" ]]; then
  # Robust debugger check: Try to execute with --version or --help
  if ssh -o BatchMode=yes "$TARGET_DEVICE" "lldb --version" &>/dev/null; then
    echo "[OK] found 'lldb' debugger."
    HAS_LLDB=true
  elif ssh -o BatchMode=yes "$TARGET_DEVICE" "gdb --version" &>/dev/null; then
    echo "[OK] found 'gdb' debugger."
    HAS_GDB=true
  else
    echo "[WARN] No debugger found. Will fall back to system log."
  fi
fi

# Final Preflight Validation
if [[ "$DEVICE_TYPE" == "iphone" ]] && [[ "$HAS_IPAINSTALLER" == false ]]; then
  echo ""
  echo "Preflight failed: Missing mandatory utilities on iPhone."
  exit 1
fi

echo ""
echo "--- DEPLOYMENT STARTING ---"

PACKAGE_NAME=$(basename "$TARGET_PACKAGE")
APP_NAME=$(echo "$PACKAGE_NAME" | sed 's/\.zip$//' | sed 's/\.ipa$//')

# --- iPhone Deployment Logic ---
if [[ "$DEVICE_TYPE" == "iphone" ]]; then
  TMP_DIR="~/tmp_altivec"
  
  echo "Creating remote temp directory: $TMP_DIR"
  ssh -o BatchMode=yes "$TARGET_DEVICE" "mkdir -p $TMP_DIR"
  
  echo "Uploading package..."
  scp -o BatchMode=yes "$TARGET_PACKAGE" "$TARGET_DEVICE:$TMP_DIR/$PACKAGE_NAME"
  
  echo "Installing package..."
  set +e
  ssh -o BatchMode=yes "$TARGET_DEVICE" "ipainstaller $TMP_DIR/$PACKAGE_NAME"
  set -e
  
  echo "Cleaning up remote temp file..."
  ssh -o BatchMode=yes "$TARGET_DEVICE" "rm $TMP_DIR/$PACKAGE_NAME"
  
  echo "Deployment complete!"

  if [[ "$HAS_SYSLOG" == true ]]; then
    echo ""
    echo "***************************************************"
    echo "  PLEASE OPEN THE APP ON YOUR IPHONE NOW"
    echo "  Tailing /var/log/syslog (Press Ctrl+C to stop)..."
    echo "***************************************************"
    echo ""
    ssh "$TARGET_DEVICE" "tail -f /var/log/syslog"
  fi
fi

# --- Mac Deployment Logic ---
if [[ "$DEVICE_TYPE" == "mac" ]]; then
  DEPLOY_DIR="~/Desktop/Altivec"
  
  echo "Creating deployment directory: $DEPLOY_DIR"
  ssh -o BatchMode=yes "$TARGET_DEVICE" "mkdir -p $DEPLOY_DIR"
  
  echo "Uploading package..."
  scp -o BatchMode=yes "$TARGET_PACKAGE" "$TARGET_DEVICE:$DEPLOY_DIR/$PACKAGE_NAME"
  
  echo "Extracting application..."
  ssh -o BatchMode=yes "$TARGET_DEVICE" "cd $DEPLOY_DIR && unzip -oq $PACKAGE_NAME && rm $PACKAGE_NAME"
  
  # Heuristic to find the .app inside the directory
  REMOTE_APP_PATH=$(ssh -o BatchMode=yes "$TARGET_DEVICE" "find $DEPLOY_DIR -name '*.app' -maxdepth 1 | head -n 1")
  
  if [ -z "$REMOTE_APP_PATH" ]; then
    echo "Error: Could not find .app bundle after extraction in $DEPLOY_DIR"
    exit 1
  fi

  # Find the actual executable inside the bundle
  EXECUTABLE_NAME=$(echo $(basename "$REMOTE_APP_PATH") | sed 's/\.app$//')
  REMOTE_BIN="$REMOTE_APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"

  echo "Deployment complete!"
  echo ""

  if [[ "$HAS_LLDB" == true ]]; then
    echo "***************************************************"
    echo "  LAUNCHING LLDB"
    echo "  - Type 'run' to start the application."
    echo "  - Press Ctrl+C to pause/interrupt."
    echo "  - Type 'kill' to stop the process."
    echo "  - Type 'quit' to exit the debugger."
    echo ""
    echo "  NOTICE: Remote files will be deleted upon exit."
    echo "***************************************************"
    echo ""
    ssh -t "$TARGET_DEVICE" "lldb $REMOTE_BIN"
  elif [[ "$HAS_GDB" == true ]]; then
    echo "***************************************************"
    echo "  LAUNCHING GDB"
    echo "  - Type 'run' to start the application."
    echo "  - Press Ctrl+C to pause/interrupt."
    echo "  - Type 'kill' to stop the process."
    echo "  - Type 'quit' to exit the debugger."
    echo ""
    echo "  NOTICE: Remote files will be deleted upon exit."
    echo "***************************************************"
    echo ""
    ssh -t "$TARGET_DEVICE" "gdb $REMOTE_BIN"
  else
    echo "***************************************************"
    echo "  PLEASE OPEN THE APP ON YOUR MAC NOW"
    echo "  Tailing /var/log/system.log (Press Ctrl+C to stop)..."
    echo "  NOTICE: Remote files will be deleted upon exit."
    echo "***************************************************"
    echo ""
    ssh "$TARGET_DEVICE" "tail -f /var/log/system.log"
  fi

  echo ""
  echo "Cleaning up remote Altivec folder..."
  ssh -o BatchMode=yes "$TARGET_DEVICE" "rm -rf $DEPLOY_DIR"
  echo "Mac cleanup complete."
fi
