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
[[ -f "$catalog_path" ]] ||
  die "SDK catalog not found: ${catalog_path}"
for tool in awk bash chmod env grep jq mktemp readlink realpath rm; do
  command -v "$tool" >/dev/null 2>&1 ||
    die "required validation tool not found: ${tool}"
done

manager_script="$(realpath -m "$manager_script")"
catalog_path="$(realpath -m "$catalog_path")"
readonly manager_script catalog_path

bash -n "$manager_script"

jq -e '
  .schema == 2 and
  .device_source.repository == "okanon/iPhoneOS.sdk" and
  .device_source.release_tag == "v0.0.1" and
  .device_source.release_url ==
    "https://github.com/okanon/iPhoneOS.sdk/releases/tag/v0.0.1" and
  (.device_sdks | type == "array" and length == 6) and
  (all(.device_sdks[];
    (.version | type == "string" and
      test("^[0-9]+[.][0-9]+$")) and
    (.directory | type == "string") and
    (.archive | type == "string") and
    (.url | type == "string") and
    (.sha256 | type == "string" and
      test("^[0-9a-f]{64}$")) and
    (.download_bytes | type == "number" and . > 0) and
    (.unpacked_bytes | type == "number" and . > 0) and
    (.architectures | type == "array" and length > 0 and
      all(.[]; . == "armv7" or . == "arm64")) and
    (.deployment_targets | type == "object") and
    (. as $sdk |
      all($sdk.architectures[];
        . as $arch |
        ($sdk.deployment_targets[$arch] |
          type == "string" and test("^[0-9]+[.][0-9]+$")))) and
    (. as $sdk |
      if ($sdk.architectures | index("armv7")) != null then
        $sdk.deployment_targets.armv7 == "5.0"
      else
        true
      end) and
    (.linker_input == "dylib" or .linker_input == "tapi")
  )) and
  ([.device_sdks[].version] | unique | length) == (.device_sdks | length) and
  ([.device_sdks[].directory] | unique | length) == (.device_sdks | length) and
  ([.device_sdks[].archive] | unique | length) == (.device_sdks | length) and
  ([.device_sdks[].url] | unique | length) == (.device_sdks | length) and
  ([.device_sdks[].sha256] | unique | length) == (.device_sdks | length) and
  ([.device_sdks[].version] == ["8.4", "9.3", "10.3", "11.4", "12.4", "13.2"]) and
  (.device_sdks[0].sha256 ==
    "677be5a92577c5e29cbab6067a9a624a3369af1cc00578941565886ea6a0a7da")
' "$catalog_path" >/dev/null ||
  die 'SDK catalog schema or pinned metadata is invalid'

readonly download_prefix='https://github.com/okanon/iPhoneOS.sdk/releases/download/v0.0.1'

while IFS=$'\t' read -r version directory archive url; do
  [[ "$directory" == "iPhoneOS${version}.sdk" ]] ||
    die "catalog directory does not match version ${version}: ${directory}"
  [[ "$archive" == "${directory}.tar.gz" ]] ||
    die "catalog archive does not match directory ${directory}: ${archive}"
  [[ "$url" == "${download_prefix}/${archive}" ]] ||
    die "catalog URL is outside the pinned release: ${url}"
done < <(
  jq -r '.device_sdks[] | [.version, .directory, .archive, .url] | @tsv' \
    "$catalog_path"
)

printf 'SDK manager inputs are valid: %s catalog entries.\n' \
  "$(jq -r '.device_sdks | length' "$catalog_path")"

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
readonly state_root="${check_root}/state"
readonly cache_root="${check_root}/cache"
readonly temporary_root="${check_root}/tmp"

mkdir -p "$fake_prefix/bin" "$sdk_root/iPhoneOS8.4.sdk" \
  "$sdk_root/iPhoneOS9.3.sdk" "$state_root/receipts" "$temporary_root"
ln -s iPhoneOS8.4.sdk "$sdk_root/Current.sdk"
printf '{}\n' > "$state_root/receipts/8.4.json"
printf '{}\n' > "$state_root/receipts/9.3.json"

write_fake_tool() {
  local name="$1"
  shift
  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' "$@"
  } > "$fake_prefix/bin/$name"
  chmod 0755 "$fake_prefix/bin/$name"
}

# The quoted lines are the literal body of the generated fake tool.
# shellcheck disable=SC2016
write_fake_tool clang \
  'case "${1:-}" in' \
  '  --print-targets) printf "  arm - ARM\\n" ;;' \
  '  --version) printf "fake clang\\n" ;;' \
  'esac'
write_fake_tool ld 'printf "fake ld; binary framework inputs only\\n" >&2'
for tool in curl file openssl otool tar; do
  write_fake_tool "$tool" 'exit 0'
done

run_manager() {
  env \
    ALTIVEC_SDK_TESTING=1 \
    ALTIVEC_SDK_INSTALL_PREFIX="$fake_prefix" \
    ALTIVEC_SDK_ROOT="$sdk_root" \
    ALTIVEC_SDK_CATALOG="$catalog_path" \
    ALTIVEC_SDK_STATE_ROOT="$state_root" \
    ALTIVEC_SDK_CACHE_ROOT="$cache_root" \
    ALTIVEC_SDK_TMP_ROOT="$temporary_root" \
    "$manager_script" "$@"
}

run_manager --help > "$check_root/help.txt"
grep -Fq 'altivec-sdk remove <version>' "$check_root/help.txt" ||
  die 'SDK manager help omits remove usage'

if run_manager remove 8.4 > "$check_root/remove-current.txt" 2>&1; then
  die 'remove accepted the selected SDK version'
fi
grep -Fq \
  'cannot remove selected iPhoneOS SDK 8.4; select another version first' \
  "$check_root/remove-current.txt" ||
  die 'remove did not explain how to remove the selected SDK version'
[[ -d "$sdk_root/iPhoneOS8.4.sdk" &&
  -f "$state_root/receipts/8.4.json" &&
  "$(readlink "$sdk_root/Current.sdk")" == 'iPhoneOS8.4.sdk' ]] ||
  die 'failed removal changed the selected SDK version'

run_manager remove 9.3 > "$check_root/remove.txt"
grep -Fq \
  "Removed iPhoneOS SDK 9.3 from ${sdk_root}/iPhoneOS9.3.sdk." \
  "$check_root/remove.txt" ||
  die 'remove did not report the removed SDK version'
[[ ! -e "$sdk_root/iPhoneOS9.3.sdk" &&
  ! -L "$sdk_root/iPhoneOS9.3.sdk" &&
  ! -e "$state_root/receipts/9.3.json" &&
  ! -L "$state_root/receipts/9.3.json" ]] ||
  die 'remove left the SDK version or its manager receipt behind'
[[ "$(readlink "$sdk_root/Current.sdk")" == 'iPhoneOS8.4.sdk' ]] ||
  die 'remove changed the selected SDK version'
run_manager list > "$check_root/list-after-remove.txt"
grep -Eq '^9[.]3[[:space:]]+available[[:space:]]+-' \
  "$check_root/list-after-remove.txt" ||
  die 'list does not report the removed SDK version as available'

mkdir "$sdk_root/iPhoneOS10.3.sdk"
if run_manager remove 10.3 > "$check_root/remove-unmanaged.txt" 2>&1; then
  die 'remove accepted an unmanaged SDK directory'
fi
grep -Fq 'SDK 10.3 is not managed by altivec-sdk' \
  "$check_root/remove-unmanaged.txt" ||
  die 'remove did not identify the unmanaged SDK directory'
[[ -d "$sdk_root/iPhoneOS10.3.sdk" ]] ||
  die 'failed removal deleted an unmanaged SDK directory'

printf '%s\n' 'SDK manager removal validation passed.'
