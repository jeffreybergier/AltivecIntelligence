#!/bin/bash

set -euo pipefail

readonly install_prefix="${ALTIVEC_SDK_INSTALL_PREFIX:-/var/altivec}"
readonly sdk_root="${ALTIVEC_SDK_ROOT:-${install_prefix}/SDKs}"
readonly catalog_path="${ALTIVEC_SDK_CATALOG:-${install_prefix}/share/altivec-sdk/catalog.json}"
readonly state_root="${ALTIVEC_SDK_STATE_ROOT:-/var/lib/altivec-sdk}"
readonly cache_root="${ALTIVEC_SDK_CACHE_ROOT:-/var/cache/altivec-sdk}"
readonly temporary_root="${ALTIVEC_SDK_TMP_ROOT:-/var/tmp}"
readonly bin_dir="${install_prefix}/bin"
readonly current_sdk="${sdk_root}/Current.sdk"
readonly receipt_dir="${state_root}/receipts"
readonly download_dir="${cache_root}/downloads"
readonly lock_dir="${state_root}/install.lock"
readonly github_download_prefix='https://github.com/okanon/iPhoneOS.sdk/releases/download/v0.0.1'
readonly testing="${ALTIVEC_SDK_TESTING:-0}"

staging_dir=""
verify_dir=""
receipt_temp=""
selection_temp=""
lock_held=0

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

usage() {
  printf '%s\n' \
    'Usage:' \
    '  altivec-sdk install <version>' \
    '  altivec-sdk list' \
    '  altivec-sdk remove <version>' \
    '  altivec-sdk select <version>' \
    '  altivec-sdk verify <version>' \
    '' \
    'Installs verified iPhoneOS SDKs from the pinned' \
    'okanon/iPhoneOS.sdk v0.0.1 GitHub release.'
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

jq_tool="$(require_tool jq)"
grep_tool="$(require_tool grep)"
awk_tool="$(require_tool awk)"
clang_tool="$(require_tool clang)"
linker_tool="$(require_tool ld)"
file_tool="$(require_tool file)"
otool_tool="$(require_tool otool)"
tar_tool="$(require_tool tar)"
curl_tool="$(require_tool curl)"
openssl_tool="$(require_tool openssl)"
readonly jq_tool grep_tool awk_tool clang_tool linker_tool
readonly file_tool otool_tool tar_tool curl_tool openssl_tool

readonly mkdir_tool="/bin/mkdir"
readonly mv_tool="/bin/mv"
readonly rm_tool="/bin/rm"
readonly ln_tool="/bin/ln"
readonly chmod_tool="/bin/chmod"
readonly readlink_tool="/bin/readlink"
readonly mktemp_tool="/bin/mktemp"
readonly date_tool="/bin/date"
readonly uname_tool="/bin/uname"
readonly sysctl_tool="/usr/sbin/sysctl"
readonly dpkg_tool="/usr/bin/dpkg"
readonly df_tool="/usr/bin/df"

for system_tool in "$mkdir_tool" "$mv_tool" "$rm_tool" "$ln_tool" \
  "$chmod_tool" "$readlink_tool" "$mktemp_tool" "$date_tool" \
  "$uname_tool" "$df_tool"; do
  [[ -x "$system_tool" ]] ||
    die "required system command is missing: ${system_tool}"
done

[[ "$testing" == "0" || "$testing" == "1" ]] ||
  die 'ALTIVEC_SDK_TESTING must be 0 or 1'

[[ -r "$catalog_path" ]] ||
  die "SDK catalog is missing: ${catalog_path}"

catalog_valid="$(
  "$jq_tool" -r '
    .schema == 1 and
    .source.repository == "okanon/iPhoneOS.sdk" and
    .source.release_tag == "v0.0.1" and
    (.sdks | type == "array" and length > 0)
  ' "$catalog_path"
)"
[[ "$catalog_valid" == "true" ]] ||
  die "SDK catalog is invalid: ${catalog_path}"

cleanup_temp_dir() {
  local path="$1"

  [[ -n "$path" ]] || return 0
  case "$path" in
    "${sdk_root}"/.install.*|"${temporary_root}"/altivec-sdk-verify.*)
      ;;
    *)
      warn "refusing to clean unexpected temporary path: ${path}"
      return 1
      ;;
  esac

  if [[ -d "$path" && ! -L "$path" ]]; then
    "$rm_tool" -r -- "$path"
  elif [[ -e "$path" || -L "$path" ]]; then
    warn "temporary path is not a real directory: ${path}"
    return 1
  fi
}

cleanup() {
  local rc=$?
  local cleanup_rc=0

  trap - EXIT

  if ! cleanup_temp_dir "$verify_dir"; then
    cleanup_rc=1
  fi
  if ! cleanup_temp_dir "$staging_dir"; then
    cleanup_rc=1
  fi

  if [[ -n "$receipt_temp" && -f "$receipt_temp" &&
      ! -L "$receipt_temp" ]]; then
    case "$receipt_temp" in
      "${receipt_dir}"/.*.json.*)
        "$rm_tool" -f -- "$receipt_temp" || cleanup_rc=1
        ;;
      *)
        warn "refusing to clean unexpected receipt path: ${receipt_temp}"
        cleanup_rc=1
        ;;
    esac
  fi

  if [[ -n "$selection_temp" && -L "$selection_temp" ]]; then
    case "$selection_temp" in
      "${sdk_root}"/.Current.sdk.*)
        "$rm_tool" -f -- "$selection_temp" || cleanup_rc=1
        ;;
      *)
        warn "refusing to clean unexpected selection path: ${selection_temp}"
        cleanup_rc=1
        ;;
    esac
  fi

  if [[ "$lock_held" -eq 1 ]]; then
    "$rm_tool" -f -- "${lock_dir}/owner" 2>/dev/null || cleanup_rc=1
    "$rm_tool" -f -- "${lock_dir}/command" 2>/dev/null || cleanup_rc=1
    /bin/rmdir "$lock_dir" 2>/dev/null || cleanup_rc=1
  fi

  if [[ "$rc" -eq 0 && "$cleanup_rc" -ne 0 ]]; then
    rc=1
  fi
  exit "$rc"
}
trap cleanup EXIT

require_root() {
  if [[ "$testing" == "1" ]]; then
    return 0
  fi
  [[ "${EUID}" -eq 0 ]] || die 'this command must run as root'
}

validate_version() {
  local version="$1"
  [[ "$version" =~ ^[0-9]+[.][0-9]+$ ]] ||
    die "invalid SDK version: ${version}"
}

catalog_entry() {
  local version="$1"
  local entry=""

  entry="$(
    # shellcheck disable=SC2016
    "$jq_tool" -cer --arg version "$version" \
      '.sdks[] | select(.version == $version)' "$catalog_path"
  )" || die "SDK ${version} is not in the bundled catalog"
  printf '%s\n' "$entry"
}

entry_value() {
  local entry="$1"
  local filter="$2"
  printf '%s\n' "$entry" | "$jq_tool" -er "$filter"
}

device_model=""
device_arch="unknown"
dpkg_arch="unknown"
toolchain_has_armv7=0
toolchain_has_arm64=0
linker_has_tapi=0
toolchain_targets=""
linker_version=""

detect_capabilities() {
  local arm64_capable=""
  local processor=""
  local targets_output=""
  local linker_output=""

  device_model="$("$uname_tool" -m 2>/dev/null || printf 'unknown')"
  processor="$("$uname_tool" -p 2>/dev/null || printf 'unknown')"

  if [[ -x "$sysctl_tool" ]]; then
    arm64_capable="$(
      "$sysctl_tool" -n hw.optional.arm64 2>/dev/null || true
    )"
  fi
  if [[ -x "$dpkg_tool" ]]; then
    dpkg_arch="$(
      "$dpkg_tool" --print-architecture 2>/dev/null || printf 'unknown'
    )"
  fi

  if [[ "$arm64_capable" == "1" || "$dpkg_arch" == *arm64* ||
      "$processor" == "arm64" ]]; then
    device_arch="arm64"
  elif [[ "$processor" == arm* || "$dpkg_arch" == "iphoneos-arm" ]]; then
    device_arch="armv7"
  fi

  targets_output="$("$clang_tool" --print-targets 2>/dev/null || true)"
  if printf '%s\n' "$targets_output" |
      "$grep_tool" -Eq '^[[:space:]]*arm[[:space:]]+-'; then
    toolchain_has_armv7=1
  fi
  if printf '%s\n' "$targets_output" |
      "$grep_tool" -Eq '^[[:space:]]*aarch64[[:space:]]+-'; then
    toolchain_has_arm64=1
  fi

  toolchain_targets=""
  [[ "$toolchain_has_armv7" -eq 1 ]] && toolchain_targets="armv7"
  if [[ "$toolchain_has_arm64" -eq 1 ]]; then
    toolchain_targets="${toolchain_targets:+${toolchain_targets},}arm64"
  fi
  [[ -n "$toolchain_targets" ]] || toolchain_targets="none"

  linker_output="$("$linker_tool" -v 2>&1 || true)"
  if [[ "$linker_output" == *"TAPI support using:"* ]]; then
    linker_has_tapi=1
  fi
  linker_version="${linker_output%%$'\n'*}"
  [[ -n "$linker_version" ]] || linker_version="unknown"
}

compatible_arches=""
incompatibility_reason=""

evaluate_compatibility() {
  local sdk_arches="$1"
  local linker_input="$2"
  local sdk_arch=""

  compatible_arches=""
  incompatibility_reason=""

  for sdk_arch in ${sdk_arches//,/ }; do
    case "$sdk_arch" in
      armv7)
        if [[ "$toolchain_has_armv7" -eq 1 ]]; then
          compatible_arches="${compatible_arches:+${compatible_arches},}armv7"
        fi
        ;;
      arm64)
        if [[ "$toolchain_has_arm64" -eq 1 ]]; then
          compatible_arches="${compatible_arches:+${compatible_arches},}arm64"
        fi
        ;;
    esac
  done

  if [[ -z "$compatible_arches" ]]; then
    incompatibility_reason="SDK targets ${sdk_arches}; Clang targets ${toolchain_targets}"
    return 1
  fi

  if [[ "$linker_input" == "tapi" && "$linker_has_tapi" -ne 1 ]]; then
    incompatibility_reason='installed linker lacks TAPI framework discovery'
    compatible_arches=""
    return 1
  fi
  return 0
}

evaluate_entry() {
  local entry="$1"
  local sdk_arches=""
  local linker_input=""

  IFS=$'\t' read -r sdk_arches linker_input < <(
    printf '%s\n' "$entry" |
      "$jq_tool" -er \
        '[(.architectures | join(",")), .linker_input] | @tsv'
  )
  evaluate_compatibility "$sdk_arches" "$linker_input"
}

preferred_architecture() {
  local arches="$1"

  if [[ "$device_arch" == "arm64" && ",${arches}," == *,arm64,* ]]; then
    printf 'arm64\n'
  elif [[ ",${arches}," == *,armv7,* ]]; then
    printf 'armv7\n'
  elif [[ ",${arches}," == *,arm64,* ]]; then
    printf 'arm64\n'
  else
    return 1
  fi
}

format_mib() {
  local bytes="$1"
  "$awk_tool" -v bytes="$bytes" \
    'BEGIN { printf "%.1f MiB", bytes / 1048576 }'
}

ensure_runtime_dirs() {
  "$mkdir_tool" -p "$sdk_root" "$receipt_dir" "$download_dir"
  "$chmod_tool" 0755 "$sdk_root" "$state_root" "$receipt_dir"
  "$chmod_tool" 0700 "$cache_root" "$download_dir"
}

acquire_lock() {
  if ! "$mkdir_tool" "$lock_dir" 2>/dev/null; then
    die "another SDK operation holds the lock: ${lock_dir}"
  fi
  lock_held=1
  printf '%s\n' "$$" > "${lock_dir}/owner"
  printf '%s\n' "${1:-unknown}" > "${lock_dir}/command"
}

validate_sdk_directory() {
  local version="$1"
  local sdk_path="$2"

  [[ -d "$sdk_path" && ! -L "$sdk_path" ]] ||
    die "SDK is not a real directory: ${sdk_path}"
  [[ -f "$sdk_path/SDKSettings.plist" ]] ||
    die "SDK ${version} is missing SDKSettings.plist"
  [[ -f "$sdk_path/System/Library/Frameworks/Foundation.framework/Headers/Foundation.h" ]] ||
    die "SDK ${version} is missing Foundation headers"
  [[ -f "$sdk_path/System/Library/Frameworks/UIKit.framework/Headers/UIKit.h" ]] ||
    die "SDK ${version} is missing UIKit headers"

  if [[ ! -e "$sdk_path/usr/lib/libSystem.dylib" &&
      ! -f "$sdk_path/usr/lib/libSystem.B.dylib" &&
      ! -f "$sdk_path/usr/lib/libSystem.tbd" ]]; then
    die "SDK ${version} is missing a libSystem linker input"
  fi
}

validate_archive_paths() {
  local archive_path="$1"
  local expected_directory="$2"
  local member=""
  local normalized=""
  local member_count=0

  "$tar_tool" -tzf "$archive_path" >/dev/null ||
    die 'downloaded SDK archive is not a valid gzip-compressed tar archive'

  while IFS= read -r member; do
    [[ -n "$member" ]] || continue
    case "$member" in
      /*)
        die "SDK archive contains an absolute path: ${member}"
        ;;
    esac

    normalized="${member#./}"
    case "$normalized" in
      ""|"."|..|../*|*/../*|*/..|*/./*)
        die "SDK archive contains an unsafe path: ${member}"
        ;;
      "$expected_directory"|"$expected_directory"/*)
        ;;
      *)
        die "SDK archive has an unexpected top-level path: ${member}"
        ;;
    esac
    member_count=$((member_count + 1))
  done < <("$tar_tool" -tzf "$archive_path")

  [[ "$member_count" -gt 0 ]] || die 'SDK archive is empty'
}

run_sdk_smoke_test() {
  local version="$1"
  local sdk_path="$2"
  local arches="$3"
  local architecture=""
  local deployment_target=""
  local entry=""
  local source_path=""
  local executable_path=""
  local file_output=""
  local target_triple=""

  architecture="$(preferred_architecture "$arches")" ||
    die "cannot choose a verification architecture from: ${arches}"
  entry="$(catalog_entry "$version")"
  # shellcheck disable=SC2016
  deployment_target="$(
    printf '%s\n' "$entry" |
      "$jq_tool" -er --arg arch "$architecture" \
        '.deployment_targets[$arch]'
  )"

  case "$architecture" in
    armv7) target_triple="armv7-apple-ios${deployment_target}" ;;
    arm64) target_triple="arm64-apple-ios${deployment_target}" ;;
    *) die "unsupported verification architecture: ${architecture}" ;;
  esac

  verify_dir="$(
    "$mktemp_tool" -d \
      "${temporary_root}/altivec-sdk-verify.${version}.XXXXXX"
  )"
  source_path="${verify_dir}/main.m"
  executable_path="${verify_dir}/sdk-smoke"

  printf '%s\n' \
    '#import <Foundation/Foundation.h>' \
    '#import <UIKit/UIKit.h>' \
    'int main(void) { return 0; }' > "$source_path"

  printf 'Checking SDK %s headers for %s...\n' "$version" "$architecture"
  "$clang_tool" \
    "--target=${target_triple}" \
    -arch "$architecture" \
    "-miphoneos-version-min=${deployment_target}" \
    -isysroot "$sdk_path" \
    "-B${bin_dir}" \
    -x objective-c \
    -fsyntax-only "$source_path"

  printf 'Linking an SDK %s %s UIKit executable...\n' \
    "$version" "$architecture"
  "$clang_tool" \
    "--target=${target_triple}" \
    -arch "$architecture" \
    "-miphoneos-version-min=${deployment_target}" \
    -isysroot "$sdk_path" \
    "-B${bin_dir}" \
    "$source_path" \
    -framework Foundation \
    -framework UIKit \
    -o "$executable_path"

  file_output="$("$file_tool" "$executable_path")"
  [[ "$file_output" == *"Mach-O"* && "$file_output" == *"$architecture"* ]] ||
    die "SDK smoke test produced an unexpected file: ${file_output}"
  "$otool_tool" -hv "$executable_path" >/dev/null

  printf 'SDK %s compile/link test passed for %s.\n' \
    "$version" "$architecture"
  cleanup_temp_dir "$verify_dir"
  verify_dir=""
}

write_receipt() {
  local version="$1"
  local entry="$2"
  local arches="$3"
  local installed_at=""
  local clang_version=""
  local receipt_path="${receipt_dir}/${version}.json"

  installed_at="$("$date_tool" -u '+%Y-%m-%dT%H:%M:%SZ')"
  IFS= read -r clang_version < <("$clang_tool" --version)
  receipt_temp="${receipt_dir}/.${version}.json.$$"

  # shellcheck disable=SC2016
  printf '%s\n' "$entry" |
    "$jq_tool" -e \
      --arg installed_at "$installed_at" \
      --arg verified_at "$installed_at" \
      --arg compatible_arches "$arches" \
      --arg clang_version "$clang_version" \
      '{
        schema: 1,
        version: .version,
        directory: .directory,
        source_url: .url,
        archive_sha256: .sha256,
        installed_at: $installed_at,
        verified_at: $verified_at,
        verified_architectures: ($compatible_arches | split(",")),
        clang_version: $clang_version
      }' > "$receipt_temp"
  "$chmod_tool" 0644 "$receipt_temp"
  "$mv_tool" "$receipt_temp" "$receipt_path"
  receipt_temp=""
}

update_verified_at() {
  local version="$1"
  local receipt_path="${receipt_dir}/${version}.json"
  local verified_at=""

  [[ -f "$receipt_path" && ! -L "$receipt_path" ]] || {
    warn "SDK ${version} has no manager receipt; verification was not recorded"
    return 0
  }

  verified_at="$("$date_tool" -u '+%Y-%m-%dT%H:%M:%SZ')"
  receipt_temp="${receipt_dir}/.${version}.json.$$"
  # shellcheck disable=SC2016
  "$jq_tool" -e --arg verified_at "$verified_at" \
    '.verified_at = $verified_at' "$receipt_path" > "$receipt_temp"
  "$chmod_tool" 0644 "$receipt_temp"
  "$mv_tool" "$receipt_temp" "$receipt_path"
  receipt_temp=""
}

select_sdk() {
  local version="$1"
  local entry=""
  local directory=""
  local sdk_path=""
  local receipt_path=""

  entry="$(catalog_entry "$version")"
  directory="$(entry_value "$entry" '.directory')"
  sdk_path="${sdk_root}/${directory}"
  receipt_path="${receipt_dir}/${version}.json"

  [[ -f "$receipt_path" && ! -L "$receipt_path" ]] ||
    die "SDK ${version} is not managed by altivec-sdk"
  validate_sdk_directory "$version" "$sdk_path"

  if ! evaluate_entry "$entry"; then
    die "SDK ${version} is incompatible: ${incompatibility_reason}"
  fi

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
  printf 'Selected iPhoneOS SDK %s: %s -> %s\n' \
    "$version" "$current_sdk" "$directory"
}

command_list() {
  local selected_target=""
  local version=""
  local directory=""
  local sdk_arches=""
  local linker_input=""
  local download_bytes=""
  local status=""
  local selected=""
  local compatibility=""
  local reason=""
  local sdk_path=""
  local receipt_path=""

  if [[ -L "$current_sdk" ]]; then
    selected_target="$("$readlink_tool" "$current_sdk")"
  elif [[ -e "$current_sdk" ]]; then
    warn "selection path is not a symlink: ${current_sdk}"
  fi

  printf 'Device: %s (%s; dpkg %s)\n' \
    "$device_model" "$device_arch" "$dpkg_arch"
  printf 'Clang targets: %s\n' "$toolchain_targets"
  if [[ "$linker_has_tapi" -eq 1 ]]; then
    printf 'Linker: %s; TAPI framework discovery available\n' \
      "$linker_version"
  else
    printf 'Linker: %s; binary framework inputs only\n' \
      "$linker_version"
  fi
  printf '\n'
  printf '%-7s %-10s %-8s %-13s %-13s %-10s\n' \
    VERSION STATUS CURRENT SDK-TARGETS USABLE-TARGETS DOWNLOAD

  while IFS=$'\t' read -r version directory sdk_arches linker_input \
      download_bytes; do
    sdk_path="${sdk_root}/${directory}"
    receipt_path="${receipt_dir}/${version}.json"

    if [[ -d "$sdk_path" && ! -L "$sdk_path" ]]; then
      if [[ -f "$receipt_path" && ! -L "$receipt_path" ]]; then
        status="installed"
      else
        status="unmanaged"
      fi
    elif [[ -e "$sdk_path" || -L "$sdk_path" ]]; then
      status="broken"
    else
      status="available"
    fi

    if [[ "$selected_target" == "$directory" ]]; then
      selected="yes"
    else
      selected="-"
    fi

    if evaluate_compatibility "$sdk_arches" "$linker_input"; then
      compatibility="$compatible_arches"
      reason=""
    else
      compatibility="-"
      reason="$incompatibility_reason"
    fi

    printf '%-7s %-10s %-8s %-13s %-13s %-10s\n' \
      "$version" "$status" "$selected" "$sdk_arches" \
      "$compatibility" "$(format_mib "$download_bytes")"
    if [[ -n "$reason" ]]; then
      printf '  unavailable on this toolchain: %s\n' "$reason"
    fi
  done < <(
    "$jq_tool" -r '
      .sdks[] |
      [
        .version,
        .directory,
        (.architectures | join(",")),
        .linker_input,
        (.download_bytes | tostring)
      ] |
      @tsv
    ' "$catalog_path"
  )
}

command_install() {
  local version="$1"
  local entry=""
  local directory=""
  local archive=""
  local url=""
  local expected_sha=""
  local download_bytes=""
  local unpacked_bytes=""
  local sdk_path=""
  local receipt_path=""
  local download_path=""
  local digest_output=""
  local actual_sha=""
  local free_kb=""
  local required_kb=0

  require_root
  entry="$(catalog_entry "$version")"
  if ! evaluate_entry "$entry"; then
    die "SDK ${version} is incompatible: ${incompatibility_reason}"
  fi

  directory="$(entry_value "$entry" '.directory')"
  archive="$(entry_value "$entry" '.archive')"
  url="$(entry_value "$entry" '.url')"
  expected_sha="$(entry_value "$entry" '.sha256')"
  download_bytes="$(entry_value "$entry" '.download_bytes | tostring')"
  unpacked_bytes="$(entry_value "$entry" '.unpacked_bytes | tostring')"
  sdk_path="${sdk_root}/${directory}"
  receipt_path="${receipt_dir}/${version}.json"
  download_path="${download_dir}/${archive}.part"

  [[ "$url" == "${github_download_prefix}/${archive}" ]] ||
    die "catalog URL is outside the pinned GitHub release: ${url}"

  ensure_runtime_dirs
  acquire_lock "install ${version}"

  if [[ -d "$sdk_path" && ! -L "$sdk_path" ]]; then
    [[ -f "$receipt_path" && ! -L "$receipt_path" ]] ||
      die "SDK destination exists without a manager receipt: ${sdk_path}"
    validate_sdk_directory "$version" "$sdk_path"
    printf 'iPhoneOS SDK %s is already installed at %s.\n' \
      "$version" "$sdk_path"
    return 0
  fi
  [[ ! -e "$sdk_path" && ! -L "$sdk_path" ]] ||
    die "SDK destination is unsafe: ${sdk_path}"

  # shellcheck disable=SC2016
  free_kb="$(
    "$df_tool" -Pk "$sdk_root" |
      "$awk_tool" 'NR == 2 { print $4 }'
  )"
  [[ "$free_kb" =~ ^[0-9]+$ ]] ||
    die "could not determine free space for ${sdk_root}"
  required_kb=$(((download_bytes + unpacked_bytes + 1023) / 1024 + 65536))
  if ((free_kb < required_kb)); then
    die "SDK ${version} needs approximately ${required_kb} KiB free; only ${free_kb} KiB is available"
  fi

  printf 'Downloading iPhoneOS SDK %s (%s)...\n' \
    "$version" "$(format_mib "$download_bytes")"
  if ! "$curl_tool" \
      --fail \
      --location \
      --proto '=https' \
      --proto-redir '=https' \
      --retry 5 \
      --retry-delay 2 \
      --retry-all-errors \
      --connect-timeout 30 \
      --continue-at - \
      --output "$download_path" \
      "$url"; then
    die "download failed; the partial file was retained for retry: ${download_path}"
  fi

  digest_output="$("$openssl_tool" dgst -sha256 "$download_path")"
  actual_sha="${digest_output##*= }"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    "$rm_tool" -f -- "$download_path"
    die "SDK checksum mismatch: got ${actual_sha}, expected ${expected_sha}"
  fi
  printf 'Verified SHA-256 %s.\n' "$expected_sha"

  validate_archive_paths "$download_path" "$directory"
  staging_dir="$(
    "$mktemp_tool" -d "${sdk_root}/.install.${version}.XXXXXX"
  )"
  printf 'Extracting into a private staging directory...\n'
  "$tar_tool" --no-same-owner --no-same-permissions \
    -xzf "$download_path" -C "$staging_dir"
  validate_sdk_directory "$version" "${staging_dir}/${directory}"
  run_sdk_smoke_test \
    "$version" "${staging_dir}/${directory}" "$compatible_arches"

  "$mv_tool" "${staging_dir}/${directory}" "$sdk_path"
  /bin/rmdir "$staging_dir"
  staging_dir=""
  write_receipt "$version" "$entry" "$compatible_arches"
  "$rm_tool" -f -- "$download_path"

  if [[ ! -e "$current_sdk" && ! -L "$current_sdk" ]]; then
    select_sdk "$version"
  fi

  printf 'Installed iPhoneOS SDK %s at %s.\n' "$version" "$sdk_path"
}

command_remove() {
  local version="$1"
  local entry=""
  local directory=""
  local sdk_path=""
  local receipt_path="${receipt_dir}/${version}.json"

  require_root
  entry="$(catalog_entry "$version")"
  directory="$(entry_value "$entry" '.directory')"
  [[ "$directory" == "iPhoneOS${version}.sdk" ]] ||
    die "SDK ${version} has an unsafe catalog directory: ${directory}"
  sdk_path="${sdk_root}/${directory}"

  ensure_runtime_dirs
  acquire_lock "remove ${version}"

  [[ -d "$sdk_path" && ! -L "$sdk_path" ]] ||
    die "SDK ${version} is not installed"
  if [[ -L "$current_sdk" && -e "$current_sdk" &&
      "$current_sdk" -ef "$sdk_path" ]]; then
    die "cannot remove selected iPhoneOS SDK ${version}; select another version first"
  fi
  [[ -f "$receipt_path" && ! -L "$receipt_path" ]] ||
    die "SDK ${version} is not managed by altivec-sdk"

  "$rm_tool" -r -- "$sdk_path"
  "$rm_tool" -f -- "$receipt_path"
  printf 'Removed iPhoneOS SDK %s from %s.\n' "$version" "$sdk_path"
}

command_select() {
  local version="$1"

  require_root
  ensure_runtime_dirs
  acquire_lock "select ${version}"
  select_sdk "$version"
}

command_verify() {
  local version="$1"
  local entry=""
  local directory=""
  local sdk_path=""

  require_root
  entry="$(catalog_entry "$version")"
  if ! evaluate_entry "$entry"; then
    die "SDK ${version} is incompatible: ${incompatibility_reason}"
  fi
  directory="$(entry_value "$entry" '.directory')"
  sdk_path="${sdk_root}/${directory}"

  ensure_runtime_dirs
  acquire_lock "verify ${version}"
  validate_sdk_directory "$version" "$sdk_path"
  run_sdk_smoke_test "$version" "$sdk_path" "$compatible_arches"
  update_verified_at "$version"
  printf 'iPhoneOS SDK %s verification passed.\n' "$version"
}

detect_capabilities

if (($# == 0)); then
  usage >&2
  exit 2
fi

case "$1" in
  list)
    (($# == 1)) || die 'list takes no arguments'
    command_list
    ;;
  install)
    (($# == 2)) || die 'install requires exactly one SDK version'
    validate_version "$2"
    command_install "$2"
    ;;
  remove)
    (($# == 2)) || die 'remove requires exactly one SDK version'
    validate_version "$2"
    command_remove "$2"
    ;;
  select)
    (($# == 2)) || die 'select requires exactly one SDK version'
    validate_version "$2"
    command_select "$2"
    ;;
  verify)
    (($# == 2)) || die 'verify requires exactly one SDK version'
    validate_version "$2"
    command_verify "$2"
    ;;
  -h|--help|help)
    (($# == 1)) || die 'help takes no arguments'
    usage
    ;;
  *)
    usage >&2
    die "unknown command: $1"
    ;;
esac
