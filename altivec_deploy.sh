#!/usr/bin/env bash

# AltivecIntelligence Deployment Script
# Usage: ./altivec_deploy.sh <app_dir_or_package> [-d <ssh_host>]

set -e

# --- Constants: Paths and Commands ---
IPHONE_REMOTE_DEST="~/Altivec"
MAC_REMOTE_DEST="~/Desktop/Altivec"

CMD_UNAME="uname -sm"
CMD_IOS_HINT="[ -d /var/mobile ] && echo 'iOS' || echo 'macOS'"
CMD_WHICH_APPINST="which appinst"
CMD_WHICH_IPAINSTALLER="which ipainstaller"
CMD_CHECK_SYSLOG="[ -f /var/log/syslog ]"
CMD_LLDB_VERSION="lldb --version"
CMD_GDB_VERSION="gdb --version"

# --- Variables: State and Arguments ---
TARGET_DEVICE=""
INPUT_PATH=""
REMOTE_ROOT=""
IS_REMOTE=false
DEVICE_TYPE="unknown" # "iphone" or "mac"
APP_TYPE="unknown"    # "ipa" or "zip"
APP_PATH=""           # Path to the .ipa or .zip file
FILES_TO_COPY=()

HAS_APPINST=false
HAS_IPAINSTALLER=false
HAS_LLDB=false
HAS_GDB=false
HAS_SYSLOG=false

# --- Cleanup Logic ---
cleanup() {
  if [ "$IS_REMOTE" = true ] && [ -n "$REMOTE_ROOT" ]; then
    echo ""
    echo "Cleaning up remote Altivec folder ($REMOTE_ROOT)..."
    ssh -o ConnectTimeout=5 "$TARGET_DEVICE" "rm -rf '$REMOTE_ROOT'"
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

if [ -z "$INPUT_PATH" ]; then
  echo "[FAIL] Missing required <app_dir_or_package> argument."
  exit 1
fi

# --- Discover Package and dSYMs ---
echo "--- DISCOVERING PACKAGE ---"

find_package_in_dir() {
  local dir="$1"
  # Priority: .ipa then .zip
  find "$dir" -maxdepth 1 \( -name "*.ipa" -o -name "*.zip" \) | head -n 1
}

if [ -f "$INPUT_PATH" ]; then
  APP_PATH="$INPUT_PATH"
elif [ -d "$INPUT_PATH" ]; then
  if [[ "$INPUT_PATH" == *.app ]]; then
     echo "[FAIL] Path is a .app bundle. Please pass the folder containing it or a .zip/.ipa."
     exit 1
  fi
  
  # 1. Check directly in folder
  APP_PATH=$(find_package_in_dir "$INPUT_PATH")
  
  # 2. Check in build* folders
  if [ -z "$APP_PATH" ]; then
    FIRST_BUILD_DIR=$(find "$INPUT_PATH" -maxdepth 1 -type d -name "build*" | head -n 1)
    if [ -n "$FIRST_BUILD_DIR" ]; then
      echo "[OK] Found build directory: $FIRST_BUILD_DIR"
      APP_PATH=$(find_package_in_dir "$FIRST_BUILD_DIR")
    fi
  fi
else
  echo "[FAIL] Input path '$INPUT_PATH' not found."
  exit 1
fi

if [ -z "$APP_PATH" ]; then
  echo "[FAIL] Could not find any .zip or .ipa in '$INPUT_PATH' or its build subdirectories."
  exit 1
fi

# Determine APP_TYPE
if [[ "$APP_PATH" == *.ipa ]]; then
  APP_TYPE="ipa"
elif [[ "$APP_PATH" == *.zip ]]; then
  APP_TYPE="zip"
else
  echo "[FAIL] Found file '$APP_PATH' but it is not a .zip or .ipa."
  exit 1
fi

echo "[OK] Found package ($APP_TYPE): $APP_PATH"
FILES_TO_COPY+=("$APP_PATH")

# Find dSYMs in the same directory
PACKAGE_DIR=$(dirname "$APP_PATH")
while IFS= read -r dsym; do
  if [ -n "$dsym" ]; then
    echo "[OK] Found dSYM: $(basename "$dsym")"
    FILES_TO_COPY+=("$dsym")
  fi
done < <(find "$PACKAGE_DIR" -maxdepth 1 -name "*.dSYM")

# --- Determine Mode (Remote vs Local) ---
if [ -n "$TARGET_DEVICE" ]; then
  IS_REMOTE=true
  echo ""
  echo "--- REMOTE CONNECTION CHECK ($TARGET_DEVICE) ---"
else
  echo ""
  echo "--- LOCAL MODE CHECK ---"
fi

# 1. Connection & OS Info
if [ "$IS_REMOTE" = true ]; then
  set +e
  REMOTE_INFO=$(ssh "$TARGET_DEVICE" "$CMD_UNAME; $CMD_IOS_HINT")
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
  UNAME_OUTPUT=$($CMD_UNAME)
  if [ -d /var/mobile ]; then TYPE_HINT="iOS"; else TYPE_HINT="macOS"; fi
fi

if [[ "$UNAME_OUTPUT" == Darwin* ]]; then
  if [[ "$TYPE_HINT" == "iOS" ]]; then
    DEVICE_TYPE="iphone"
  else
    DEVICE_TYPE="mac"
  fi
fi
echo "[OK] Detected Device Type: $DEVICE_TYPE ($UNAME_OUTPUT)"

# --- Final Validation: App Type vs Device Type ---
if [[ "$DEVICE_TYPE" == "iphone" ]] && [[ "$APP_TYPE" != "ipa" ]]; then
  echo "[FAIL] iPhone requires an .ipa package, but found '$APP_TYPE'."
  exit 1
fi

if [[ "$DEVICE_TYPE" == "mac" ]] && [[ "$APP_TYPE" != "zip" ]]; then
  echo "[FAIL] Mac requires a .zip package, but found '$APP_TYPE'."
  exit 1
fi

# --- Utility Checks ---
echo ""
echo "--- UTILITY CHECK ---"

check_util() {
  if [ "$IS_REMOTE" = true ]; then
    ssh "$TARGET_DEVICE" "$1" &>/dev/null
  else
    eval "$1" &>/dev/null
  fi
}

if [[ "$DEVICE_TYPE" == "iphone" ]]; then
  if check_util "$CMD_WHICH_APPINST"; then
    echo "[OK] found 'appinst'."
    HAS_APPINST=true
  fi
  if check_util "$CMD_WHICH_IPAINSTALLER"; then
    echo "[OK] found 'ipainstaller'."
    HAS_IPAINSTALLER=true
  fi

  if [ "$HAS_APPINST" = false ] && [ "$HAS_IPAINSTALLER" = false ]; then
    echo "[FAIL] Neither 'appinst' nor 'ipainstaller' found."
    exit 1
  fi

  if check_util "$CMD_CHECK_SYSLOG"; then
    echo "[OK] found '/var/log/syslog'."
    HAS_SYSLOG=true
  fi
elif [[ "$DEVICE_TYPE" == "mac" ]]; then
  if check_util "$CMD_LLDB_VERSION"; then
    echo "[OK] found 'lldb'."
    HAS_LLDB=true
  elif check_util "$CMD_GDB_VERSION"; then
    echo "[OK] found 'gdb'."
    HAS_GDB=true
  fi
fi

echo ""
echo "--- DEPLOYMENT STARTING ---"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$DEVICE_TYPE" == "iphone" ]]; then
  if [ "$IS_REMOTE" = true ]; then
    REMOTE_ROOT="$IPHONE_REMOTE_DEST"
    echo "Preparing remote directory: $REMOTE_ROOT"
    ssh "$TARGET_DEVICE" "mkdir -p \"$REMOTE_ROOT\""
    echo "Copying files to iPhone..."
    scp -r "${FILES_TO_COPY[@]}" "$TARGET_DEVICE:$REMOTE_ROOT/"
    INSTALL_PATH="$REMOTE_ROOT/$(basename "$APP_PATH")"
  else
    INSTALL_PATH="$APP_PATH"
  fi
  
  echo "Installing package: $(basename "$APP_PATH")..."
  set +e
  INSTALL_CMD=""
  if [ "$HAS_APPINST" = true ]; then
    INSTALL_CMD="appinst \"$INSTALL_PATH\""
  else
    INSTALL_CMD="ipainstaller \"$INSTALL_PATH\""
  fi

  if [ "$IS_REMOTE" = true ]; then
    ssh "$TARGET_DEVICE" "$INSTALL_CMD"
  else
    eval "$INSTALL_CMD"
  fi
  set -e
  echo "Deployment complete!"

  if [ "$HAS_SYSLOG" = true ]; then
    APP_NAME=$(basename "$APP_PATH" | sed 's/\.ipa$//')
    echo ""
    echo "***************************************************"
    echo "  PLEASE OPEN THE APP ON YOUR IPHONE NOW"
    echo "  Filtering syslog for: $APP_NAME"
    echo "  (Press Ctrl+C to stop)..."
    echo "***************************************************"
    echo ""
    if [ "$IS_REMOTE" = true ]; then
      ssh "$TARGET_DEVICE" "tail -f /var/log/syslog | grep --line-buffered \"$APP_NAME\""
    else
      tail -f /var/log/syslog | grep --line-buffered "$APP_NAME"
    fi
  fi

elif [[ "$DEVICE_TYPE" == "mac" ]]; then
  if [ "$IS_REMOTE" = true ]; then
    REMOTE_ROOT="$MAC_REMOTE_DEST"
    echo "Preparing remote directory: $REMOTE_ROOT"
    ssh "$TARGET_DEVICE" "mkdir -p \"$REMOTE_ROOT\""
    echo "Copying files to Mac..."
    scp -r "${FILES_TO_COPY[@]}" "$TARGET_DEVICE:$REMOTE_ROOT/"
    
    # Upload appropriate debugger init
    if [ "$HAS_LLDB" = true ] && [ -f "$SCRIPT_DIR/altivec_build/lldbinit" ]; then
      scp -q "$SCRIPT_DIR/altivec_build/lldbinit" "$TARGET_DEVICE:$REMOTE_ROOT/lldbinit"
    elif [ "$HAS_GDB" = true ] && [ -f "$SCRIPT_DIR/altivec_build/gdbinit" ]; then
      scp -q "$SCRIPT_DIR/altivec_build/gdbinit" "$TARGET_DEVICE:$REMOTE_ROOT/gdbinit"
    fi
    
    echo "Unzipping package on remote..."
    ssh "$TARGET_DEVICE" "cd \"$REMOTE_ROOT\" && unzip -o \"$(basename "$APP_PATH")\""
    UNZIPPED_APP_PATH=$(ssh "$TARGET_DEVICE" "find \"$REMOTE_ROOT\" -name \"*.app\" -type d -maxdepth 2 | head -n 1")
  else
    # Local mode logic
    APP_DIR=$(dirname "$APP_PATH")
    unzip -o "$APP_PATH" -d "$APP_DIR"
    UNZIPPED_APP_PATH=$(find "$APP_DIR" -name "*.app" -type d -maxdepth 2 | head -n 1)
  fi
  
  EXECUTABLE_NAME=$(basename "$UNZIPPED_APP_PATH" | sed 's/\.app$//')
  BIN_PATH="$UNZIPPED_APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
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
