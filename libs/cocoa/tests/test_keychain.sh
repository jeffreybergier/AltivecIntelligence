#!/bin/bash
# Native Mac storage + host-executed iOS Security recorder. No login items.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
flags=(-fno-objc-arc -Wall -Wextra -Werror -Wno-deprecated-declarations
       -Wno-semicolon-before-method-body -framework Foundation -framework Security)
clang "${flags[@]}" "$root/AIKeychainStore.m" \
  "$root/tests/keychain_test.m" -o "$work/native"
"$work/native"
clang "${flags[@]}" "$root/tests/keychain_ios_test.m" -o "$work/ios-recorder"
"$work/ios-recorder"
