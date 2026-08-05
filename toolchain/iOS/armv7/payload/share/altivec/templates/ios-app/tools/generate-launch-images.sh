#!/bin/bash

set -euo pipefail

master=""
force=0
project_root="$(cd "$(dirname "$0")/.." && /bin/pwd -P)"
resource_dir="${project_root}/source/iOS/Resources"

usage() {
  printf '%s\n' \
    "Usage: $(basename "$0") --master <png> [--force]" \
    '' \
    'Creates the canonical legacy iPhone launch-image matrix.' \
    'Existing launch images are preserved unless --force is supplied.'
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

while (($# > 0)); do
  case "$1" in
    --master)
      (($# >= 2)) || die '--master requires a value'
      master="$2"
      shift 2
      ;;
    --force)
      force=1
      shift
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

[[ -n "$master" ]] || die '--master is required'
[[ -f "$master" ]] || die "master image not found: ${master}"

magick_tool="${ALTIVEC_MAGICK:-/var/altivec/bin/magick}"
if [[ ! -x "$magick_tool" ]]; then
  magick_tool="$(command -v magick 2>/dev/null || true)"
fi
[[ -n "$magick_tool" && -x "$magick_tool" ]] ||
  die 'ImageMagick magick command not found'

outputs=(
  Default.png
  Default@2x.png
  Default-568h@2x.png
  Default-iOS8-667h@2x.png
  Default-iOS8-736h@3x.png
  Default-iOS11-812h@3x.png
  Default-iOS12-896h@2x.png
  Default-iOS12-896h@3x.png
)

if [[ "$force" -ne 1 ]]; then
  for output in "${outputs[@]}"; do
    [[ ! -e "${resource_dir}/${output}" ]] ||
      die "launch image already exists (use --force): ${resource_dir}/${output}"
  done
fi

/bin/mkdir -p "$resource_dir"

make_launch_image() {
  local width="$1"
  local height="$2"
  local output="$3"

  "$magick_tool" "$master" \
    -colorspace sRGB \
    -filter Lanczos \
    -resize "${width}x${height}^" \
    -gravity center \
    -extent "${width}x${height}" \
    -background '#ffffff' \
    -alpha remove \
    -alpha off \
    -strip \
    "PNG24:${resource_dir}/${output}"
}

make_launch_image 320 480 Default.png
make_launch_image 640 960 Default@2x.png
make_launch_image 640 1136 Default-568h@2x.png
make_launch_image 750 1334 Default-iOS8-667h@2x.png
make_launch_image 1242 2208 Default-iOS8-736h@3x.png
make_launch_image 1125 2436 Default-iOS11-812h@3x.png
make_launch_image 828 1792 Default-iOS12-896h@2x.png
make_launch_image 1242 2688 Default-iOS12-896h@3x.png

printf 'Launch images written to %s\n' "$resource_dir"
