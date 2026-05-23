#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[altivec_chooser.main] aborted"; exit 130' INT

log() {
  printf '[altivec_chooser.%s] %s\n' "$1" "$2"
}


show_banner() {
  local pink='\033[38;5;205m'
  local cyan='\033[38;5;44m'
  local blue='\033[38;5;117m'
  local black='\033[38;5;16m'
  local purple='\033[38;5;141m'
  local border="+------------------------------------------------------------------------------+"

  printf '%b%s%b\n' "$pink" "$border" '\033[0m'
  printf '%b|%s|%b\n' "$pink"   "                     <*> * . * . * . <*> * . * . * . * . *                    " '\033[0m'
  printf '%b|%s|%b\n' "$black"  "              (/\\_/) Ａｌｔｉｖｅｃ　Ｉｎｔｅｌｌｉｇｅｎｃｅ (/\\_/)          " '\033[0m'
  printf '%b|%s|%b\n' "$cyan"   "              ( o.o )       Retro development made fun       ( o.o )          " '\033[0m'
  printf '%b|%s|%b\n' "$blue"   "               / >[]        . * . * . * . * . * . * .         []< \\           " '\033[0m'
  printf '%b|%s|%b\n' "$purple" "                        . * . * . * . * . * . * . * . * .                     " '\033[0m'
  printf '%b%s%b\n' "$cyan" "$border" '\033[0m'
}

require_cmd() {
  local name="$1"

  if command -v "$name" >/dev/null 2>&1; then
    return 0
  fi

  log "require_cmd" "Missing dependency: $name"
  exit 1
}

launch_claude() {
  local npm_root=""
  local claude_bin=""
  local claude_wrapper=""

  npm_root="$(npm root -g)"
  claude_bin="$npm_root/@anthropic-ai/claude-code/bin/claude.exe"
  claude_wrapper="$npm_root/@anthropic-ai/claude-code/cli-wrapper.cjs"

  if [[ -x "$claude_bin" ]]; then
    exec "$claude_bin" --dangerously-skip-permissions
  fi

  if [[ -f "$claude_wrapper" ]]; then
    exec node "$claude_wrapper" --dangerously-skip-permissions
  fi

  log "launch_claude" "Claude install is incomplete after npm update"
  exit 1
}

launch_standard() {
  local cmd="$1"
  local flag="${2:-}"

  require_cmd "$cmd"

  if [[ -n "$flag" ]]; then
    exec "$cmd" "$flag"
  else
    exec "$cmd"
  fi
}

require_cmd npm
require_cmd node

echo ""
show_banner
echo "Select an AI agent:"
echo "  1) Claude (@anthropic-ai/claude-code)"
echo "  2) Codex  (@openai/codex)"
echo "  3) Antigravity (Google) (agy)"
echo "  4) Pi       (Advanced) (@earendil-works/pi-coding-agent)"
echo "  5) OpenCode (Advanced) (@opencode-ai)"
echo ""
read -rp "Choice [1-5]: " choice

case "$choice" in
  1)
    pkg="@anthropic-ai/claude-code"
    launcher="launch_claude"
    ;;
  2)
    pkg="@openai/codex"
    launcher="launch_standard codex --yolo"
    ;;
  3)
    pkg=""
    launcher="launch_standard agy --dangerously-skip-permissions"
    ;;
  4)
    pkg="@earendil-works/pi-coding-agent"
    launcher="launch_standard pi"
    ;;
  5)
    pkg="opencode-ai"
    launcher="launch_standard opencode"
    ;;
  *)
    log "main" "Invalid choice: $choice"
    exit 1
    ;;
esac

if [[ -n "$pkg" ]]; then
  log "main" "Updating $pkg"
  npm update -g "$pkg"
  hash -r
fi

log "main" "Launching $launcher"
$launcher
