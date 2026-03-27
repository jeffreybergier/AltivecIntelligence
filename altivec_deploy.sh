#!/usr/bin/env bash

# AltivecIntelligence Deployment Script
# Usage: ./altivec_deploy.sh -d <ssh_host> -b <build_dir>

set -e

# Initialize variables
TARGET_DEVICE=""
BUILD_DIR=""

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -d|--device) TARGET_DEVICE="$2"; shift ;;
    -b|--build) BUILD_DIR="$2"; shift ;;
    *) echo "Unknown parameter passed: $1"; exit 1 ;;
  esac
  shift
done

# --- Check Device first ---
if [ -z "$TARGET_DEVICE" ]; then
  echo "[FAIL] Missing required -d <device> parameter."
  exit 1
fi

echo "--- REMOTE CONNECTION CHECK ($TARGET_DEVICE) ---"

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

# --- Local Preflight ---
echo ""
echo "--- PREFLIGHT CHECK (Local: $BUILD_DIR) ---"
if [ -z "$BUILD_DIR" ]; then
  echo "[FAIL] Missing required -b <build_dir> parameter."
  exit 1
fi

if [ ! -d "$BUILD_DIR" ]; then
  echo "[FAIL] Build directory '$BUILD_DIR' not found."
  exit 1
fi

# Check for appropriate package based on device type
if [[ "$DEVICE_TYPE" == "mac" ]]; then
  PACKAGE_PATH=$(find "$BUILD_DIR" -name "*.app" -maxdepth 1 | head -n 1)
  if [ -z "$PACKAGE_PATH" ]; then
    echo "[FAIL] Could not find a .app bundle in '$BUILD_DIR'."
    exit 1
  fi
  echo "[OK] Found Mac bundle: $(basename "$PACKAGE_PATH")"
elif [[ "$DEVICE_TYPE" == "iphone" ]]; then
  PACKAGE_PATH=$(find "$BUILD_DIR" -name "*.ipa" -maxdepth 1 | head -n 1)
  if [ -z "$PACKAGE_PATH" ]; then
    echo "[FAIL] Could not find a .ipa package in '$BUILD_DIR'."
    exit 1
  fi
  echo "[OK] Found iPhone package: $(basename "$PACKAGE_PATH")"
fi

# --- Device-Specific Utility Checks ---
echo ""
echo "--- UTILITY CHECK ---"
HAS_IPAINSTALLER=false
HAS_SYSLOG=false
HAS_LLDB=false
HAS_GDB=false

if [[ "$DEVICE_TYPE" == "iphone" ]]; then
  if ssh -o BatchMode=yes "$TARGET_DEVICE" "which ipainstaller" &>/dev/null; then
    echo "[OK] found 'ipainstaller' utility."
    HAS_IPAINSTALLER=true
  else
    echo "[FAIL] 'ipainstaller' NOT found. (Install via Cydia)"
    exit 1
  fi

  if ssh -o BatchMode=yes "$TARGET_DEVICE" "[ -f /var/log/syslog ]" &>/dev/null; then
    echo "[OK] found '/var/log/syslog' for log tailing."
    HAS_SYSLOG=true
  else
    echo "[WARN] '/var/log/syslog' NOT found."
  fi
elif [[ "$DEVICE_TYPE" == "mac" ]]; then
  if ssh -o BatchMode=yes "$TARGET_DEVICE" "lldb --version" &>/dev/null; then
    echo "[OK] found 'lldb' debugger."
    HAS_LLDB=true
  elif ssh -o BatchMode=yes "$TARGET_DEVICE" "gdb --version" &>/dev/null; then
    echo "[OK] found 'gdb' debugger."
    HAS_GDB=true
  else
    echo "[WARN] No debugger found."
  fi
fi

echo ""
echo "--- DEPLOYMENT STARTING ---"

BUILD_DIR_NAME=$(basename "$BUILD_DIR")

if [[ "$DEVICE_TYPE" == "iphone" ]]; then
  REMOTE_ROOT="~/tmp_altivec"
  REMOTE_BUILD_DIR="$REMOTE_ROOT/$BUILD_DIR_NAME"
  
  echo "Preparing remote directory: $REMOTE_ROOT"
  ssh -o BatchMode=yes "$TARGET_DEVICE" "mkdir -p $REMOTE_ROOT"
  
  echo "Copying whole build directory to iPhone..."
  scp -r -o BatchMode=yes "$BUILD_DIR" "$TARGET_DEVICE:$REMOTE_ROOT/"
  
  IPA_NAME=$(basename "$PACKAGE_PATH")
  echo "Installing package: $IPA_NAME"
  set +e
  ssh -o BatchMode=yes "$TARGET_DEVICE" "ipainstaller $REMOTE_BUILD_DIR/$IPA_NAME"
  set -e
  
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

elif [[ "$DEVICE_TYPE" == "mac" ]]; then
  REMOTE_ROOT="~/Desktop/Altivec"
  # The scp -r command will put the build folder INSIDE REMOTE_ROOT
  REMOTE_BUILD_DIR="$REMOTE_ROOT/$BUILD_DIR_NAME"
  
  echo "Preparing remote directory: $REMOTE_ROOT"
  ssh -o BatchMode=yes "$TARGET_DEVICE" "mkdir -p $REMOTE_ROOT"
  
  echo "Copying whole build directory to Mac..."
  scp -r -o BatchMode=yes "$BUILD_DIR" "$TARGET_DEVICE:$REMOTE_ROOT/"
  
  APP_NAME=$(basename "$PACKAGE_PATH")
  EXECUTABLE_NAME=$(echo "$APP_NAME" | sed 's/\.app$//')
  REMOTE_BIN="$REMOTE_BUILD_DIR/$APP_NAME/Contents/MacOS/$EXECUTABLE_NAME"

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
    echo ""
    echo "  NOTICE: Remote files will be deleted upon exit."
    echo "***************************************************"
    echo ""
    ssh "$TARGET_DEVICE" "tail -f /var/log/system.log"
  fi

  echo ""
  echo "Cleaning up remote Altivec folder..."
  ssh -o BatchMode=yes "$TARGET_DEVICE" "rm -rf $REMOTE_ROOT"
  echo "Mac cleanup complete."
fi
