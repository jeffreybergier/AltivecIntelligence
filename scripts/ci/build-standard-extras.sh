#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

for tool in altivec-release awk find make mktemp rm sha256sum unzip; do
  command -v "$tool" >/dev/null 2>&1 ||
    die "required release tool not found: ${tool}"
done

: "${ALTIVEC_RELEASE_PREBUILT_ROOT:?ALTIVEC_RELEASE_PREBUILT_ROOT is required}"
: "${RELEASE_VERSION:?RELEASE_VERSION is required}"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly script_dir
repository_root="$(cd -- "${script_dir}/../.." && pwd -P)"
readonly repository_root
prebuilt_root="$(cd -- "$ALTIVEC_RELEASE_PREBUILT_ROOT" && pwd -P)"
readonly prebuilt_root
readonly dist_dir="${repository_root}/dist"

[[ "$RELEASE_VERSION" =~ ^[0-9]+([.][0-9]+){0,2}$ ]] ||
  die "invalid release version: ${RELEASE_VERSION}"

for path in \
  libs/core/build-mac/lib/AltivecCore.framework \
  libs/core/build-phone/lib/libAltivecCore.a \
  libs/cocoa/build-mac/lib/AltivecCocoa.framework \
  libs/cocoa/build-phone/lib/libAltivecCocoa.a; do
  [[ -e "${prebuilt_root}/${path}" ]] ||
    die "prebuilt image output is missing: ${prebuilt_root}/${path}"
done

unexpected_build="$(
  find "${prebuilt_root}/apps" -type d \
    \( -name 'build-*' -o -name Intermediates \) -print -quit
)"
[[ -z "$unexpected_build" ]] ||
  die "primary image contains a prebuilt sample directory: ${unexpected_build}"

readonly targets=(
  AltivecCore
  AltivecCocoa
  SingleWindow
  SingleScreen
  CURLmac
  CURLphone
)
target_args=()
for target in "${targets[@]}"; do
  target_args+=(--target "$target")
done

cd "$repository_root"
altivec-release build "${target_args[@]}"

[[ -d apps/CURLmac/build-release/CURLmac.app/Contents/Frameworks/AltivecCore.framework ]] ||
  die 'CURLmac did not embed AltivecCore.framework'
[[ -d apps/CURLmac/build-release/CURLmac.app/Contents/Frameworks/AltivecCocoa.framework ]] ||
  die 'CURLmac did not embed AltivecCocoa.framework'
[[ -f apps/CURLmac/build-release/CURLmac.app/Contents/Frameworks/AltivecCocoa.framework/Resources/Fonts/FA7-Solid-900.otf ]] ||
  die 'CURLmac did not stage the AltivecCocoa font'
[[ -f apps/CURLmac/build-release/CURLmac.app/Contents/Frameworks/AltivecCocoa.framework/Resources/Fonts/LICENSE-Font-Awesome.txt ]] ||
  die 'CURLmac did not stage the Font Awesome license'
[[ -f apps/CURLphone/build-release/CURLphone.app/Fonts/FA7-Solid-900.otf ]] ||
  die 'CURLphone did not stage the AltivecCocoa font'
[[ -f apps/CURLphone/build-release/CURLphone.app/Fonts/LICENSE-Font-Awesome.txt ]] ||
  die 'CURLphone did not stage the Font Awesome license'
[[ ! -d apps/CURLphone/build-release/CURLphone.app/Frameworks ]] ||
  die 'CURLphone unexpectedly embedded an iOS framework'

arc_plan="$(mktemp "${TMPDIR:-/tmp}/altivec-arc-plan.XXXXXX")"
readonly arc_plan
cleanup() {
  rm -f -- "$arc_plan"
}
trap cleanup EXIT

make -C apps/CURLphone -Bn release \
  ALTIVEC_ROOT="$prebuilt_root" \
  PHONE_SOURCE_FLAGS=-fobjc-arc > "$arc_plan"
awk '/Linking Phone universal/ { in_link = 1 }
     in_link && /-Xarch_armv7 -fobjc-arc/ { found = 1 }
     END { exit(found ? 0 : 1) }' "$arc_plan" ||
  die 'CURLphone ARC link plan lost its armv7 ARC flag'

case "$dist_dir" in
  "${repository_root}/dist") rm -rf -- "$dist_dir" ;;
  *) die "refusing to replace unsafe dist path: ${dist_dir}" ;;
esac
altivec-release stage "$RELEASE_VERSION" "${target_args[@]}"

readonly expected_assets=(
  "AltivecCore-${RELEASE_VERSION}-macOS.framework.zip"
  "AltivecCore-${RELEASE_VERSION}-iOS-static.zip"
  "AltivecCocoa-${RELEASE_VERSION}-macOS.framework.zip"
  "AltivecCocoa-${RELEASE_VERSION}-iOS-static.zip"
  "SingleWindow-${RELEASE_VERSION}.zip"
  "SingleScreen-${RELEASE_VERSION}.ipa"
  "CURLmac-${RELEASE_VERSION}.zip"
  "CURLphone-${RELEASE_VERSION}.ipa"
)

for asset in "${expected_assets[@]}"; do
  [[ -s "${dist_dir}/${asset}" ]] || die "release asset is missing: ${asset}"
  unzip -tq "${dist_dir}/${asset}" >/dev/null ||
    die "release ZIP is corrupt: ${asset}"
done

actual_count="$(find "$dist_dir" -maxdepth 1 -type f | awk 'END { print NR }')"
[[ "$actual_count" == "${#expected_assets[@]}" ]] ||
  die "expected ${#expected_assets[@]} standard assets, found ${actual_count}"

sha256sum "${dist_dir}"/*
