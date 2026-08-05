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

readonly manager_script="$1"
readonly catalog_path="$2"

[[ -f "$manager_script" ]] ||
  die "SDK manager script not found: ${manager_script}"
[[ -f "$catalog_path" ]] ||
  die "SDK catalog not found: ${catalog_path}"
command -v bash >/dev/null 2>&1 || die 'bash is required'
command -v jq >/dev/null 2>&1 || die 'jq is required'

bash -n "$manager_script"

jq -e '
  .schema == 1 and
  .source.repository == "okanon/iPhoneOS.sdk" and
  .source.release_tag == "v0.0.1" and
  .source.release_url ==
    "https://github.com/okanon/iPhoneOS.sdk/releases/tag/v0.0.1" and
  (.sdks | type == "array" and length == 6) and
  (all(.sdks[];
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
        $sdk.deployment_targets.armv7 == "4.3"
      else
        true
      end) and
    (.linker_input == "dylib" or .linker_input == "tapi")
  )) and
  ([.sdks[].version] | unique | length) == (.sdks | length) and
  ([.sdks[].directory] | unique | length) == (.sdks | length) and
  ([.sdks[].archive] | unique | length) == (.sdks | length) and
  ([.sdks[].url] | unique | length) == (.sdks | length) and
  ([.sdks[].sha256] | unique | length) == (.sdks | length) and
  ([.sdks[].version] == ["8.4", "9.3", "10.3", "11.4", "12.4", "13.2"]) and
  (.sdks[0].sha256 ==
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
  jq -r '.sdks[] | [.version, .directory, .archive, .url] | @tsv' \
    "$catalog_path"
)

printf 'SDK manager inputs are valid: %s catalog entries.\n' \
  "$(jq -r '.sdks | length' "$catalog_path")"
