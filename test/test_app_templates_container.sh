#!/bin/bash
# Existing image, network disabled, checkout /altivec and read-only SDK volumes.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
node --test "$root/test/altivec-app.test.cjs" "$root/test/altivec-release.test.cjs"
work=$(mktemp -d "$root/build/template-matrix.XXXXXX")
printf '%s\n' "$work" > "$root/build/template-matrix-latest.txt"
for template in ios-basic mac-basic cocoa-shared cocoa-daemon daemon cli-library; do
  project="$work/$template"
  node "$root/packages/altivec-app/bin/altivec-app.js" new --template "$template" \
    --name Example --bundle-id "org.altivec.test.$template" --destination "$project"
  (
    cd "$project"
    SANITIZE=1 make test-host
    make check-project
    make -j4 debug release
    make analyze
    make validate-package CONFIG=debug
    make validate-package CONFIG=release
    python3 tools/check-artifacts.py
    "$root/bin/altivec-release" stage --dry-run
  )
done
project="$work/rootless"
node "$root/packages/altivec-app/bin/altivec-app.js" new --template cocoa-daemon \
  --name Example --bundle-id org.altivec.test.rootless --platform iOS \
  --ios-package deb-rootless --destination "$project"
make -C "$project" release validate-package
printf 'PASS: generated SDK matrix at %s (no native-device claim)\n' "$work"
