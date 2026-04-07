#!/bin/bash

# --- CONSTANTS ---
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ALTIVEC_BUILD_DIR="$SCRIPT_DIR/altivec_build"
readonly GDBINIT_FILE="$ALTIVEC_BUILD_DIR/gdbinit"
readonly LLDBINIT_FILE="$ALTIVEC_BUILD_DIR/lldbinit"
readonly REMOTE_MAC_BASE="~/Desktop/Altivec"
readonly REMOTE_IOS_BASE="~/tmp_altivec"

# --- VARIABLES ---
# Arguments
INPUT_PATH=""
DEVICE_SSH_STR=""

# Application Preflight
APP_BUNDLE_PATH=""
APP_DIR=""
APP_IPA_PATH=""
APP_ZIP_PATH=""
APP_DSYM_PATHS=()
APP_NAME=""
APP_GDBINIT=""
APP_LLDBINIT=""

# Device Preflight
DEV_IS_REMOTE=false
DEV_SSH_CMD=""
DEV_OS=""      # Darwin
DEV_TYPE=""    # mac || ios
DEV_GDB=""     # path to gdb
DEV_LLDB=""    # path to lldb
DEV_LOG=""     # path to system log for tailing
DEV_LOG_MAC="" # path to /var/log/system.log
DEV_LOG_IOS="" # path to /var/log/syslog
DEV_APPINST="" # path to appinst
DEV_IPAINST="" # path to ipainstaller
DEV_NEEDS_CLEANUP=false # Flag to track if we've touched the remote device
NON_INTERACTIVE=false
TIMEOUT=60

# --- FUNCTIONS ---

# Portable timeout replacement for macOS/Linux
timeout_int() {
  local sec="$1"; shift
  # Use GNU timeout/gtimeout if available for efficiency
  if command -v timeout >/dev/null 2>&1; then
    timeout -s INT "$sec" "$@"
    return $?
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout -s INT "$sec" "$@"
    return $?
  fi

  # Fallback: Loop-based timer
  "$@" &
  local pid=$!
  local count=0
  
  # Check if process is alive every second
  while [ $count -lt "$sec" ]; do
    if ! kill -0 $pid 2>/dev/null; then
      wait $pid 2>/dev/null
      return $?
    fi
    sleep 1
    count=$((count + 1))
  done

  # Timeout reached: Kill process
  kill -TERM $pid 2>/dev/null
  sleep 2
  kill -KILL $pid 2>/dev/null
  wait $pid 2>/dev/null
  return 124
}

log_header() {
  echo ""
  echo "=== $1 ==="
}

log_item() {
  echo " > $1"
}

log_fail() {
  echo "[FAIL] $1"
}

log_instructions() {
  local type="$1"
  local is_remote="$2"
  echo ""
  echo "***************************************************"
  if [ "$type" = "debugger" ]; then
    echo "  DEBUGGER INSTRUCTIONS:"
    echo "  - Type 'run' to launch the app."
    echo "  - Press CTRL+C to pause the app."
    echo "  - Type 'kill' to kill the app."
    echo "  - Type 'quit' to exit the debugger."
    if [ "$is_remote" = "true" ]; then
      if [ "$DEV_TYPE" = "ios" ]; then
        echo "  Note: Temporary files have been deleted, but"
        echo "        the app will remain on the homescreen."
      else
        echo "  Note: Remote files will be deleted"
        echo "        automatically after quitting."
      fi
    fi
  elif [ "$type" = "logs" ]; then
    echo "  LOG INSTRUCTIONS:"
    echo "  - Press CTRL+C to stop tailing logs."
    if [ "$is_remote" = "true" ]; then
      if [ "$DEV_TYPE" = "ios" ]; then
        echo "  Note: Temporary files have been deleted, but"
        echo "        the app will remain on the homescreen."
      else
        echo "  Note: Remote files will be deleted"
        echo "        automatically after stopping."
      fi
    fi
  elif [ "$type" = "logsnone" ]; then
    echo "  NO LOGS FOUND:"
    echo "  - The app has been launched on the remote Mac."
    echo "  - No system log was found to tail."
    echo "  - Press CTRL+C to stop the app and cleanup."
    if [ "$is_remote" = "true" ]; then
      echo "  Note: Remote files will be deleted"
      echo "        automatically after stopping."
    fi
  fi
  echo "***************************************************"
  echo ""
}

# Robust utility check that respects exit codes and handles noisy 'which'
check_util_path() {
  local cmd="$1"
  local path=""
  if [ "$DEV_IS_REMOTE" = true ]; then
    # Use 'command -v' which is POSIX and more reliable than 'which'
    path=$($DEV_SSH_CMD "command -v $cmd" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$path" ]; then
      echo "$path"
      return 0
    fi
  else
    path=$(command -v "$cmd" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$path" ]; then
      echo "$path"
      return 0
    fi
  fi
  return 1
}

cleanup() {
  if [ "$DEV_NEEDS_CLEANUP" = true ]; then
    if [ "$DEV_TYPE" = "mac" ]; then
      echo "Stopping remote app..."
      $DEV_SSH_CMD "killall '$APP_NAME' 2>/dev/null"
      echo "Cleaning up remote Mac directory..."
      $DEV_SSH_CMD "rm -rf $REMOTE_MAC_BASE"
    elif [ "$DEV_TYPE" = "ios" ]; then
      echo "Cleaning up remote iPhone directory..."
      $DEV_SSH_CMD "rm -rf $REMOTE_IOS_BASE"
    fi
  fi
}

preflight_app() {
  log_header "Application Preflight"
  
  # Search for .app bundle
  if [ -d "$INPUT_PATH" ] && [[ "$INPUT_PATH" == *.app ]]; then
    APP_BUNDLE_PATH="$INPUT_PATH"
  else
    APP_BUNDLE_PATH=$(find "$INPUT_PATH" -maxdepth 2 -name "*.app" -type d -print -quit)
  fi

  if [ -z "$APP_BUNDLE_PATH" ]; then
    log_fail "Could not find .app bundle in $INPUT_PATH"
    return 1
  fi
  log_item "Found App: $APP_BUNDLE_PATH"

  APP_DIR=$(dirname "$APP_BUNDLE_PATH")
  APP_NAME=$(basename "$APP_BUNDLE_PATH" .app)
  
  # Search for payload
  APP_IPA_PATH=$(find "$APP_DIR" -maxdepth 1 -name "*.ipa" -print -quit)
  APP_ZIP_PATH=$(find "$APP_DIR" -maxdepth 1 -name "*.zip" -print -quit)
  
  if [ -n "$APP_IPA_PATH" ]; then log_item "Found IPA: $(basename "$APP_IPA_PATH")"; fi
  if [ -n "$APP_ZIP_PATH" ]; then log_item "Found ZIP: $(basename "$APP_ZIP_PATH")"; fi
  
  # Search for dSYMs
  while IFS= read -r dsym; do
    if [ -n "$dsym" ]; then
      APP_DSYM_PATHS+=("$dsym")
      log_item "Found dSYM: $(basename "$dsym")"
    fi
  done < <(find "$APP_DIR" -maxdepth 1 -name "*.dSYM")

  # Debugger inits
  if [ -f "$GDBINIT_FILE" ]; then APP_GDBINIT="$GDBINIT_FILE"; log_item "Found gdbinit"; fi
  if [ -f "$LLDBINIT_FILE" ]; then APP_LLDBINIT="$LLDBINIT_FILE"; log_item "Found lldbinit"; fi

  return 0
}

preflight_device() {
  local uname_out=""
  local mobile_check=""
  
  log_header "Device Preflight"

  if [ -n "$DEVICE_SSH_STR" ]; then
    DEV_IS_REMOTE=true
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$DEVICE_SSH_STR" "exit" 2>/dev/null; then
      log_fail "SSH connection to '$DEVICE_SSH_STR' failed"
      echo "       Run 'ssh $DEVICE_SSH_STR' to debug the errors"
      echo "       Note: Key authentication is required for this script"
      return 1
    fi
    DEV_SSH_CMD="ssh $DEVICE_SSH_STR"
    log_item "SSH Connection: OK"
  else
    DEV_IS_REMOTE=false
    log_item "Local Deployment"
  fi

  # Determine OS
  if [ "$DEV_IS_REMOTE" = true ]; then
    uname_out=$($DEV_SSH_CMD "uname")
  else
    uname_out=$(uname)
  fi
  DEV_OS="$uname_out"
  log_item "OS: $DEV_OS"

  # Determine Device Type
  if [ "$DEV_OS" = "Darwin" ]; then
    if [ "$DEV_IS_REMOTE" = true ]; then
      mobile_check=$($DEV_SSH_CMD "[ -d /var/mobile ] && echo 'ios' || echo 'mac'")
    else
      [ -d /var/mobile ] && mobile_check="ios" || mobile_check="mac"
    fi
  else
    mobile_check="$DEV_OS"
  fi
  DEV_TYPE="$mobile_check"
  log_item "Type: $DEV_TYPE"

  # Find Utilities Robustly
  DEV_GDB=$(check_util_path "gdb")
  DEV_LLDB=$(check_util_path "lldb")
  DEV_APPINST=$(check_util_path "appinst")
  DEV_IPAINST=$(check_util_path "ipainstaller")

  [ -n "$DEV_GDB" ] && log_item "GDB: $DEV_GDB" || log_item "GDB: Not found"
  [ -n "$DEV_LLDB" ] && log_item "LLDB: $DEV_LLDB" || log_item "LLDB: Not found"
  [ -n "$DEV_APPINST" ] && log_item "appinst: $DEV_APPINST" || log_item "appinst: Not found"
  [ -n "$DEV_IPAINST" ] && log_item "ipainstaller: $DEV_IPAINST" || log_item "ipainstaller: Not found"
  
  # Find Logs
  if [ "$DEV_IS_REMOTE" = true ]; then
    DEV_LOG_MAC=$($DEV_SSH_CMD "[ -f /var/log/system.log ] && echo '/var/log/system.log'")
    DEV_LOG_IOS=$($DEV_SSH_CMD "[ -f /var/log/syslog ] && echo '/var/log/syslog'")
  else
    [ -f /var/log/system.log ] && DEV_LOG_MAC="/var/log/system.log"
    [ -f /var/log/syslog ] && DEV_LOG_IOS="/var/log/syslog"
  fi

  [ -n "$DEV_LOG_MAC" ] && log_item "Syslog (Mac): $DEV_LOG_MAC" || log_item "Syslog (Mac): Not found"
  [ -n "$DEV_LOG_IOS" ] && log_item "Syslog (iOS): $DEV_LOG_IOS" || log_item "Syslog (iOS): Not found"

  # Pick best log for tailing (Prefer Mac log)
  DEV_LOG="${DEV_LOG_MAC:-$DEV_LOG_IOS}"

  return 0
  }
preflight_go_nogo() {
  # 1. Check OS/Type
  if [[ "$DEV_TYPE" != "mac" && "$DEV_TYPE" != "ios" ]]; then
    log_fail "Unable to deploy Mac or iOS app to Linux"
    echo "       Use -d to specify a remote device deployment with ssh"
    return 1
  fi

  # 2. Match App to Device
  if [ "$DEV_TYPE" = "mac" ]; then
    if [ -n "$APP_IPA_PATH" ]; then
      log_fail "Unable to deploy iOS app (ipa) to a Mac"
      echo "       Use -d to specify a remote device deployment with ssh"
      return 1
    fi
    if [ "$DEV_IS_REMOTE" = true ] && [ -z "$APP_ZIP_PATH" ]; then
      log_fail "Remote Mac deployment requires a .zip payload. None found in $APP_DIR"
      return 1
    fi
  fi

  if [ "$DEV_TYPE" = "ios" ]; then
    if [ -z "$APP_IPA_PATH" ]; then
      log_fail "iPhone deployment requires an .ipa payload. None found in $APP_DIR"
      return 1
    fi
    if [ -z "$DEV_APPINST" ] && [ -z "$DEV_IPAINST" ]; then
      log_fail "No iPhone installer found (appinst or ipainstaller)."
      echo "       Please install one of these utilities on your device."
      return 1
    fi
  fi

  return 0
}

preflight_summary() {
  local choice=""
  log_header "Deployment Summary"
  
  if ! preflight_go_nogo; then
    return 1
  fi
  
  if [ "$DEV_IS_REMOTE" = false ]; then
    log_item "Action: Local launch of $APP_NAME"
  elif [ "$DEV_TYPE" = "mac" ]; then
    log_item "Action: Deploy $APP_NAME to Remote Mac ($DEVICE_SSH_STR)"
    log_item "Transfer: $(basename "$APP_ZIP_PATH"), ${#APP_DSYM_PATHS[@]} dSYMs, and debugger inits"
  elif [ "$DEV_TYPE" = "ios" ]; then
    log_item "Action: Deploy $APP_NAME to Remote iPhone ($DEVICE_SSH_STR)"
    log_item "Transfer: $(basename "$APP_IPA_PATH")"
  fi

  if [ "$NON_INTERACTIVE" = true ]; then
    log_item "Continuing automatically (--yes set)"
    return 0
  fi

  echo ""
  read -p "Continue with deployment? (Y/n): " choice
  if [[ ! "$choice" =~ ^[Yy]$ ]] && [ -n "$choice" ]; then
    echo "Aborted."
    exit 0
  fi
}

execute_local() {
  local bin_path="$APP_BUNDLE_PATH/Contents/MacOS/$APP_NAME"
  
  if [ "$NON_INTERACTIVE" = false ] && [ -n "$DEV_LLDB" ]; then
    log_instructions "debugger"
    # Use exec to replace the shell process with the debugger.
    # This ensures that signals (like Ctrl+C) are handled directly by LLDB.
    exec lldb -s "$APP_LLDBINIT" "$bin_path"
  elif [ "$NON_INTERACTIVE" = false ] && [ -n "$DEV_GDB" ]; then
    log_instructions "debugger"
    exec gdb -x "$APP_GDBINIT" "$bin_path"
  else
    if [ "$NON_INTERACTIVE" = true ]; then
      echo "Executing $APP_NAME for $TIMEOUT seconds (--yes)..."
      timeout_int $TIMEOUT "$bin_path" || true
    else
      open "$APP_BUNDLE_PATH"
      if [ -n "$DEV_LOG" ]; then
        log_instructions "logs"
        tail -f "$DEV_LOG" | grep --line-buffered "$APP_NAME"
      fi
    fi
  fi
}

execute_remote_mac() {
  local remote_app_path="$REMOTE_MAC_BASE/$APP_NAME.app"
  local remote_bin_path="$remote_app_path/Contents/MacOS/$APP_NAME"
  local transfer_list=()
  
  $DEV_SSH_CMD "mkdir -p $REMOTE_MAC_BASE"
  DEV_NEEDS_CLEANUP=true
  
  # Prepare transfer list
  transfer_list+=("$APP_ZIP_PATH")
  for dsym in "${APP_DSYM_PATHS[@]}"; do
    transfer_list+=("$dsym")
  done
  [ -f "$APP_GDBINIT" ] && transfer_list+=("$APP_GDBINIT")
  [ -f "$APP_LLDBINIT" ] && transfer_list+=("$APP_LLDBINIT")

  # Perform a single transfer
  echo "Transferring files to remote Mac..."
  scp -O -r "${transfer_list[@]}" "$DEVICE_SSH_STR:$REMOTE_MAC_BASE/"
  
  # Unzip on remote
  $DEV_SSH_CMD "cd $REMOTE_MAC_BASE && unzip -o $(basename "$APP_ZIP_PATH")"
  
  if [ "$NON_INTERACTIVE" = false ] && [ -n "$DEV_LLDB" ]; then
    log_instructions "debugger" "true"
    $DEV_SSH_CMD -t "lldb -s $REMOTE_MAC_BASE/lldbinit $remote_bin_path"
  elif [ "$NON_INTERACTIVE" = false ] && [ -n "$DEV_GDB" ]; then
    log_instructions "debugger" "true"
    $DEV_SSH_CMD -t "gdb -x $REMOTE_MAC_BASE/gdbinit $remote_bin_path"
  else
    if [ "$NON_INTERACTIVE" = true ]; then
      echo "Executing $APP_NAME on remote Mac for $TIMEOUT seconds (--yes)..."
      timeout_int $TIMEOUT $DEV_SSH_CMD "$remote_bin_path" || true
    else
      $DEV_SSH_CMD "open $remote_app_path"
      if [ -n "$DEV_LOG" ]; then
        log_instructions "logs" "true"
        $DEV_SSH_CMD "tail -f $DEV_LOG | grep --line-buffered $APP_NAME"
      else
        log_instructions "logsnone" "true"
        # Wait for the user to press CTRL+C
        while true; do sleep 1; done
      fi
    fi
  fi
}

execute_remote_iphone() {
  local ipa_name=$(basename "$APP_IPA_PATH")
  local install_cmd=""
  
  $DEV_SSH_CMD "mkdir -p $REMOTE_IOS_BASE"
  DEV_NEEDS_CLEANUP=true
  scp -O "$APP_IPA_PATH" "$DEVICE_SSH_STR:$REMOTE_IOS_BASE/"
  
  if [ -n "$DEV_APPINST" ]; then
    install_cmd="appinst $REMOTE_IOS_BASE/$ipa_name"
  else
    install_cmd="ipainstaller $REMOTE_IOS_BASE/$ipa_name"
  fi
  
  $DEV_SSH_CMD "$install_cmd"
  $DEV_SSH_CMD "rm $REMOTE_IOS_BASE/$ipa_name"
  
  if [ -n "$DEV_LOG" ]; then
    log_instructions "logs" "true"
    echo "Tailing logs for $APP_NAME..."
    if [ "$NON_INTERACTIVE" = true ]; then
      echo "Tailing logs for $TIMEOUT seconds (--yes)..."
      timeout_int $TIMEOUT $DEV_SSH_CMD "tail -f $DEV_LOG | grep --line-buffered $APP_NAME" || true
    else
      $DEV_SSH_CMD "tail -f $DEV_LOG | grep --line-buffered $APP_NAME"
    fi
  fi
}

# --- MAIN ---

trap cleanup EXIT

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <path_to_app_or_build_dir> [-d <user@host>] [-y|--yes]"
  exit 1
fi

INPUT_PATH="$1"
shift

while [[ "$#" -gt 0 ]]; do
  case $1 in
    -d|--device) DEVICE_SSH_STR="$2"; shift ;;
    -y|--yes) 
      NON_INTERACTIVE=true
      if [[ "$2" =~ ^[0-9]+$ ]]; then
        TIMEOUT="$2"
        shift
      fi
      ;;
    *) log_fail "Unknown argument: $1"; exit 1 ;;
  esac
  shift
done

if ! preflight_app; then exit 1; fi
if ! preflight_device; then exit 1; fi
if ! preflight_summary; then exit 1; fi

if [ "$DEV_IS_REMOTE" = false ]; then
  execute_local
elif [ "$DEV_TYPE" = "mac" ]; then
  execute_remote_mac
elif [ "$DEV_TYPE" = "ios" ]; then
  execute_remote_iphone
fi

exit 0
