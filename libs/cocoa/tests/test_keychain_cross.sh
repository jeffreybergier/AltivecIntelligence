#!/bin/bash
# Run inside the image with SDK volumes installed; no native execution claimed.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
legacy=/osxcross/legacy/target
modern=/osxcross/modern
for arch in ppc i386; do
  compiler=oppc32-gcc
  [[ "$arch" != i386 ]] || compiler=o32-gcc
  "$legacy/bin/$compiler" -arch "$arch" -mmacosx-version-min=10.4 \
    -isysroot "$legacy/SDK/MacOSX10.5.sdk" -Wall -Wextra -Werror \
    -Wno-deprecated-declarations -fno-stack-protector \
    -framework Foundation -framework Security \
    "$root/AIKeychainStore.m" "$root/tests/keychain_test.m" \
    -o "$work/$arch"
  echo "PASS: Tiger $arch compile/link (including native test)"
done
if [[ -n "${KEYCHAIN_TEST_OUTPUT_DIR:-}" ]]; then
  mkdir -p "$KEYCHAIN_TEST_OUTPUT_DIR"
  cp "$work/ppc" "$KEYCHAIN_TEST_OUTPUT_DIR/keychain-ppc"
fi
for spec in x86_64:10.9 arm64:11.0; do
  arch=${spec%:*}; floor=${spec#*:}
  clang -target "$arch-apple-macos$floor" \
    -isysroot "$modern/SDK/MacOSX11.3.sdk" -B"$modern/bin" \
    -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -Wno-semicolon-before-method-body -framework Foundation -framework Security \
    "$root/AIKeychainStore.m" "$root/tests/keychain_test.m" \
    -o "$work/$arch"
  echo "PASS: Mac $arch compile/link (including native test)"
done
for spec in armv7:5.0 arm64:7.0; do
  arch=${spec%:*}; floor=${spec#*:}
  clang -target "$arch-apple-ios$floor" \
    -isysroot "$modern/SDK/iPhoneOS8.4.sdk" -B"$modern/bin" \
    -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -Wno-semicolon-before-method-body -framework Foundation -framework Security \
    "$root/AIKeychainStore.m" "$root/tests/keychain_device_test.m" \
    -o "$work/ios-$arch"
  ldid -S"$root/tests/KeychainTestEntitlements.plist" "$work/ios-$arch"
  if [[ -n "${KEYCHAIN_TEST_OUTPUT_DIR:-}" ]]; then
    cp "$work/ios-$arch" "$KEYCHAIN_TEST_OUTPUT_DIR/keychain-$arch"
  fi
  echo "PASS: iOS $arch compile/link/sign (native test executable)"
done
