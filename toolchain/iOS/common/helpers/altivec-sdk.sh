#!/bin/bash

set -euo pipefail

readonly install_prefix="${ALTIVEC_SDK_INSTALL_PREFIX:-/var/altivec}"
readonly sdk_root="${ALTIVEC_SDK_ROOT:-${install_prefix}/SDKs}"
readonly catalog_path="${ALTIVEC_SDK_CATALOG:-${install_prefix}/share/altivec-sdk/catalog.json}"
readonly state_root="${ALTIVEC_SDK_STATE_ROOT:-/var/lib/altivec-sdk}"
readonly testing="${ALTIVEC_SDK_TESTING:-0}"
if [[ "$testing" == '1' && -n "${ALTIVEC_SDK_ARCHIVE_DIR:-}" ]]; then
  archive_dir="$ALTIVEC_SDK_ARCHIVE_DIR"
else
  archive_dir=/var/root
fi
readonly archive_dir
readonly bin_dir="${install_prefix}/bin"
readonly current_sdk="${sdk_root}/Current.sdk"
readonly receipt_dir="${state_root}/receipts"
readonly receipt_path="${receipt_dir}/8.4.json"
readonly lock_dir="${state_root}/install.lock"
readonly archive_name='iPhoneOS8.4.sdk.tar.gz'
readonly directory='iPhoneOS8.4.sdk'
readonly sdk_path="${sdk_root}/${directory}"

staging_dir=""
receipt_temp=""
selection_temp=""
lock_held=0
sdk_entry=""

jq_tool=""
awk_tool=""
wc_tool=""
tar_tool=""
openssl_tool=""

readonly mkdir_tool='/bin/mkdir'
readonly mv_tool='/bin/mv'
readonly rm_tool='/bin/rm'
readonly ln_tool='/bin/ln'
readonly chmod_tool='/bin/chmod'
readonly mktemp_tool='/bin/mktemp'
readonly date_tool='/bin/date'

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf '%s\n' \
    'Usage:' \
    '  altivec-sdk help' \
    '  altivec-sdk status' \
    '  altivec-sdk preflight' \
    '  altivec-sdk install' \
    '  altivec-sdk uninstall' \
    '' \
    "Archive folder: ${archive_dir}" \
    "The default /var/root folder is root's ~/ on the iPhone." \
    'Place this exact file in that folder:' \
    "  ${archive_name}" \
    '' \
    "Expected path: ${archive_dir}/${archive_name}" \
    "Installed SDK: ${sdk_path}" \
    '' \
    'Run status, preflight, install, and uninstall as root.' \
    'This tool never downloads SDKs. It verifies and installs the local archive.'
}

require_exact_args() {
  local expected="$1"
  local message="$2"
  shift 2
  (($# == expected)) || die "$message"
}

resolve_tool() {
  local tool_name="$1"
  local preferred="${bin_dir}/${tool_name}"
  local resolved=""

  if [[ -x "$preferred" ]]; then
    printf '%s\n' "$preferred"
    return 0
  fi
  resolved="$(command -v "$tool_name" 2>/dev/null)" || return 1
  [[ -x "$resolved" ]] || return 1
  printf '%s\n' "$resolved"
}

require_tool() {
  local tool_name="$1"
  local resolved=""

  resolved="$(resolve_tool "$tool_name")" ||
    die "required command is missing: ${tool_name}"
  printf '%s\n' "$resolved"
}

initialize() {
  local system_tool catalog_valid

  [[ "$testing" == '0' || "$testing" == '1' ]] ||
    die 'ALTIVEC_SDK_TESTING must be 0 or 1'
  for system_tool in "$mkdir_tool" "$mv_tool" "$rm_tool" "$ln_tool" \
      "$chmod_tool" "$mktemp_tool" "$date_tool"; do
    [[ -x "$system_tool" ]] ||
      die "required system command is missing: ${system_tool}"
  done

  jq_tool="$(require_tool jq)"
  awk_tool="$(require_tool awk)"
  wc_tool="$(require_tool wc)"
  tar_tool="$(require_tool tar)"
  openssl_tool="$(require_tool openssl)"

  [[ -r "$catalog_path" ]] || die "SDK catalog is missing: ${catalog_path}"
  catalog_valid="$(
    "$jq_tool" -r '
      .schema == 3 and
      (.build_sdks | type == "array" and length == 3) and
      ([.build_sdks[] | select(.id == "iphoneos-8.4")] | length == 1) and
      (.build_sdks[] | select(.id == "iphoneos-8.4") |
        .platform == "iphoneos" and
        .version == "8.4" and
        .directory == "iPhoneOS8.4.sdk" and
        .archive == "iPhoneOS8.4.sdk.tar.gz" and
        .format == "tar.gz" and
        (.archive_bytes | type == "number" and . > 0) and
        (.sha256 | test("^[0-9a-f]{64}$")) and
        (.required_paths | type == "array" and length > 0) and
        (has("url") | not))
    ' "$catalog_path"
  )"
  [[ "$catalog_valid" == 'true' ]] ||
    die "SDK catalog is invalid: ${catalog_path}"
  sdk_entry="$(
    "$jq_tool" -cer '.build_sdks[] | select(.id == "iphoneos-8.4")' \
      "$catalog_path"
  )" || die 'iPhoneOS 8.4 is not in the bundled catalog'

  trap cleanup EXIT
}

require_root() {
  if [[ "$testing" == '1' ]]; then
    return 0
  fi
  [[ "${EUID}" -eq 0 ]] || die 'this command must run as root'
}

entry_value() {
  printf '%s\n' "$sdk_entry" | "$jq_tool" -er "$1"
}

hash_file() {
  local digest_output

  digest_output="$("$openssl_tool" dgst -sha256 "$1")"
  printf '%s\n' "${digest_output##*= }"
}

file_bytes() {
  # $1 below is an awk field reference.
  # shellcheck disable=SC2016
  "$wc_tool" -c < "$1" | "$awk_tool" '{print $1}'
}

cleanup() {
  local rc=$?
  local cleanup_rc=0

  trap - EXIT
  if [[ -n "$staging_dir" ]]; then
    case "$staging_dir" in
      "${sdk_root}"/.install.8.4.*)
        if [[ -d "$staging_dir" && ! -L "$staging_dir" ]]; then
          "$rm_tool" -r -- "$staging_dir" || cleanup_rc=1
        fi
        ;;
      *)
        printf 'warning: refusing to clean unexpected path: %s\n' \
          "$staging_dir" >&2
        cleanup_rc=1
        ;;
    esac
  fi
  if [[ -n "$receipt_temp" && -f "$receipt_temp" && ! -L "$receipt_temp" ]]; then
    case "$receipt_temp" in
      "${receipt_dir}"/.8.4.json.*)
        "$rm_tool" -f -- "$receipt_temp" || cleanup_rc=1
        ;;
      *) cleanup_rc=1 ;;
    esac
  fi
  if [[ -n "$selection_temp" && -L "$selection_temp" ]]; then
    case "$selection_temp" in
      "${sdk_root}"/.Current.sdk.*)
        "$rm_tool" -f -- "$selection_temp" || cleanup_rc=1
        ;;
      *) cleanup_rc=1 ;;
    esac
  fi
  if [[ "$lock_held" -eq 1 ]]; then
    "$rm_tool" -f -- "${lock_dir}/owner" "${lock_dir}/command" \
      2>/dev/null || cleanup_rc=1
    /bin/rmdir "$lock_dir" 2>/dev/null || cleanup_rc=1
  fi
  if [[ "$rc" -eq 0 && "$cleanup_rc" -ne 0 ]]; then
    rc=1
  fi
  exit "$rc"
}

ensure_runtime_dirs() {
  "$mkdir_tool" -p "$sdk_root" "$receipt_dir"
  "$chmod_tool" 0755 "$sdk_root" "$state_root" "$receipt_dir"
}

acquire_lock() {
  if ! "$mkdir_tool" "$lock_dir" 2>/dev/null; then
    die "another SDK operation holds the lock: ${lock_dir}"
  fi
  lock_held=1
  printf '%s\n' "$$" > "${lock_dir}/owner"
  printf '%s\n' "$1" > "${lock_dir}/command"
}

validate_archive_paths() {
  local archive="$1"
  local member normalized
  local member_count=0

  if ! "$tar_tool" -tzf "$archive" >/dev/null; then
    printf 'error: invalid SDK archive: %s\n' "$archive" >&2
    return 1
  fi
  while IFS= read -r member; do
    [[ -n "$member" ]] || continue
    normalized="${member#./}"
    case "$normalized" in
      /*|..|../*|*/../*|*/..|*/./*)
        printf 'error: unsafe path in SDK archive %s: %s\n' \
          "$archive" "$member" >&2
        return 1
        ;;
      "$directory"|"$directory"/*) ;;
      *)
        printf 'error: unexpected path in SDK archive %s: %s\n' \
          "$archive" "$member" >&2
        return 1
        ;;
    esac
    member_count=$((member_count + 1))
  done < <("$tar_tool" -tzf "$archive")
  if [[ "$member_count" -eq 0 ]]; then
    printf 'error: SDK archive is empty: %s\n' "$archive" >&2
    return 1
  fi
}

sdk_is_valid() {
  local path="$1"
  local required

  [[ -d "$path" && ! -L "$path" ]] || return 1
  while IFS= read -r required; do
    [[ -e "$path/$required" ]] || return 1
  done < <(printf '%s\n' "$sdk_entry" | "$jq_tool" -r '.required_paths[]')
  [[ -e "$path/usr/lib/libSystem.dylib" ||
    -f "$path/usr/lib/libSystem.B.dylib" ||
    -f "$path/usr/lib/libSystem.tbd" ]]
}

receipt_is_valid() {
  local expected="$1"

  [[ -f "$receipt_path" && ! -L "$receipt_path" ]] || return 1
  # $expected below is a jq variable.
  # shellcheck disable=SC2016
  "$jq_tool" -e --arg expected "$expected" \
    '.archive_sha256 == $expected' "$receipt_path" >/dev/null 2>&1
}

archive_state() {
  local archive="${archive_dir}/${archive_name}"
  local expected expected_bytes actual actual_bytes

  expected="$(entry_value '.sha256')"
  expected_bytes="$(entry_value '.archive_bytes | tostring')"
  if [[ ! -e "$archive" && ! -L "$archive" ]]; then
    printf 'missing\n'
  elif [[ ! -f "$archive" || -L "$archive" ]]; then
    printf 'invalid\n'
  else
    actual_bytes="$(file_bytes "$archive")"
    actual="$(hash_file "$archive")"
    if [[ "$actual_bytes" == "$expected_bytes" && "$actual" == "$expected" ]]; then
      printf 'available\n'
    else
      printf 'invalid\n'
    fi
  fi
}

installation_state() {
  local expected

  expected="$(entry_value '.sha256')"
  if sdk_is_valid "$sdk_path" && receipt_is_valid "$expected"; then
    printf 'installed\n'
  elif [[ -e "$sdk_path" || -L "$sdk_path" ]]; then
    printf 'invalid\n'
  else
    printf 'missing\n'
  fi
}

command_status() {
  local source_state install_state

  require_root
  source_state="$(archive_state)"
  install_state="$(installation_state)"
  printf 'Archive folder: %s\n\n' "$archive_dir"
  printf '%-14s %-28s %-10s %-12s\n' \
    SDK ARCHIVE SOURCE INSTALLATION
  printf '%-14s %-28s %-10s %-12s\n' \
    iPhoneOS8.4 "$archive_name" "$source_state" "$install_state"
}

command_preflight() {
  local archive="${archive_dir}/${archive_name}"
  local expected expected_bytes actual actual_bytes

  require_root
  expected="$(entry_value '.sha256')"
  expected_bytes="$(entry_value '.archive_bytes | tostring')"
  printf 'Checking %s...\n' "$archive"
  [[ -f "$archive" && ! -L "$archive" ]] ||
    die "required SDK archive is missing: ${archive}"
  actual_bytes="$(file_bytes "$archive")"
  [[ "$actual_bytes" == "$expected_bytes" ]] ||
    die "SDK size mismatch: got ${actual_bytes}; expected ${expected_bytes}"
  actual="$(hash_file "$archive")"
  [[ "$actual" == "$expected" ]] ||
    die "SDK checksum mismatch: got ${actual}; expected ${expected}"
  validate_archive_paths "$archive" || return 1
  printf 'SDK archive preflight passed: %s\n' "$archive_name"
}

write_receipt() {
  local expected installed_at

  expected="$(entry_value '.sha256')"
  installed_at="$("$date_tool" -u '+%Y-%m-%dT%H:%M:%SZ')"
  receipt_temp="${receipt_dir}/.8.4.json.$$"
  # Dollar-prefixed names below are jq variables.
  # shellcheck disable=SC2016
  "$jq_tool" -n -e \
    --arg version '8.4' \
    --arg archive "$archive_name" \
    --arg archive_sha256 "$expected" \
    --arg installed_at "$installed_at" \
    '{
      schema: 2,
      version: $version,
      archive: $archive,
      archive_sha256: $archive_sha256,
      installed_at: $installed_at
    }' > "$receipt_temp"
  "$chmod_tool" 0644 "$receipt_temp"
  "$mv_tool" "$receipt_temp" "$receipt_path"
  receipt_temp=""
}

select_installed_sdk() {
  if [[ -e "$current_sdk" && ! -L "$current_sdk" ]]; then
    die "selection path exists and is not a symlink: ${current_sdk}"
  fi
  selection_temp="${sdk_root}/.Current.sdk.$$"
  "$ln_tool" -s "$directory" "$selection_temp"
  if [[ -L "$current_sdk" ]]; then
    "$rm_tool" -f -- "$current_sdk"
  fi
  "$mv_tool" "$selection_temp" "$current_sdk"
  selection_temp=""
}

command_install() {
  local archive="${archive_dir}/${archive_name}"
  local extracted expected

  require_root
  command_preflight
  ensure_runtime_dirs
  acquire_lock 'install'
  expected="$(entry_value '.sha256')"

  if sdk_is_valid "$sdk_path" && receipt_is_valid "$expected"; then
    select_installed_sdk
    printf 'SDK already installed: %s\n' "$sdk_path"
    return 0
  fi
  if [[ -e "$sdk_path" || -L "$sdk_path" ]]; then
    die "existing SDK is incomplete or unverified: ${sdk_path}; run altivec-sdk uninstall first"
  fi
  if [[ -e "$current_sdk" && ! -L "$current_sdk" ]]; then
    die "selection path exists and is not a symlink: ${current_sdk}"
  fi

  staging_dir="$("$mktemp_tool" -d "${sdk_root}/.install.8.4.XXXXXX")"
  printf 'Extracting %s...\n' "$archive_name"
  "$tar_tool" --no-same-owner --no-same-permissions \
    -xzf "$archive" -C "$staging_dir"
  extracted="${staging_dir}/${directory}"
  sdk_is_valid "$extracted" || die 'extracted iPhoneOS 8.4 SDK failed validation'
  "$mv_tool" "$extracted" "$sdk_path"
  /bin/rmdir "$staging_dir"
  staging_dir=""
  write_receipt
  select_installed_sdk
  printf 'Installed SDK: %s\n' "$sdk_path"
}

command_uninstall() {
  local removed=0

  require_root
  ensure_runtime_dirs
  acquire_lock 'uninstall'
  case "$sdk_path" in
    "${sdk_root}"/iPhoneOS8.4.sdk) ;;
    *) die "refusing to uninstall unexpected SDK path: ${sdk_path}" ;;
  esac
  if [[ -e "$current_sdk" && ! -L "$current_sdk" ]]; then
    die "selection path exists and is not a symlink: ${current_sdk}"
  fi
  if [[ -L "$current_sdk" ]]; then
    "$rm_tool" -f -- "$current_sdk"
  fi
  if [[ -d "$sdk_path" && ! -L "$sdk_path" ]]; then
    "$rm_tool" -r -- "$sdk_path"
    removed=1
  elif [[ -e "$sdk_path" || -L "$sdk_path" ]]; then
    "$rm_tool" -f -- "$sdk_path"
    removed=1
  fi
  "$rm_tool" -f -- "$receipt_path"
  if [[ "$removed" -eq 1 ]]; then
    printf 'Uninstalled SDK: %s\n' "$sdk_path"
  else
    printf 'SDK not installed: %s\n' "$sdk_path"
  fi
  printf 'Source archive left untouched: %s/%s\n' \
    "$archive_dir" "$archive_name"
}

command_name="${1:-}"
case "$command_name" in
  -h|--help|help)
    require_exact_args 1 'help takes no arguments' "$@"
    usage
    exit 0
    ;;
  '')
    usage >&2
    exit 2
    ;;
esac

initialize
case "$command_name" in
  status)
    require_exact_args 1 'status takes no arguments' "$@"
    command_status
    ;;
  preflight)
    require_exact_args 1 'preflight takes no arguments' "$@"
    command_preflight
    ;;
  install)
    require_exact_args 1 'install takes no arguments' "$@"
    command_install
    ;;
  uninstall)
    require_exact_args 1 'uninstall takes no arguments' "$@"
    command_uninstall
    ;;
  *)
    usage >&2
    printf 'error: unknown command: %s\n' "$command_name" >&2
    exit 2
    ;;
esac
