#!/bin/bash
# Exercise installed packages against the final Make modules without Apple SDKs.
set -euo pipefail
root=${ALTIVEC_ROOT:-/altivec}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
altivec-release doctor --json
altivec-sdk status
for template in ios-basic mac-basic cocoa-shared cocoa-daemon daemon cli-library; do
  project="$work/$template"
  altivec-app new --template "$template" --name Example \
    --bundle-id "org.altivec.smoke.$template" --destination "$project"
  make -C "$project" ALTIVEC_ROOT="$root" test-host check-project print-config
  (cd "$project" && altivec-release check 1.0.0)
done
bash "$(dirname "$0")/website-smoke.sh"
printf '%s\n' 'PASS: installed packages, generated projects, Make modules and website tooling (no native-device claim)'
