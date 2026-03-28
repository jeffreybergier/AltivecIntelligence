#!/usr/bin/env bash

# AltivecIntelligence Deployment Script
# Usage: ./altivec_deploy.sh <app_dir_or_build_dir> [-d <ssh_host>]

set -e

# Initialize variables
TARGET_DEVICE=""
INPUT_PATH=""

# Parse positional argument (app directory or build directory)
if [[ "$#" -gt 0 ]] && [[ ! "$1" == -* ]]; then
  INPUT_PATH="$1"
  shift
fi

# Parse remaining options
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -d|--device) TARGET_DEVICE="$2"; shift ;;
    *) echo "Unknown parameter passed: $1"; exit 1 ;;
  esac
  shift
done

# --- Resolve Build Directory ---
BUILD_DIR=""
if [ -z "$INPUT_PATH" ]; then
  echo "[FAIL] Missing required <app_dir> argument."
  echo "Usage: ./altivec_deploy.sh <app_dir> [-d <ssh_host>]"
  exit 1
fi

if [ -d "$INPUT_PATH/build-debug" ]; then
  BUILD_DIR="$INPUT_PATH/build-debug"
  echo "[OK] Using debug build: $BUILD_DIR"
elif [ -d "$INPUT_PATH/build-release" ]; then
  BUILD_DIR="$INPUT_PATH/build-release"
  echo "[OK] Using release build: $BUILD_DIR"
elif [ -d "$INPUT_PATH" ]; then
  BUILD_DIR="$INPUT_PATH"
else
  echo "[FAIL] Build directory '$INPUT_PATH' not found."
  exit 1
fi

# --- Determine Mode (Remote vs Local) ---
IS_REMOTE=false
if [ -n "$TARGET_DEVICE" ]; then
  IS_REMOTE=true
  echo "--- REMOTE CONNECTION CHECK ($TARGET_DEVICE) ---"
else
  echo "--- LOCAL MODE CHECK ---"
fi

# 1. Connection & OS Info
if [ "$IS_REMOTE" = true ]; then
  set +e
  REMOTE_INFO=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$TARGET_DEVICE" "uname -sm; [ -d /var/mobile ] && echo 'iOS' || echo 'macOS'" 2>/dev/null)
  SSH_EXIT_CODE=$?
  set -e
  
  if [ $SSH_EXIT_CODE -ne 0 ]; then
    echo "[FAIL] Could not connect to '$TARGET_DEVICE' via SSH."
    exit 1
  fi
  echo "[OK] SSH Connection established."
  UNAME_OUTPUT=$(echo "$REMOTE_INFO" | head -n 1)
  TYPE_HINT=$(echo "$REMOTE_INFO" | tail -n 1)
else
  UNAME_OUTPUT=$(uname -sm)
  [ -d /var/mobile ] && TYPE_HINT="iOS" || TYPE_HINT="macOS"
fi

OS_NAME=$(echo "$UNAME_OUTPUT" | awk '{print $1}')
MACHINE_ARCH=$(echo "$UNAME_OUTPUT" | awk '{print $2}')

DEVICE_TYPE="unknown"
if [[ "$OS_NAME" == "Darwin" ]]; then
  if [[ "$TYPE_HINT" == "iOS" ]]; then
    DEVICE_TYPE="iphone"
  elif [[ "$MACHINE_ARCH" == iPhone* ]] || [[ "$MACHINE_ARCH" == iPad* ]]; then
    DEVICE_TYPE="iphone"
  else
    DEVICE_TYPE="mac"
  fi
fi
echo "[OK] Detected Device Type: $DEVICE_TYPE ($UNAME_OUTPUT)"

# 2. Check compatibility
if [[ "$DEVICE_TYPE" == "unknown" ]]; then
  echo ""
  echo "[FAIL] This device ($OS_NAME) is not a Mac or iPhone."
  echo "Please run this script on a Mac or specify a remote target device with -d|--device."
  exit 1
fi

# --- Local Preflight ---
echo ""
echo "--- PREFLIGHT CHECK (Local: $BUILD_DIR) ---"

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

# --- Utility Checks ---
echo ""
echo "--- UTILITY CHECK ---"
HAS_IPAINSTALLER=false
HAS_SYSLOG=false
HAS_LLDB=false
HAS_GDB=false

check_util() {
  if [ "$IS_REMOTE" = true ]; then
    ssh -o BatchMode=yes "$TARGET_DEVICE" "$1" &>/dev/null
  else
    eval "$1" &>/dev/null
  fi
}

if [[ "$DEVICE_TYPE" == "iphone" ]]; then
  if check_util "which ipainstaller"; then
    echo "[OK] found 'ipainstaller' utility."
    HAS_IPAINSTALLER=true
  else
    echo "[FAIL] 'ipainstaller' NOT found. (Install via Cydia)"
    exit 1
  fi
elif [[ "$DEVICE_TYPE" == "mac" ]]; then
  if check_util "lldb --version"; then
    echo "[OK] found 'lldb' debugger."
    HAS_LLDB=true
  elif check_util "gdb --version"; then
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
  if [ "$IS_REMOTE" = true ]; then
    REMOTE_ROOT="~/tmp_altivec"
    REMOTE_BUILD_DIR="$REMOTE_ROOT/$BUILD_DIR_NAME"
    echo "Preparing remote directory: $REMOTE_ROOT"
    ssh -o BatchMode=yes "$TARGET_DEVICE" "mkdir -p $REMOTE_ROOT"
    echo "Copying whole build directory to iPhone..."
    scp -r -o BatchMode=yes "$BUILD_DIR" "$TARGET_DEVICE:$REMOTE_ROOT/"
    INSTALL_PATH="$REMOTE_BUILD_DIR/$(basename "$PACKAGE_PATH")"
  else
    INSTALL_PATH="$BUILD_DIR/$(basename "$PACKAGE_PATH")"
  fi
  
  echo "Installing package: $(basename "$PACKAGE_PATH")"
  if [ "$IS_REMOTE" = true ]; then
    ssh -o BatchMode=yes "$TARGET_DEVICE" "ipainstaller $INSTALL_PATH"
  else
    ipainstaller "$INSTALL_PATH"
  fi
  echo "Deployment complete!"

elif [[ "$DEVICE_TYPE" == "mac" ]]; then
  if [ "$IS_REMOTE" = true ]; then
    REMOTE_ROOT="~/Desktop/Altivec"
    REMOTE_BUILD_DIR="$REMOTE_ROOT/$BUILD_DIR_NAME"
    echo "Preparing remote directory: $REMOTE_ROOT"
    ssh -o BatchMode=yes "$TARGET_DEVICE" "mkdir -p $REMOTE_ROOT"
    echo "Copying whole build directory to Mac..."
    scp -r -o BatchMode=yes "$BUILD_DIR" "$TARGET_DEVICE:$REMOTE_ROOT/"
    
    # Copy gdbinit if it exists
    if [ -f "altivec_build/gdbinit" ]; then
      echo "Uploading gdbinit..."
      scp -o BatchMode=yes "altivec_build/gdbinit" "$TARGET_DEVICE:$REMOTE_ROOT/gdbinit"
    fi
    
    APP_PATH="$REMOTE_BUILD_DIR/$(basename "$PACKAGE_PATH")"
  else
    APP_PATH="$(pwd)/$BUILD_DIR/$(basename "$PACKAGE_PATH")"
  fi
  
  EXECUTABLE_NAME=$(echo "$(basename "$PACKAGE_PATH")" | sed 's/\.app$//')
  BIN_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"

  echo "Deployment complete!"
  echo ""

  DEBUG_CMD=""
  if [[ "$HAS_LLDB" == true ]]; then
    DEBUG_CMD="lldb $BIN_PATH"
    DEBUG_NAME="LLDB"
  elif [[ "$HAS_GDB" == true ]]; then
    if [ "$IS_REMOTE" = true ]; then
      DEBUG_CMD="gdb -x $REMOTE_ROOT/gdbinit $BIN_PATH"
    else
      if [ -f "altivec_build/gdbinit" ]; then
        DEBUG_CMD="gdb -x altivec_build/gdbinit $BIN_PATH"
      else
        DEBUG_CMD="gdb $BIN_PATH"
      fi
    fi
    DEBUG_NAME="GDB"
  fi

  if [ -n "$DEBUG_CMD" ]; then
    echo "***************************************************"
    echo "  LAUNCHING $DEBUG_NAME"
    echo "  - Type 'run' to start the application."
    echo "  - Press Ctrl+C to pause/interrupt."
    echo "  - Type 'kill' to stop the process."
    echo "  - Type 'quit' to exit the debugger."
    if [ "$IS_REMOTE" = true ]; then
      echo ""
      echo "  NOTICE: Remote files will be deleted upon exit."
    fi
    echo "***************************************************"
    echo ""
    if [ "$IS_REMOTE" = true ]; then
      ssh -t "$TARGET_DEVICE" "$DEBUG_CMD"
    else
      $DEBUG_CMD
    fi
  else
    echo "***************************************************"
    echo "  PLEASE OPEN THE APP ON YOUR MAC NOW"
    if [ "$IS_REMOTE" = true ]; then
      echo "  Tailing /var/log/system.log (Press Ctrl+C to stop)..."
      echo "  NOTICE: Remote files will be deleted upon exit."
      echo "***************************************************"
      echo ""
      ssh "$TARGET_DEVICE" "tail -f /var/log/system.log"
    else
      echo "***************************************************"
    fi
  fi

  if [ "$IS_REMOTE" = true ]; then
    echo ""
    echo "Cleaning up remote Altivec folder..."
    ssh -o BatchMode=yes "$TARGET_DEVICE" "rm -rf $REMOTE_ROOT"
    echo "Mac cleanup complete."
  fi
fi
