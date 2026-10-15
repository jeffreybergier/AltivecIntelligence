#!/bin/bash
# Optional sibling-facade Tiger test build; no source or credential modification.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
siblings=${KEYCHAIN_SIBLINGS:?Set KEYCHAIN_SIBLINGS to the sibling checkout parent}
output=${KEYCHAIN_TEST_OUTPUT_DIR:?Set KEYCHAIN_TEST_OUTPUT_DIR to a build folder}
mkdir -p "$output"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/include"
ln -s "$root" "$work/include/AltivecCocoa"
flags=(-arch ppc -mmacosx-version-min=10.4
       -isysroot /osxcross/legacy/target/SDK/MacOSX10.5.sdk
       -Wall -Wextra -Werror -Wno-deprecated-declarations -fno-stack-protector
       -framework Foundation -framework Security -framework CoreServices
       -I"$work/include")
cc=/osxcross/legacy/target/bin/oppc32-gcc
testsource="$root/tests/keychain_consumers_test.m"
"$cc" "${flags[@]}" "$root/AIKeychainStore.m" "$testsource" \
  -I"$siblings/Strappy-Cocoa/source/daemon" \
  "$siblings/Strappy-Cocoa/source/daemon/XPKeychain.m" -o "$output/strappy-ppc"
"$cc" "${flags[@]}" -DAI_TEST_ENIL "$root/AIKeychainStore.m" "$testsource" \
  -I"$siblings/ENIL/source/shared" \
  "$siblings/ENIL/source/shared/XPFoundation.m" -o "$output/enil-ppc"
"$cc" "${flags[@]}" -DAI_TEST_RCLOUD "$root/AIKeychainStore.m" "$testsource" \
  -I"$siblings/Retro-Cloud-Sync/source/shared" \
  "$siblings/Retro-Cloud-Sync/source/shared/RCICloudCredentials.m" \
  "$siblings/Retro-Cloud-Sync/source/shared/RCError.c" -o "$output/rcloud-ppc"
echo 'PASS: three consumer facade Tiger test executables'
