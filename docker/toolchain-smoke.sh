#!/usr/bin/env bash

# Link one executable per supported thin slice before the expensive library
# build. This catches wrapper, SDK, linker, and minimum-target regressions.

set -euo pipefail

readonly MODERN_ROOT="${ALTIVEC_MODERN_TOOLCHAIN:-/osxcross/modern}"
readonly LEGACY_ROOT="${ALTIVEC_LEGACY_TOOLCHAIN:-/osxcross/legacy/target}"
readonly SOURCE_FILE="${1:-/osxcross/legacy/docker/fixtures/toolchain-smoke.c}"
OUTPUT_DIR="$(mktemp -d /tmp/altivec-toolchain-smoke.XXXXXX)"
readonly OUTPUT_DIR

trap 'rm -rf "$OUTPUT_DIR"' EXIT

legacy_sdk="$LEGACY_ROOT/SDK/MacOSX10.5.sdk"
modern_sdk="$MODERN_ROOT/SDK/MacOSX11.3.sdk"
ios_sdk="$MODERN_ROOT/SDK/iPhoneOS8.4.sdk"
modern_bin="$MODERN_ROOT/bin"

assert_min_version() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$("$modern_bin/otool" -l "$file" | awk '
    $1 == "cmd" && ($2 == "LC_VERSION_MIN_MACOSX" ||
                     $2 == "LC_VERSION_MIN_IPHONEOS" ||
                     $2 == "LC_BUILD_VERSION") { found = 1; next }
    found && ($1 == "version" || $1 == "minos") { print $2; exit }
  ')"
  if [[ "$actual" != "$expected" ]]; then
    echo "error: $file has minimum version $actual; expected $expected" >&2
    exit 1
  fi
}

"$LEGACY_ROOT/bin/oppc32-gcc" -arch ppc -mmacosx-version-min=10.4 \
  -isysroot "$legacy_sdk" "$SOURCE_FILE" -lgcc_s.10.4 \
  -o "$OUTPUT_DIR/macos-ppc"
"$LEGACY_ROOT/bin/o32-gcc" -arch i386 -mmacosx-version-min=10.4 \
  -isysroot "$legacy_sdk" "$SOURCE_FILE" -lgcc_s.10.4 \
  -o "$OUTPUT_DIR/macos-i386"

modern_x64="$(find "$modern_bin" -maxdepth 1 -name 'x86_64-apple-darwin*-clang' | head -n 1)"
modern_arm64="$(find "$modern_bin" -maxdepth 1 -name 'arm64-apple-darwin*-clang' | head -n 1)"
test -n "$modern_x64"
test -n "$modern_arm64"

"$modern_x64" -target x86_64-apple-macos10.9 \
  -isysroot "$modern_sdk" "$SOURCE_FILE" -o "$OUTPUT_DIR/macos-x86_64"
"$modern_arm64" -target arm64-apple-macos11.0 \
  -isysroot "$modern_sdk" "$SOURCE_FILE" -o "$OUTPUT_DIR/macos-arm64"

/usr/bin/clang -target arm64-apple-ios -arch armv7 -arch arm64 \
  -Xarch_armv7 -miphoneos-version-min=4.3 \
  -Xarch_arm64 -miphoneos-version-min=7.0 \
  -Werror=overriding-option -isysroot "$ios_sdk" -B"$modern_bin" \
  "$SOURCE_FILE" -o "$OUTPUT_DIR/ios-universal"

"$LEGACY_ROOT/bin/i386-apple-darwin9-lipo" -create \
  "$OUTPUT_DIR/macos-ppc" "$OUTPUT_DIR/macos-i386" \
  "$OUTPUT_DIR/macos-x86_64" "$OUTPUT_DIR/macos-arm64" \
  -output "$OUTPUT_DIR/macos-universal"
"$LEGACY_ROOT/bin/i386-apple-darwin9-lipo" \
  "$OUTPUT_DIR/macos-universal" -verify_arch ppc i386 x86_64 arm64

"$modern_bin/lipo" "$OUTPUT_DIR/ios-universal" -verify_arch armv7 arm64

for slice_and_version in \
  macos-ppc:10.4 macos-i386:10.4 macos-x86_64:10.9 macos-arm64:11.0 \
  ios-armv7:4.3 ios-arm64:7.0; do
  slice="${slice_and_version%%:*}"
  expected="${slice_and_version##*:}"
  case "$slice" in
    macos-*)
      arch="${slice#macos-}"
      "$LEGACY_ROOT/bin/i386-apple-darwin9-lipo" \
        "$OUTPUT_DIR/macos-universal" -thin "$arch" \
        -output "$OUTPUT_DIR/verify-$slice"
      ;;
    ios-*)
      arch="${slice#ios-}"
      "$modern_bin/lipo" "$OUTPUT_DIR/ios-universal" -thin "$arch" \
        -output "$OUTPUT_DIR/verify-$slice"
      ;;
  esac
  assert_min_version "$OUTPUT_DIR/verify-$slice" "$expected"
done

echo "Toolchain smoke test passed: architectures and minimum versions verified"
