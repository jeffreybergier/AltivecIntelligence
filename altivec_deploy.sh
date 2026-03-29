#!/usr/bin/env bash

# AltivecIntelligence Deployment Script
# Usage: ./altivec_deploy.sh <app_dir_or_build_dir> [-d <ssh_host>]

set -e

# Initialize variables
TARGET_DEVICE=""
INPUT_PATH=""
REMOTE_ROOT=""

# --- Cleanup Logic ---
cleanup() {
  if [ "$IS_REMOTE" = true ] && [ -n "$REMOTE_ROOT" ]; then
    echo ""
    echo "Cleaning up remote Altivec folder ($REMOTE_ROOT)..."
    ssh -o ConnectTimeout=5 "$TARGET_DEVICE" "rm -rf \"$REMOTE_ROOT\""
    echo "Cleanup complete."
  fi
}
trap cleanup EXIT

# --- Argument Parsing ---
if [[ "$#" -gt 0 ]] && [[ ! "$1" == -* ]]; then
  INPUT_PATH="$1"
  shift
fi

while [[ "$#" -gt 0 ]]; do
  case $1 in
    -d|--device) TARGET_DEVICE="$2"; shift ;;
    *) echo "Unknown parameter passed: $1"; exit 1 ;;
  esac
  shift
done

# --- Resolve Build Directory ---
if [ -z "$INPUT_PATH" ]; then
  echo "[FAIL] Missing required <app_dir> argument."
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
  REMOTE_INFO=$(ssh "$TARGET_DEVICE" "uname -sm; [ -d /var/mobile ] && echo 'iOS' || echo 'macOS'")
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

DEVICE_TYPE="unknown"
if [[ "$UNAME_OUTPUT" == Darwin* ]]; then
  if [[ "$TYPE_HINT" == "iOS" ]]; then
    DEVICE_TYPE="iphone"
  else
    DEVICE_TYPE="mac"
  fi
fi
echo "[OK] Detected Device Type: $DEVICE_TYPE ($UNAME_OUTPUT)"

# --- Preflight ---
echo ""
echo "--- PREFLIGHT CHECK ---"
if [[ "$DEVICE_TYPE" == "mac" ]]; then
  PACKAGE_PATH=$(find "$BUILD_DIR" -name "*.app" -maxdepth 1 | head -n 1)
elif [[ "$DEVICE_TYPE" == "iphone" ]]; then
  PACKAGE_PATH=$(find "$BUILD_DIR" -name "*.ipa" -maxdepth 1 | head -n 1)
fi

if [ -z "$PACKAGE_PATH" ]; then
  echo "[FAIL] Could not find suitable package in '$BUILD_DIR'."
  exit 1
fi
echo "[OK] Found package: $(basename "$PACKAGE_PATH")"

# --- Utility Checks ---
echo ""
echo "--- UTILITY CHECK ---"
HAS_IPAINSTALLER=false
HAS_LLDB=false
HAS_GDB=false
HAS_SYSLOG=false

check_util() {
  if [ "$IS_REMOTE" = true ]; then
    ssh "$TARGET_DEVICE" "$1" &>/dev/null
  else
    eval "$1" &>/dev/null
  fi
}

if [[ "$DEVICE_TYPE" == "iphone" ]]; then
  if check_util "which ipainstaller"; then
    echo "[OK] found 'ipainstaller'."
    HAS_IPAINSTALLER=true
  else
    echo "[FAIL] 'ipainstaller' NOT found."
    exit 1
  fi
  if check_util "[ -f /var/log/syslog ]"; then
    echo "[OK] found '/var/log/syslog'."
    HAS_SYSLOG=true
  fi
elif [[ "$DEVICE_TYPE" == "mac" ]]; then
  if check_util "lldb --version"; then
    echo "[OK] found 'lldb'."
    HAS_LLDB=true
  elif check_util "gdb --version"; then
    echo "[OK] found 'gdb'."
    HAS_GDB=true
  fi
fi

echo ""
echo "--- DEPLOYMENT STARTING ---"
BUILD_DIR_NAME=$(basename "$BUILD_DIR")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$DEVICE_TYPE" == "iphone" ]]; then
  if [ "$IS_REMOTE" = true ]; then
    REMOTE_ROOT="/var/mobile/tmp_altivec"
    REMOTE_BUILD_DIR="$REMOTE_ROOT/$BUILD_DIR_NAME"
    echo "Preparing remote directory: $REMOTE_ROOT"
    ssh "$TARGET_DEVICE" "mkdir -p \"$REMOTE_ROOT\""
    echo "Copying build to iPhone..."
    scp -O -r "$BUILD_DIR" "$TARGET_DEVICE:\"$REMOTE_ROOT/\""
    INSTALL_PATH="$REMOTE_BUILD_DIR/$(basename "$PACKAGE_PATH")"
  else
    INSTALL_PATH="$BUILD_DIR/$(basename "$PACKAGE_PATH")"
  fi
  
  echo "Installing package: $(basename "$PACKAGE_PATH")..."
  set +e
  if [ "$IS_REMOTE" = true ]; then
    ssh "$TARGET_DEVICE" "ipainstaller \"$INSTALL_PATH\""
  else
    ipainstaller "$INSTALL_PATH"
  fi
  set -e
  echo "Deployment complete!"

  if [ "$HAS_SYSLOG" = true ]; then
    echo ""
    echo "***************************************************"
    echo "  PLEASE OPEN THE APP ON YOUR IPHONE NOW"
    echo "  Tailing /var/log/syslog (Press Ctrl+C to stop)..."
    echo "***************************************************"
    echo ""
    if [ "$IS_REMOTE" = true ]; then
      ssh "$TARGET_DEVICE" "tail -f /var/log/syslog"
    else
      tail -f /var/log/syslog
    fi
  fi

elif [[ "$DEVICE_TYPE" == "mac" ]]; then
  if [ "$IS_REMOTE" = true ]; then
    HOME_PATH=$(ssh "$TARGET_DEVICE" "echo \$HOME")
    REMOTE_ROOT="$HOME_PATH/Desktop/Altivec_Tmp"
    REMOTE_BUILD_DIR="$REMOTE_ROOT/$BUILD_DIR_NAME"
    echo "Preparing remote directory: $REMOTE_ROOT"
    ssh "$TARGET_DEVICE" "mkdir -p \"$REMOTE_ROOT\""
    echo "Copying build to Mac..."
    scp -O -r "$BUILD_DIR" "$TARGET_DEVICE:\"$REMOTE_ROOT/\""
    
    # Upload appropriate debugger init
    if [ "$HAS_LLDB" = true ] && [ -f "$SCRIPT_DIR/altivec_build/lldbinit" ]; then
      scp -O -q "$SCRIPT_DIR/altivec_build/lldbinit" "$TARGET_DEVICE:\"$REMOTE_ROOT/lldbinit\""
    elif [ "$HAS_GDB" = true ] && [ -f "$SCRIPT_DIR/altivec_build/gdbinit" ]; then
      scp -O -q "$SCRIPT_DIR/altivec_build/gdbinit" "$TARGET_DEVICE:\"$REMOTE_ROOT/gdbinit\""
    fi
    
    APP_PATH="$REMOTE_BUILD_DIR/$(basename "$PACKAGE_PATH")"
  else
    APP_PATH="$(pwd)/$BUILD_DIR/$(basename "$PACKAGE_PATH")"
  fi
  
  EXECUTABLE_NAME=$(echo "$(basename "$PACKAGE_PATH")" | sed 's/\.app$//')
  BIN_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
  echo "Deployment complete!"

  DEBUG_CMD=""
  if [[ "$HAS_LLDB" == true ]]; then
    if [ "$IS_REMOTE" = true ]; then
      [ -f "$SCRIPT_DIR/altivec_build/lldbinit" ] && DBG_INIT="-s \"$REMOTE_ROOT/lldbinit\"" || DBG_INIT=""
    else
      [ -f "$SCRIPT_DIR/altivec_build/lldbinit" ] && DBG_INIT="-s \"$SCRIPT_DIR/altivec_build/lldbinit\"" || DBG_INIT=""
    fi
    DEBUG_CMD="lldb $DBG_INIT \"$BIN_PATH\""
    DEBUG_NAME="LLDB"
  elif [[ "$HAS_GDB" == true ]]; then
    if [ "$IS_REMOTE" = true ]; then
      [ -f "$SCRIPT_DIR/altivec_build/gdbinit" ] && DBG_INIT="-x \"$REMOTE_ROOT/gdbinit\"" || DBG_INIT=""
    else
      [ -f "$SCRIPT_DIR/altivec_build/gdbinit" ] && DBG_INIT="-x \"$SCRIPT_DIR/altivec_build/gdbinit\"" || DBG_INIT=""
    fi
    DEBUG_NAME="GDB"
    DEBUG_CMD="gdb $DBG_INIT \"$BIN_PATH\""
  fi

  if [ -n "$DEBUG_CMD" ]; then
    echo ""
    echo "***************************************************"
    echo "  LAUNCHING $DEBUG_NAME"
    echo "  - Type 'run' to start."
    echo "  - Press Ctrl+C to pause."
    echo "  - Type 'quit' to exit."
    echo "***************************************************"
    echo ""
    if [ "$IS_REMOTE" = true ]; then
      ssh -t "$TARGET_DEVICE" "$DEBUG_CMD"
    else
      eval "$DEBUG_CMD"
    fi
  else
    if [ "$IS_REMOTE" = true ]; then
      echo "No debugger found. Tailing /var/log/system.log..."
      ssh "$TARGET_DEVICE" "tail -f /var/log/system.log"
    fi
  fi
fi
