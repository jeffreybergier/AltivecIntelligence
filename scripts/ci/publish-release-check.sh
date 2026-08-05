#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

for tool in awk chmod cp find jq mkdir mktemp rm sha256sum stat; do
  command -v "$tool" >/dev/null 2>&1 ||
    die "required publisher-test tool not found: ${tool}"
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly script_dir
check_root="$(mktemp -d "${TMPDIR:-/tmp}/altivec-publish-check.XXXXXX")"
readonly check_root

cleanup() {
  local rc=$?
  trap - EXIT
  case "$check_root" in
    "${TMPDIR:-/tmp}"/altivec-publish-check.*)
      rm -rf -- "$check_root"
      ;;
    *)
      printf 'error: refusing to remove unsafe test path: %s\n' \
        "$check_root" >&2
      rc=1
      ;;
  esac
  exit "$rc"
}
trap cleanup EXIT

mkdir -p "$check_root/bin" "$check_root/state/assets" "$check_root/dist"

mock_gh="$check_root/bin/gh"
readonly mock_gh
cp "$script_dir/fixtures/mock-gh" "$mock_gh"
chmod 0755 "$mock_gh"

printf 'asset one\n' > "$check_root/dist/Asset-1.2.3.zip"
printf 'checksums\n' > "$check_root/dist/SHA256SUMS"

export PATH="$check_root/bin:$PATH"
export MOCK_GH_STATE="$check_root/state"
export GITHUB_REPOSITORY='example/AltivecIntelligence'
export GH_TOKEN='test-token'

readonly tag='v1.2.3'
readonly sha='0123456789abcdef0123456789abcdef01234567'
readonly publisher="${script_dir}/publish-release.sh"

"$publisher" stage "$tag" "$sha" "$check_root/dist" >/dev/null
[[ "$(jq -r '.draft' "$check_root/state/release.json")" == true ]] ||
  die 'stage did not leave a draft release'
[[ "$(find "$check_root/state/assets" -maxdepth 1 -type f | awk 'END { print NR }')" == 2 ]] ||
  die 'stage did not upload the expected assets'

MOCK_GH_OMIT_DIGEST=1 \
  "$publisher" stage "$tag" "$sha" "$check_root/dist" >/dev/null
"$publisher" publish "$tag" "$sha" "$check_root/dist" >/dev/null
[[ "$(jq -r '.draft' "$check_root/state/release.json")" == false ]] ||
  die 'publish did not make the release public'

"$publisher" publish "$tag" "$sha" "$check_root/dist" >/dev/null
printf 'changed asset\n' > "$check_root/dist/Asset-1.2.3.zip"
if "$publisher" stage "$tag" "$sha" "$check_root/dist" \
    > /dev/null 2>&1; then
  die 'publisher accepted a changed immutable asset'
fi

printf 'Release publisher validation passed.\n'
