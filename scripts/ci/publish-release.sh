#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

if (($# != 4)); then
  printf 'Usage: %s <stage|publish> <tag> <commit-sha> <dist-directory>\n' \
    "$(basename "$0")" >&2
  exit 2
fi

for tool in awk find gh jq mkdir mktemp realpath rm sha256sum sort stat; do
  command -v "$tool" >/dev/null 2>&1 ||
    die "required publishing tool not found: ${tool}"
done

readonly mode="$1"
readonly release_tag="$2"
readonly release_sha="$3"
dist_dir="$(realpath -m "$4")"
readonly dist_dir
readonly repository="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

[[ "$mode" == stage || "$mode" == publish ]] || die "invalid mode: ${mode}"
[[ "$release_tag" =~ ^v[0-9]+([.][0-9]+){0,2}$ ]] ||
  die "invalid release tag: ${release_tag}"
[[ "$release_sha" =~ ^[0-9a-f]{40}$ ]] ||
  die "invalid release commit: ${release_sha}"
[[ -d "$dist_dir" && ! -L "$dist_dir" ]] ||
  die "dist directory is missing or unsafe: ${dist_dir}"

mapfile -d '' -t local_assets < <(
  find "$dist_dir" -maxdepth 1 -type f -print0 | sort -z
)
[[ "${#local_assets[@]}" -gt 0 ]] || die 'no local release assets found'

declare -A local_names=()
for path in "${local_assets[@]}"; do
  name="${path##*/}"
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] ||
    die "unsafe release asset name: ${name}"
  [[ -z "${local_names[$name]:-}" ]] || die "duplicate local asset: ${name}"
  local_names["$name"]=1
done

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/altivec-release.XXXXXX")"
readonly temporary_root
cleanup() {
  local rc=$?
  trap - EXIT
  case "$temporary_root" in
    "${TMPDIR:-/tmp}"/altivec-release.*)
      rm -rf -- "$temporary_root"
      ;;
    *)
      printf 'error: refusing to remove unsafe temporary path: %s\n' \
        "$temporary_root" >&2
      rc=1
      ;;
  esac
  exit "$rc"
}
trap cleanup EXIT

get_release() {
  gh api "repos/${repository}/releases/tags/${release_tag}"
}

release_json=''
if ! release_json="$(get_release 2>/dev/null)"; then
  if [[ "$mode" == publish ]]; then
    die "draft release does not exist: ${release_tag}"
  fi
  gh release create "$release_tag" \
    --repo "$repository" \
    --target "$release_sha" \
    --generate-notes \
    --draft
  release_json="$(get_release)"
fi

release_id="$(jq -r '.id // empty' <<< "$release_json")"
readonly release_id
[[ "$release_id" =~ ^[0-9]+$ ]] || die 'GitHub returned an invalid release ID'

download_and_compare() {
  local name="$1"
  local local_path="$2"
  local download_dir="${temporary_root}/download-${name}"
  local downloaded="${download_dir}/${name}"

  mkdir -p "$download_dir"
  gh release download "$release_tag" \
    --repo "$repository" \
    --pattern "$name" \
    --dir "$download_dir"
  [[ -f "$downloaded" ]] || die "could not download existing asset: ${name}"
  [[ "$(sha256sum "$downloaded" | awk '{ print $1 }')" == \
      "$(sha256sum "$local_path" | awk '{ print $1 }')" ]] ||
    die "existing release asset differs from local file: ${name}"
}

verify_existing_asset() {
  local asset_json="$1"
  local local_path="$2"
  local name="${local_path##*/}"
  local remote_size=''
  local local_size=''
  local remote_digest=''
  local local_digest=''

  remote_size="$(jq -r '.size // empty' <<< "$asset_json")"
  local_size="$(stat -c %s "$local_path")"
  [[ "$remote_size" == "$local_size" ]] ||
    die "existing release asset has the wrong size: ${name}"

  remote_digest="$(jq -r '.digest // empty' <<< "$asset_json")"
  local_digest="sha256:$(sha256sum "$local_path" | awk '{ print $1 }')"
  if [[ -n "$remote_digest" ]]; then
    [[ "$remote_digest" == "$local_digest" ]] ||
      die "existing release asset has the wrong digest: ${name}"
  else
    download_and_compare "$name" "$local_path"
  fi
}

stage_assets() {
  local release="$1"
  local path=''
  local name=''
  local matches=''
  local asset_json=''

  for path in "${local_assets[@]}"; do
    name="${path##*/}"
    matches="$(
      jq --arg name "$name" '[.assets[] | select(.name == $name)] | length' \
        <<< "$release"
    )"
    if [[ "$matches" == 0 ]]; then
      gh release upload "$release_tag" "$path" --repo "$repository"
      release="$(get_release)"
    elif [[ "$matches" == 1 ]]; then
      asset_json="$(
        jq -c --arg name "$name" '.assets[] | select(.name == $name)' \
          <<< "$release"
      )"
      verify_existing_asset "$asset_json" "$path"
    else
      die "release contains duplicate assets named ${name}"
    fi
  done

  release_json="$release"
}

verify_exact_assets() {
  local release="$1"
  local remote_count=''
  local name=''
  local path=''
  local asset_json=''

  remote_count="$(jq '.assets | length' <<< "$release")"
  [[ "$remote_count" -eq "${#local_assets[@]}" ]] ||
    die "release has ${remote_count} uploaded assets; expected ${#local_assets[@]}"

  while IFS= read -r name; do
    [[ -n "${local_names[$name]:-}" ]] ||
      die "release contains an unexpected asset: ${name}"
  done < <(jq -r '.assets[].name' <<< "$release")

  for path in "${local_assets[@]}"; do
    name="${path##*/}"
    asset_json="$(
      jq -c --arg name "$name" '.assets[] | select(.name == $name)' \
        <<< "$release"
    )"
    [[ -n "$asset_json" ]] || die "release asset was not uploaded: ${name}"
    verify_existing_asset "$asset_json" "$path"
  done
}

if [[ "$mode" == stage ]]; then
  if [[ "$(jq -r '.draft' <<< "$release_json")" == false ]]; then
    verify_exact_assets "$release_json"
    printf 'Release %s is already published with matching assets.\n' \
      "$release_tag"
    exit 0
  fi
  stage_assets "$release_json"
  verify_exact_assets "$release_json"
  printf 'Draft release %s has all verified assets.\n' "$release_tag"
  exit 0
fi

verify_exact_assets "$release_json"
if [[ "$(jq -r '.draft' <<< "$release_json")" == true ]]; then
  gh release edit "$release_tag" --repo "$repository" --draft=false
  release_json="$(get_release)"
fi
[[ "$(jq -r '.draft' <<< "$release_json")" == false ]] ||
  die "release is still a draft: ${release_tag}"
printf 'Published immutable release inputs for %s.\n' "$release_tag"
