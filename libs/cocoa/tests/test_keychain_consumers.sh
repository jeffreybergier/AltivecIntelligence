#!/bin/bash
# Optional integration checks when the three sibling checkouts are available.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
siblings=$(cd "$root/../../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/include"
ln -s "$root" "$work/include/AltivecCocoa"
flags=(-fno-objc-arc -Wall -Wextra -Wno-deprecated-declarations
       -Wno-semicolon-before-method-body -framework Foundation -framework Security
       -framework CoreServices -I"$work/include")
testsource="$root/tests/keychain_consumers_test.m"
run_test() {
  codesign -s - "$1"
  python3 - "$1" "$work" <<'RUN'
import subprocess, sys
subprocess.run(sys.argv[1:], check=True, timeout=45)
RUN
}
clang "${flags[@]}" "$root/AIKeychainStore.m" "$testsource" \
  -I"$siblings/Strappy-Cocoa/source/daemon" \
  "$siblings/Strappy-Cocoa/source/daemon/XPKeychain.m" -o "$work/strappy"
run_test "$work/strappy"
clang "${flags[@]}" -DAI_TEST_ENIL "$root/AIKeychainStore.m" "$testsource" \
  -I"$siblings/ENIL/source/shared" \
  "$siblings/ENIL/source/shared/XPFoundation.m" -o "$work/enil"
run_test "$work/enil"
clang "${flags[@]}" -DAI_TEST_RCLOUD "$root/AIKeychainStore.m" "$testsource" \
  -I"$siblings/Retro-Cloud-Sync/source/shared" \
  "$siblings/Retro-Cloud-Sync/source/shared/RCICloudCredentials.m" \
  "$siblings/Retro-Cloud-Sync/source/shared/RCError.c" -o "$work/rcloud"
run_test "$work/rcloud"
