#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root_input="${script_dir}/.."
build_dir_input=""

usage() {
  printf '%s\n' \
    "Usage: $(basename "$0") [options]" \
    "" \
    "Options:" \
    "  --project-root <path>  Repository root." \
    "  --build-dir <path>     Build directory to remove." \
    "  -h, --help             Show this help."
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_value() {
  (($# >= 2)) || die "$1 requires a value"
}

while (($# > 0)); do
  case "$1" in
    --project-root)
      require_value "$@"
      project_root_input="$2"
      shift 2
      ;;
    --build-dir)
      require_value "$@"
      build_dir_input="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

command -v realpath >/dev/null 2>&1 ||
  die "required tool not found: realpath"

project_root="$(realpath -m "$project_root_input")"
if [[ -z "$build_dir_input" ]]; then
  build_dir_input="${project_root}/build-release"
fi
build_dir="$(realpath -m "$build_dir_input")"

[[ -d "$project_root" ]] || die "project root not found: ${project_root}"
[[ "$build_dir" == "${project_root}/build-release" ]] ||
  die "refusing to clean unsafe path: ${build_dir}"

rm -rf -- "$build_dir"
printf 'Removed %s\n' "$build_dir"
