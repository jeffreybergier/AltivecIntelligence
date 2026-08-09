#!/usr/bin/env bash

# Install Altivec's iPhone SDK beside the current OSXCross macOS SDK and add
# the unprefixed cctools entry points required by Clang's -B lookup.

set -euo pipefail

readonly SOURCE_DIR="${1:-/osxcross/modern-source}"
readonly TARGET_DIR="${2:-/osxcross/modern}"
readonly IOS_ARCHIVE="$SOURCE_DIR/tarballs/iPhoneOS8.4.sdk.tar.gz"
readonly IOS_SDK="$TARGET_DIR/SDK/iPhoneOS8.4.sdk"
readonly BIN_DIR="$TARGET_DIR/bin"

mkdir -p "$TARGET_DIR/SDK"
rm -rf "$IOS_SDK"
tar -xzf "$IOS_ARCHIVE" -C "$TARGET_DIR/SDK"
test -d "$IOS_SDK/System/Library/Frameworks"

find_tool() {
  local name="$1"
  local result
  result="$(find "$BIN_DIR" -maxdepth 1 \( -type f -o -type l \) \
    | sed -n "\\|/[^/]*-apple-darwin[^/]*-${name}$|p" \
    | sort | head -n 1)"
  test -n "$result"
  printf '%s\n' "$result"
}

for tool in ld ar ranlib lipo libtool nm otool strip install_name_tool; do
  tool_path="$(find_tool "$tool")"
  ln -sfn "$(basename "$tool_path")" "$BIN_DIR/$tool"
done

test -x "$BIN_DIR/ld"
test -x "$BIN_DIR/lipo"

echo "Modern macOS and iOS toolchain installed at $TARGET_DIR"
