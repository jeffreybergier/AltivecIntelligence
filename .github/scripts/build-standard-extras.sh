#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

for tool in altivec-release altivec-sdk awk find grep make mktemp rm sha256sum unzip; do
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
inaccessible_resource="$(
  find "${prebuilt_root}/libs/cocoa/build-phone/Resources" \
    -type f ! -perm -004 -print -quit
)"
readonly inaccessible_resource
[[ -z "$inaccessible_resource" ]] ||
  die "prebuilt iOS resource is not world-readable: ${inaccessible_resource}"

arc_plan="$(mktemp "${TMPDIR:-/tmp}/altivec-arc-plan.XXXXXX")"
readonly arc_plan
audit_dir="$(mktemp -d "${TMPDIR:-/tmp}/altivec-release-audit.XXXXXX")"
readonly audit_dir
cleanup() {
  rm -f -- "$arc_plan"
  rm -rf -- "$audit_dir"
}
trap cleanup EXIT

make -C apps/CURLphone -Bn release \
  ALTIVEC_ROOT="$prebuilt_root" \
  PHONE_SOURCE_FLAGS=-fobjc-arc > "$arc_plan"
grep -Fq -- '-fobjc-arc' "$arc_plan" ||
  die 'CURLphone ARC compile plan lost its ARC flag'
if grep -Fqi arclite "$arc_plan"; then
  die 'CURLphone ARC build plan unexpectedly references ARCLite'
fi

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
  if unzip -Z1 "${dist_dir}/${asset}" | grep -Eiq \
      '(^|/)[^/]*[.]sdk(/|$)|[.]sdk[.]tar[.](gz|xz)$|arclite'; then
    die "release ZIP contains Apple SDK or ARCLite content: ${asset}"
  fi
  find "$audit_dir" -mindepth 1 -delete
  unzip -q "${dist_dir}/${asset}" -d "$audit_dir"
  altivec-sdk audit "$audit_dir"
done

actual_count="$(find "$dist_dir" -maxdepth 1 -type f | awk 'END { print NR }')"
[[ "$actual_count" == "${#expected_assets[@]}" ]] ||
  die "expected ${#expected_assets[@]} standard assets, found ${actual_count}"

sha256sum "${dist_dir}"/*
