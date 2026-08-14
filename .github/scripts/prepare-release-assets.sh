#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

if (($# != 2)); then
  printf 'Usage: %s <dist-directory> <release-version>\n' \
    "$(basename "$0")" >&2
  exit 2
fi

for tool in find realpath rm sha256sum sort unzip; do
  command -v "$tool" >/dev/null 2>&1 ||
    die "required asset validation tool not found: ${tool}"
done

dist_dir="$(realpath -m "$1")"
readonly dist_dir
readonly release_version="$2"

[[ "$release_version" =~ ^[0-9]+([.][0-9]+){0,2}$ ]] ||
  die "invalid release version: ${release_version}"
[[ -d "$dist_dir" && ! -L "$dist_dir" ]] ||
  die "dist directory is missing or unsafe: ${dist_dir}"
[[ "${dist_dir##*/}" == dist && "$dist_dir" != /dist ]] ||
  die "release assets must be assembled in a dedicated dist directory: ${dist_dir}"

readonly expected_assets=(
  "AltivecCore-${release_version}-macOS.framework.zip"
  "AltivecCore-${release_version}-iOS-static.zip"
  "AltivecCocoa-${release_version}-macOS.framework.zip"
  "AltivecCocoa-${release_version}-iOS-static.zip"
  "SingleWindow-${release_version}.zip"
  "SingleScreen-${release_version}.ipa"
  "CURLmac-${release_version}.zip"
  "CURLphone-${release_version}.ipa"
  "AltivecToolchain-${release_version}-iOS-armv7.deb"
)

rm -f -- "${dist_dir}/SHA256SUMS"

declare -A expected_names=()
for asset in "${expected_assets[@]}"; do
  expected_names["$asset"]=1
  [[ -f "${dist_dir}/${asset}" && ! -L "${dist_dir}/${asset}" ]] ||
    die "expected release asset is missing or unsafe: ${asset}"
  [[ -s "${dist_dir}/${asset}" ]] || die "release asset is empty: ${asset}"
done

actual_count=0
while IFS= read -r -d '' path; do
  ((actual_count += 1))
  name="${path##*/}"
  [[ -n "${expected_names[$name]:-}" ]] ||
    die "unexpected release asset: ${name}"
done < <(find "$dist_dir" -maxdepth 1 -type f -print0)
[[ "$actual_count" -eq "${#expected_assets[@]}" ]] ||
  die "expected ${#expected_assets[@]} assets, found ${actual_count}"

for asset in "${expected_assets[@]:0:8}"; do
  unzip -tq "${dist_dir}/${asset}" >/dev/null ||
    die "release ZIP is corrupt: ${asset}"
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly script_dir
"${script_dir}/validate-toolchain-deb.sh" \
  "${dist_dir}/AltivecToolchain-${release_version}-iOS-armv7.deb" \
  "$release_version"

(
  cd "$dist_dir"
  sha256sum "${expected_assets[@]}" > SHA256SUMS
  sha256sum -c SHA256SUMS
)

[[ -s "${dist_dir}/SHA256SUMS" ]] || die 'SHA256SUMS was not created'
find "$dist_dir" -maxdepth 1 -type f -printf '%f\n' | sort
