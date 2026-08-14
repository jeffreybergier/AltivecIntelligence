#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

for tool in awk gh jq; do
  command -v "$tool" >/dev/null 2>&1 || die "required tool not found: ${tool}"
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly script_dir
repository_root="$(cd -- "${script_dir}/../.." && pwd -P)"
readonly repository_root
readonly common_file="${repository_root}/libs/cocoa/cocoa_common.mk"
readonly issue_title="Font Awesome Free update available"

pinned_version="$(awk '
  $1 == "FONTAWESOME_VERSION" && $2 == "=" { print $3; exit }
' "$common_file")"
[[ "$pinned_version" =~ ^[0-9]+([.][0-9]+){2}$ ]] ||
  die "invalid pinned Font Awesome version: ${pinned_version:-missing}"

latest_version="${FONT_AWESOME_LATEST_VERSION:-}"
release_url="${FONT_AWESOME_LATEST_URL:-}"
if [[ -z "$latest_version" || -z "$release_url" ]]; then
  release_json="$(
    gh api repos/FortAwesome/Font-Awesome/releases/latest
  )"
  latest_version="$(jq -r '.tag_name // empty' <<< "$release_json")"
  release_url="$(jq -r '.html_url // empty' <<< "$release_json")"
fi
latest_version="${latest_version#v}"
[[ "$latest_version" =~ ^[0-9]+([.][0-9]+){2}$ ]] ||
  die "invalid upstream Font Awesome version: ${latest_version:-missing}"
[[ "$release_url" == https://github.com/FortAwesome/Font-Awesome/* ]] ||
  die "unexpected Font Awesome release URL: ${release_url:-missing}"

version_is_newer() {
  awk -v candidate="$1" -v current="$2" 'BEGIN {
    split(candidate, a, ".");
    split(current, b, ".");
    for (i = 1; i <= 3; i++) {
      if ((a[i] + 0) > (b[i] + 0)) exit 0;
      if ((a[i] + 0) < (b[i] + 0)) exit 1;
    }
    exit 1;
  }'
}

printf 'Pinned Font Awesome Free: %s\n' "$pinned_version"
printf 'Latest Font Awesome Free: %s\n' "$latest_version"

if [[ "${FONT_AWESOME_UPDATE_DRY_RUN:-0}" == 1 ]]; then
  if version_is_newer "$latest_version" "$pinned_version"; then
    printf 'Update available: %s\n' "$release_url"
  else
    printf 'Pinned version is current.\n'
  fi
  exit 0
fi

repository="${GITHUB_REPOSITORY:-}"
[[ "$repository" =~ ^[^/]+/[^/]+$ ]] ||
  die "GITHUB_REPOSITORY is missing or invalid"

open_issues="$(gh api "repos/${repository}/issues?state=open&per_page=100")"
issue_number="$(
  jq -r --arg title "$issue_title" '
    [
      .[] | select(.pull_request == null and .title == $title)
    ][0].number // empty
  ' <<< "$open_issues"
)"

if ! version_is_newer "$latest_version" "$pinned_version"; then
  if [[ -n "$issue_number" ]]; then
    gh issue close "$issue_number" --repo "$repository" \
      --comment "The pinned version now matches or exceeds the latest release."
  fi
  exit 0
fi

printf -v issue_body '%s\n' \
  "Font Awesome Free ${latest_version} is available; this repository pins" \
  "${pinned_version} in libs/cocoa/cocoa_common.mk." \
  "" \
  "Upstream release: ${release_url}" \
  "" \
  "Upgrade checklist:" \
  "" \
  "- Bump FONTAWESOME_VERSION and all three SHA-256 checksums." \
  "- Run make -C libs/cocoa fontawesome-icons." \
  "- Replace the upstream and embedded license texts if they changed." \
  "- Build and verify the macOS framework and iOS static package." \
  "" \
  "This issue is maintained by the Check Font Awesome workflow."

if [[ -z "$issue_number" ]]; then
  gh issue create --repo "$repository" --title "$issue_title" \
    --body "$issue_body"
  exit 0
fi

existing_body="$(
  gh issue view "$issue_number" --repo "$repository" --json body --jq .body
)"
if [[ "$existing_body" != "$issue_body" ]]; then
  gh issue edit "$issue_number" --repo "$repository" --body "$issue_body"
fi
