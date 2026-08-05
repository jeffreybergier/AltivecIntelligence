#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

if (($# != 1)); then
  printf 'Usage: %s <altivec-lib-script>\n' "$(basename "$0")" >&2
  exit 2
fi

for tool in bash chmod cp curl env grep jq mktemp openssl readlink \
  realpath rm unzip zip; do
  command -v "$tool" >/dev/null 2>&1 ||
    die "required validation tool not found: ${tool}"
done

manager_script="$(realpath -m "$1")"
readonly manager_script
[[ -f "$manager_script" ]] ||
  die "library manager script not found: ${manager_script}"

bash -n "$manager_script"

check_root="$(mktemp -d "${TMPDIR:-/tmp}/altivec-lib-check.XXXXXX")"
readonly check_root

cleanup() {
  local rc=$?

  trap - EXIT
  case "$check_root" in
    "${TMPDIR:-/tmp}"/altivec-lib-check.*)
      if [[ -d "$check_root" && ! -L "$check_root" ]]; then
        rm -r "$check_root"
      fi
      ;;
    *)
      printf 'error: refusing to remove unsafe validation path: %s\n' \
        "$check_root" >&2
      rc=1
      ;;
  esac
  exit "$rc"
}
trap cleanup EXIT

readonly fake_prefix="${check_root}/prefix"
readonly library_root="${check_root}/libraries"
readonly state_root="${check_root}/state"
readonly cache_root="${check_root}/cache"
readonly temporary_root="${check_root}/tmp"
readonly sdk_root="${check_root}/sdks"
readonly api_root="${check_root}/api/releases"
readonly release_root="${check_root}/release-downloads"
readonly fixture_root="${check_root}/fixtures"

mkdir -p \
  "$fake_prefix/bin" \
  "$temporary_root" \
  "$sdk_root/Current.sdk/System/Library/Frameworks/UIKit.framework/Headers" \
  "$api_root/tags" \
  "$release_root/v1.0.9" \
  "$release_root/v1.0.10" \
  "$release_root/v1.0.11" \
  "$fixture_root/AltivecCore-iOS-static/include/AltivecCore" \
  "$fixture_root/AltivecCore-iOS-static/lib" \
  "$fixture_root/AltivecCocoa-iOS-static/include/AltivecCocoa" \
  "$fixture_root/AltivecCocoa-iOS-static/lib" \
  "$fixture_root/AltivecCocoa-iOS-static/Resources/Fonts"

printf '%s\n' '/* fake UIKit */' \
  > "$sdk_root/Current.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIKit.h"

# These deliberately do not mirror the current library's internal headers.
for header in AltivecCore.h AITestCoreFeature.h; do
  printf '/* fake %s */\n' "$header" \
    > "$fixture_root/AltivecCore-iOS-static/include/AltivecCore/$header"
done
for header in AltivecCocoa.h AITestCocoaFeature.h; do
  printf '/* fake %s */\n' "$header" \
    > "$fixture_root/AltivecCocoa-iOS-static/include/AltivecCocoa/$header"
done
printf '%s\n' 'fake core archive' \
  > "$fixture_root/AltivecCore-iOS-static/lib/libAltivecCore.a"
printf '%s\n' 'fake CA certificates' \
  > "$fixture_root/AltivecCore-iOS-static/lib/cacert.pem"
printf '%s\n' 'fake cocoa archive' \
  > "$fixture_root/AltivecCocoa-iOS-static/lib/libAltivecCocoa.a"
printf '%s\n' 'fake package resource' \
  > "$fixture_root/AltivecCocoa-iOS-static/Resources/Fonts/TestFont.otf"
printf '%s\n' 'build-only stamp' \
  > "$fixture_root/AltivecCocoa-iOS-static/Resources/Fonts/.stamp"

(
  cd "$fixture_root"
  zip -qry "$check_root/core.zip" AltivecCore-iOS-static
  zip -qry "$check_root/cocoa.zip" AltivecCocoa-iOS-static
)

for version in 1.0.9 1.0.10 1.0.11; do
  cp "$check_root/core.zip" \
    "$release_root/v${version}/AltivecCore-${version}-iOS-static.zip"
done
for version in 1.0.9 1.0.10; do
  cp "$check_root/cocoa.zip" \
    "$release_root/v${version}/AltivecCocoa-${version}-iOS-static.zip"
done

write_fake_tool() {
  local name="$1"
  shift
  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' "$@"
  } > "$fake_prefix/bin/$name"
  chmod 0755 "$fake_prefix/bin/$name"
}

# The quoted lines are the literal body of the generated fake tools.
# shellcheck disable=SC2016
write_fake_tool clang \
  'output=' \
  'source=' \
  'saw_objc_link=0' \
  'saw_core_archive=0' \
  'saw_cocoa_archive=0' \
  'while [ "$#" -gt 0 ]; do' \
  '  case "$1" in' \
  '    -o) shift; output="$1" ;;' \
  '    *.m) source="$1" ;;' \
  '    -Wl,-ObjC) saw_objc_link=1 ;;' \
  '    */libAltivecCore.a) saw_core_archive=1 ;;' \
  '    */libAltivecCocoa.a) saw_cocoa_archive=1 ;;' \
  '  esac' \
  '  shift' \
  'done' \
  '[ -n "$output" ] && [ -f "$source" ] || exit 1' \
  '[ "$saw_objc_link" -eq 1 ] || exit 1' \
  '[ "$saw_core_archive" -eq 1 ] || exit 1' \
  '[ "$saw_cocoa_archive" -eq 1 ] || exit 1' \
  'grep -Fq "#import <AltivecCore/AltivecCore.h>" "$source" || exit 1' \
  'grep -Fq "#import <AltivecCocoa/AltivecCocoa.h>" "$source" || exit 1' \
  'if grep -Eq "AICURLConnection|AIFontAwesome|\\[AltivecCore class\\]" "$source"; then exit 1; fi' \
  'printf "fake Mach-O armv7 executable\n" > "$output"'
write_fake_tool lipo \
  'printf "Architectures in the fat file are: armv7 arm64\n"'
# shellcheck disable=SC2016
write_fake_tool file \
  'printf "%s: Mach-O armv7 executable\n" "$1"'
write_fake_tool otool 'exit 0'
# The manager must not depend on wc; it is absent on a supported device.
write_fake_tool wc 'exit 99'

sha256_file() {
  local digest=""
  digest="$(openssl dgst -sha256 "$1")"
  printf '%s\n' "${digest##*= }"
}

file_size() {
  wc -c < "$1" | awk '{ print $1 }'
}

write_release() {
  local version="$1"
  local destination="$2"
  local include_cocoa="$3"
  local core_name="AltivecCore-${version}-iOS-static.zip"
  local cocoa_name="AltivecCocoa-${version}-iOS-static.zip"
  local core_path="${release_root}/v${version}/${core_name}"
  local cocoa_path="${release_root}/v${version}/${cocoa_name}"
  local assets_json=""

  assets_json="$(jq -n \
    --arg name "$core_name" \
    --arg url "file://${core_path}" \
    --arg digest "sha256:$(sha256_file "$core_path")" \
    --argjson size "$(file_size "$core_path")" \
    '[{
      name: $name,
      state: "uploaded",
      browser_download_url: $url,
      digest: $digest,
      size: $size
    }]')"

  if [[ "$include_cocoa" == "1" ]]; then
    assets_json="$(jq -n \
      --argjson assets "$assets_json" \
      --arg name "$cocoa_name" \
      --arg url "file://${cocoa_path}" \
      --arg digest "sha256:$(sha256_file "$cocoa_path")" \
      --argjson size "$(file_size "$cocoa_path")" \
      '$assets + [{
        name: $name,
        state: "uploaded",
        browser_download_url: $url,
        digest: $digest,
        size: $size
      }]')"
  fi

  jq -n \
    --arg tag "v${version}" \
    --argjson assets "$assets_json" \
    '{tag_name: $tag, draft: false, prerelease: false, assets: $assets}' \
    > "$destination"
}

write_release 1.0.9 "$api_root/tags/v1.0.9" 1
write_release 1.0.10 "$api_root/tags/v1.0.10" 1
write_release 1.0.10 "$api_root/latest" 1
write_release 1.0.11 "$api_root/tags/v1.0.11" 0

run_manager() {
  env \
    ALTIVEC_LIB_TESTING=1 \
    ALTIVEC_LIB_INSTALL_PREFIX="$fake_prefix" \
    ALTIVEC_LIB_ROOT="$library_root" \
    ALTIVEC_LIB_STATE_ROOT="$state_root" \
    ALTIVEC_LIB_CACHE_ROOT="$cache_root" \
    ALTIVEC_LIB_TMP_ROOT="$temporary_root" \
    ALTIVEC_LIB_SDK_ROOT="$sdk_root" \
    ALTIVEC_LIB_GITHUB_API_BASE="file://${api_root}" \
    ALTIVEC_LIB_GITHUB_DOWNLOAD_PREFIX="file://${release_root}" \
    "$manager_script" "$@"
}

run_manager --help > "$check_root/help.txt"
grep -Fq 'altivec-lib install <version>' "$check_root/help.txt" ||
  die 'library manager help omits install usage'
grep -Fq 'altivec-lib update' "$check_root/help.txt" ||
  die 'library manager help omits update usage'

mkdir -p "$cache_root/downloads"
cp "$release_root/v1.0.9/AltivecCore-1.0.9-iOS-static.zip" \
  "$cache_root/downloads/AltivecCore-1.0.9-iOS-static.zip.part"
cp "$release_root/v1.0.9/AltivecCocoa-1.0.9-iOS-static.zip" \
  "$cache_root/downloads/AltivecCocoa-1.0.9-iOS-static.zip.part"
run_manager install 1.0.9 > "$check_root/install.txt" 2>&1
grep -Fq 'Using cached AltivecCore 1.0.9' "$check_root/install.txt" ||
  die 'install did not reuse a complete verified download'
[[ -d "$library_root/1.0.9" &&
  "$library_root/Current" -ef "$library_root/1.0.9" ]] ||
  die 'install did not create and select version 1.0.9'
[[ "$(readlink "$library_root/Current")" == '1.0.9' ]] ||
  die 'Current does not use a relative version link'
[[ -f "$library_root/1.0.9/Bundle/cacert.pem" &&
  -f "$library_root/1.0.9/Bundle/Fonts/TestFont.otf" ]] ||
  die 'install did not normalize managed app resources'
[[ ! -e "$library_root/1.0.9/Bundle/Fonts/.stamp" ]] ||
  die 'install copied a private build stamp into managed resources'
jq -e '.version == "1.0.9" and .repository ==
  "jeffreybergier/AltivecIntelligence"' \
  "$library_root/1.0.9/.altivec-lib-receipt.json" >/dev/null ||
  die 'install receipt is invalid'
grep -Fq 'ALTIVEC_MANAGED_VERSION := 1.0.9' \
  "$fake_prefix/share/altivec-lib/current.mk" ||
  die 'install did not generate the selected Make fragment'

rm "$library_root/Current" \
  "$fake_prefix/share/altivec-lib/current.mk" \
  "$state_root/receipts/1.0.9.json"
run_manager install 1.0.9 > "$check_root/reinstall.txt"
[[ "$(readlink "$library_root/Current")" == '1.0.9' &&
  -f "$fake_prefix/share/altivec-lib/current.mk" &&
  -f "$state_root/receipts/1.0.9.json" ]] ||
  die 'reinstall did not repair selection metadata and the external receipt'

run_manager list > "$check_root/list.txt"
grep -Eq '^1[.]0[.]9[[:space:]]+installed[[:space:]]+yes' \
  "$check_root/list.txt" ||
  die 'list does not report the selected installed version'

run_manager verify 1.0.9 > "$check_root/verify.txt"
grep -Fq 'verification passed' "$check_root/verify.txt" ||
  die 'verify did not report success'

cp "$api_root/tags/v1.0.11" "$api_root/latest"
if run_manager update > "$check_root/broken-update.txt" 2>&1; then
  die 'update accepted a release with no AltivecCocoa asset'
fi
grep -Fq 'has no valid AltivecCocoa-1.0.11-iOS-static.zip asset' \
  "$check_root/broken-update.txt" ||
  die 'broken update did not identify the missing expected asset'
[[ "$(readlink "$library_root/Current")" == '1.0.9' ]] ||
  die 'broken update changed the selected version'

write_release 1.0.10 "$api_root/latest" 1
run_manager update > "$check_root/update.txt" 2>&1
[[ -d "$library_root/1.0.10" &&
  "$(readlink "$library_root/Current")" == '1.0.10' ]] ||
  die 'update did not install and select version 1.0.10'
grep -Fq 'ALTIVEC_MANAGED_VERSION := 1.0.10' \
  "$fake_prefix/share/altivec-lib/current.mk" ||
  die 'update did not refresh the selected Make fragment'

run_manager select 1.0.9 > "$check_root/select.txt"
[[ "$(readlink "$library_root/Current")" == '1.0.9' ]] ||
  die 'select did not roll back to version 1.0.9'
grep -Fq 'ALTIVEC_MANAGED_VERSION := 1.0.9' \
  "$fake_prefix/share/altivec-lib/current.mk" ||
  die 'rollback did not refresh the selected Make fragment'

printf '%s\n' 'Altivec library manager validation passed.'
