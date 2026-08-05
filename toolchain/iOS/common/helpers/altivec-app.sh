#!/bin/bash

set -euo pipefail

readonly install_prefix="${ALTIVEC_APP_INSTALL_PREFIX:-/var/altivec}"
readonly template_root="${ALTIVEC_APP_TEMPLATE_ROOT:-${install_prefix}/share/altivec/templates/ios-app}"

app_name=""
bundle_id=""
display_name=""
destination=""
destination_created=0
destination_absolute=""
destination_parent_absolute=""

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf '%s\n' \
    'Usage:' \
    '  altivec-app new --name <executable-name> --bundle-id <identifier>' \
    '                  [--display-name <name>] [--destination <path>]' \
    '' \
    'Creates a complete Objective-C/C iOS application repository.' \
    'The destination must not already exist.'
}

require_value() {
  (($# >= 2)) || die "$1 requires a value"
}

if (($# == 0)); then
  usage >&2
  exit 2
fi

case "$1" in
  new)
    shift
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    die "unknown command: $1"
    ;;
esac

while (($# > 0)); do
  case "$1" in
    --name)
      require_value "$@"
      app_name="$2"
      shift 2
      ;;
    --bundle-id)
      require_value "$@"
      bundle_id="$2"
      shift 2
      ;;
    --display-name)
      require_value "$@"
      display_name="$2"
      shift 2
      ;;
    --destination)
      require_value "$@"
      destination="$2"
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

[[ "$app_name" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] ||
  die 'name must start with a letter and contain only letters, digits, _ or -'
[[ "$bundle_id" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ &&
   "$bundle_id" == *.* && "$bundle_id" != *..* ]] ||
  die 'bundle id must be a dot-separated identifier without wildcards'

if [[ -z "$display_name" ]]; then
  display_name="$app_name"
fi
[[ "$display_name" =~ ^[A-Za-z0-9][A-Za-z0-9._[:space:]-]*$ &&
   "$display_name" != *$'\n'* && "$display_name" != *$'\r'* ]] ||
  die 'display name contains unsupported characters'

if [[ -z "$destination" ]]; then
  destination="$app_name"
fi
while [[ "$destination" != / && "$destination" == */ ]]; do
  destination="${destination%/}"
done
case "$destination" in
  ''|/|.|..|*/.|*/..)
    die "unsafe destination: ${destination}"
    ;;
esac
[[ ! -e "$destination" && ! -L "$destination" ]] ||
  die "destination already exists: ${destination}"

for required_path in \
  Makefile \
  source/iOS/Makefile \
  source/iOS/Info.plist \
  source/iOS/Resources/Default.png \
  source/shared/Resources/en.lproj/Localizable.strings; do
  [[ -e "${template_root}/${required_path}" ]] ||
    die "installed template is incomplete: ${template_root}/${required_path}"
done

for tool_name in awk chmod cp dirname find grep mkdir mv rm; do
  command -v "$tool_name" >/dev/null 2>&1 ||
    die "required command is missing: ${tool_name}"
done

awk_tool="$(command -v awk)"
chmod_tool="$(command -v chmod)"
cp_tool="$(command -v cp)"
dirname_tool="$(command -v dirname)"
find_tool="$(command -v find)"
grep_tool="$(command -v grep)"
mkdir_tool="$(command -v mkdir)"
mv_tool="$(command -v mv)"
rm_tool="$(command -v rm)"
readonly awk_tool chmod_tool cp_tool dirname_tool find_tool grep_tool
readonly mkdir_tool mv_tool rm_tool

destination_parent="$($dirname_tool "$destination")"
"$mkdir_tool" -p "$destination_parent"
destination_parent_absolute="$(cd "$destination_parent" && /bin/pwd -P)"
if [[ "$destination_parent_absolute" == / ]]; then
  destination_absolute="/${destination##*/}"
else
  destination_absolute="${destination_parent_absolute}/${destination##*/}"
fi
template_absolute="$(cd "$template_root" && /bin/pwd -P)"
readonly destination_parent destination_parent_absolute
readonly destination_absolute template_absolute

case "$destination_absolute" in
  "$template_absolute"|"$template_absolute"/*)
    die 'destination must not be inside the installed template'
    ;;
esac

cleanup() {
  local rc=$?

  trap - EXIT
  if [[ "$rc" -ne 0 && "$destination_created" -eq 1 ]]; then
    case "$destination_absolute" in
      "$destination_parent_absolute"/*)
        if [[ -d "$destination_absolute" && ! -L "$destination_absolute" ]]; then
          "$rm_tool" -r -- "$destination_absolute"
        fi
        ;;
      *)
        printf 'warning: refusing to clean unexpected destination: %s\n' \
          "$destination_absolute" >&2
        ;;
    esac
  fi
  exit "$rc"
}
trap cleanup EXIT

"$mkdir_tool" "$destination"
destination_created=1
"$cp_tool" -R "${template_root}/." "${destination}/"
"$find_tool" "$destination" -type d -exec "$chmod_tool" 0755 {} +
"$find_tool" "$destination" -type f -exec "$chmod_tool" 0644 {} +

render_file() {
  local target="$1"
  local temporary="${target}.altivec-app.$$"

  "$awk_tool" \
    -v app_name="$app_name" \
    -v bundle_id="$bundle_id" \
    -v display_name="$display_name" '
      {
        gsub(/@ALTIVEC_APP_NAME@/, app_name)
        gsub(/@ALTIVEC_BUNDLE_ID@/, bundle_id)
        gsub(/@ALTIVEC_DISPLAY_NAME@/, display_name)
        print
      }
    ' "$target" > "$temporary"
  "$mv_tool" "$temporary" "$target"
  "$chmod_tool" 0644 "$target"
}

render_file "${destination}/README.md"
render_file "${destination}/source/iOS/Makefile"
render_file "${destination}/source/iOS/Info.plist"
"$chmod_tool" 0755 "${destination}/tools/generate-launch-images.sh"

if "$grep_tool" -R '@ALTIVEC_' "$destination" >/dev/null 2>&1; then
  die 'template rendering left an unresolved placeholder'
fi

destination_created=0
trap - EXIT

printf '%s\n' \
  "Created ${display_name} at ${destination_absolute}" \
  "Bundle identifier: ${bundle_id}" \
  '' \
  "  cd '${destination_absolute}'" \
  '  make clean' \
  '  make analyze' \
  '  make release'
