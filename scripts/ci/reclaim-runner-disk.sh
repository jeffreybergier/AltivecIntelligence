#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[[ "${GITHUB_ACTIONS:-}" == true ]] ||
  die 'runner disk cleanup is only permitted in GitHub Actions'

for tool in df rm sudo; do
  command -v "$tool" >/dev/null 2>&1 ||
    die "required runner cleanup tool not found: ${tool}"
done

# Standard hosted runners have limited free storage. These exact directories
# contain large preinstalled toolsets that neither the container runtime nor
# the toolchain build uses. Keep the allowlist explicit so this cannot turn
# into a broad cleanup if a variable or working directory changes.
readonly unused_toolsets=(
  /opt/ghc
  /opt/hostedtoolcache/CodeQL
  /usr/local/.ghcup
  /usr/local/lib/android
  /usr/share/dotnet
)

printf 'Runner disk before cleanup:\n'
df -h / "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is required}"

sudo -n true || die 'passwordless sudo is unavailable on this runner'
for path in "${unused_toolsets[@]}"; do
  case "$path" in
    /opt/ghc|/opt/hostedtoolcache/CodeQL|/usr/local/.ghcup|\
      /usr/local/lib/android|/usr/share/dotnet)
      ;;
    *)
      die "refusing to remove a path outside the cleanup allowlist: ${path}"
      ;;
  esac
  if [[ -e "$path" || -L "$path" ]]; then
    printf 'Removing unused hosted-runner toolset: %s\n' "$path"
    sudo rm -rf -- "$path"
  fi
done

printf 'Runner disk after cleanup:\n'
df -h / "$GITHUB_WORKSPACE"
