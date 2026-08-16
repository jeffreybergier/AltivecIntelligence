#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

if (($# != 2)); then
  printf 'Usage: %s <altivec-sdk-script> <catalog.json>\n' \
    "$(basename "$0")" >&2
  exit 2
fi

manager_script="$1"
catalog_path="$2"
[[ -f "$manager_script" ]] ||
  die "SDK manager script not found: ${manager_script}"
[[ -f "$catalog_path" ]] || die "SDK catalog not found: ${catalog_path}"
for tool in bash cp env grep jq mkdir mktemp readlink realpath rm sha256sum tar wc; do
  command -v "$tool" >/dev/null 2>&1 ||
    die "required validation tool not found: ${tool}"
done

manager_script="$(realpath -m "$manager_script")"
catalog_path="$(realpath -m "$catalog_path")"
readonly manager_script catalog_path
bash -n "$manager_script"

jq -e '
  .schema == 3 and
  (.build_sdks | type == "array" and length == 3) and
  ([.build_sdks[].id] ==
    ["macos-10.5", "macos-11.3", "iphoneos-8.4"]) and
  (all(.build_sdks[]; has("url") | not)) and
  (.build_sdks[] | select(.id == "iphoneos-8.4") |
    .version == "8.4" and
    .directory == "iPhoneOS8.4.sdk" and
    .archive == "iPhoneOS8.4.sdk.tar.gz" and
    .format == "tar.gz" and
    .archive_bytes == 33969945 and
    .sha256 ==
      "677be5a92577c5e29cbab6067a9a624a3369af1cc00578941565886ea6a0a7da")
' "$catalog_path" >/dev/null || die 'SDK catalog schema is invalid'
printf 'SDK manager inputs are valid: iPhoneOS 8.4 only.\n'

check_root="$(mktemp -d "${TMPDIR:-/tmp}/altivec-sdk-check.XXXXXX")"
readonly check_root

cleanup() {
  local rc=$?

  trap - EXIT
  case "$check_root" in
    "${TMPDIR:-/tmp}"/altivec-sdk-check.*)
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
readonly sdk_root="${check_root}/sdks"
readonly archive_dir="${check_root}/root-home"
readonly state_root="${check_root}/state"
readonly payload_root="${check_root}/payload"
readonly fixture_catalog="${check_root}/catalog.json"
readonly archive_path="${archive_dir}/iPhoneOS8.4.sdk.tar.gz"
readonly saved_archive="${check_root}/saved-iPhoneOS8.4.sdk.tar.gz"

mkdir -p \
  "$fake_prefix/bin" \
  "$sdk_root" \
  "$archive_dir" \
  "$state_root" \
  "$payload_root/iPhoneOS8.4.sdk/System/Library/Frameworks/Foundation.framework/Headers" \
  "$payload_root/iPhoneOS8.4.sdk/System/Library/Frameworks/UIKit.framework/Headers" \
  "$payload_root/iPhoneOS8.4.sdk/usr/lib"
printf '%s\n' 'fixture settings' \
  > "$payload_root/iPhoneOS8.4.sdk/SDKSettings.plist"
printf '%s\n' '/* fixture Foundation */' \
  > "$payload_root/iPhoneOS8.4.sdk/System/Library/Frameworks/Foundation.framework/Headers/Foundation.h"
printf '%s\n' '/* fixture UIKit */' \
  > "$payload_root/iPhoneOS8.4.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIKit.h"
printf '%s\n' 'fixture dylib' \
  > "$payload_root/iPhoneOS8.4.sdk/usr/lib/libSystem.dylib"
tar -czf "$archive_path" -C "$payload_root" iPhoneOS8.4.sdk

archive_sha="$(sha256sum "$archive_path" | awk '{print $1}')"
archive_bytes="$(wc -c < "$archive_path" | tr -d '[:space:]')"
readonly archive_sha archive_bytes
jq \
  --arg sha "$archive_sha" \
  --argjson bytes "$archive_bytes" \
  '(.build_sdks[] | select(.id == "iphoneos-8.4") | .sha256) = $sha |
   (.build_sdks[] | select(.id == "iphoneos-8.4") | .archive_bytes) = $bytes' \
  "$catalog_path" > "$fixture_catalog"

run_manager() {
  env \
    ALTIVEC_SDK_TESTING=1 \
    ALTIVEC_SDK_INSTALL_PREFIX="$fake_prefix" \
    ALTIVEC_SDK_ROOT="$sdk_root" \
    ALTIVEC_SDK_CATALOG="$fixture_catalog" \
    ALTIVEC_SDK_ARCHIVE_DIR="$archive_dir" \
    ALTIVEC_SDK_STATE_ROOT="$state_root" \
    "$manager_script" "$@"
}

run_manager help > "$check_root/help.txt"
for expected in \
    'altivec-sdk status' \
    'altivec-sdk preflight' \
    'altivec-sdk install' \
    'altivec-sdk uninstall' \
    'iPhoneOS8.4.sdk.tar.gz'; do
  grep -Fq "$expected" "$check_root/help.txt" ||
    die "SDK manager help omits: ${expected}"
done

run_manager status > "$check_root/status-before.txt"
grep -Eq '^iPhoneOS8[.]4[[:space:]]+iPhoneOS8[.]4[.]sdk[.]tar[.]gz[[:space:]]+available[[:space:]]+missing' \
  "$check_root/status-before.txt" || die 'initial status is incorrect'
run_manager preflight > "$check_root/preflight.txt"
grep -Fq 'SDK archive preflight passed' "$check_root/preflight.txt" ||
  die 'preflight did not report success'

run_manager install > "$check_root/install.txt"
[[ -f "$sdk_root/iPhoneOS8.4.sdk/SDKSettings.plist" ]] ||
  die 'install omitted SDKSettings.plist'
[[ "$(readlink "$sdk_root/Current.sdk")" == 'iPhoneOS8.4.sdk' ]] ||
  die 'install did not select iPhoneOS 8.4'
[[ -f "$state_root/receipts/8.4.json" ]] ||
  die 'install omitted its receipt'
[[ -f "$archive_path" ]] || die 'install removed the source archive'

run_manager status > "$check_root/status-installed.txt"
grep -Eq '^iPhoneOS8[.]4.*available[[:space:]]+installed' \
  "$check_root/status-installed.txt" || die 'installed status is incorrect'
run_manager install > "$check_root/install-again.txt"
grep -Fq 'SDK already installed' "$check_root/install-again.txt" ||
  die 'repeated install was not idempotent'

cp "$archive_path" "$saved_archive"
rm "$archive_path"
run_manager uninstall > "$check_root/uninstall.txt"
[[ ! -e "$sdk_root/iPhoneOS8.4.sdk" && ! -L "$sdk_root/Current.sdk" ]] ||
  die 'uninstall left installed SDK state behind'
[[ ! -e "$state_root/receipts/8.4.json" ]] ||
  die 'uninstall left its receipt behind'
[[ -f "$saved_archive" ]] || die 'uninstall modified the saved source archive'
grep -Fq 'Source archive left untouched' "$check_root/uninstall.txt" ||
  die 'uninstall did not explain source-archive behavior'

cp "$saved_archive" "$archive_path"
printf '%s\n' 'corrupt' >> "$archive_path"
if run_manager preflight > "$check_root/bad-preflight.txt" 2>&1; then
  die 'preflight accepted a corrupt archive'
fi
grep -Eq 'SDK (size|checksum) mismatch' "$check_root/bad-preflight.txt" ||
  die 'preflight did not explain the corrupt archive'

printf 'SDK manager command validation passed.\n'
