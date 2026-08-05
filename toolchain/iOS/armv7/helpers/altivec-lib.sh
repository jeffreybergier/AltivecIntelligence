#!/bin/bash

set -euo pipefail

readonly repository="jeffreybergier/AltivecIntelligence"
readonly install_prefix="${ALTIVEC_LIB_INSTALL_PREFIX:-/var/altivec}"
readonly library_root="${ALTIVEC_LIB_ROOT:-${install_prefix}/Libraries}"
readonly state_root="${ALTIVEC_LIB_STATE_ROOT:-/var/lib/altivec-lib}"
readonly cache_root="${ALTIVEC_LIB_CACHE_ROOT:-/var/cache/altivec-lib}"
readonly temporary_root="${ALTIVEC_LIB_TMP_ROOT:-/var/tmp}"
readonly sdk_root="${ALTIVEC_LIB_SDK_ROOT:-${install_prefix}/SDKs}"
readonly bin_dir="${install_prefix}/bin"
readonly current_link="${library_root}/Current"
readonly receipt_dir="${state_root}/receipts"
readonly download_dir="${cache_root}/downloads"
readonly lock_dir="${state_root}/install.lock"
readonly fragment_dir="${install_prefix}/share/altivec-lib"
readonly current_fragment="${fragment_dir}/current.mk"
readonly github_api_base="${ALTIVEC_LIB_GITHUB_API_BASE:-https://api.github.com/repos/${repository}/releases}"
readonly github_download_prefix="${ALTIVEC_LIB_GITHUB_DOWNLOAD_PREFIX:-https://github.com/${repository}/releases/download}"
readonly testing="${ALTIVEC_LIB_TESTING:-0}"

staging_dir=""
verify_dir=""
release_temp=""
receipt_temp=""
fragment_temp=""
selection_temp=""
lock_held=0

release_file=""
release_version=""
core_asset=""
core_url=""
core_sha256=""
core_bytes=""
cocoa_asset=""
cocoa_url=""
cocoa_sha256=""
cocoa_bytes=""

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
    '  altivec-lib install <version>' \
    '  altivec-lib update' \
    '  altivec-lib list' \
    '  altivec-lib select <version>' \
    '  altivec-lib verify <version>' \
    '' \
    'Installs the AltivecCore and AltivecCocoa iOS static-library assets' \
    'published by jeffreybergier/AltivecIntelligence on GitHub.'
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
awk_tool="$(require_tool awk)"
clang_tool="$(require_tool clang)"
file_tool="$(require_tool file)"
otool_tool="$(require_tool otool)"
lipo_tool="$(require_tool lipo)"
unzip_tool="$(require_tool unzip)"
curl_tool="$(require_tool curl)"
openssl_tool="$(require_tool openssl)"
realpath_tool="$(require_tool realpath)"
find_tool="$(require_tool find)"
df_tool="$(require_tool df)"
readonly jq_tool awk_tool clang_tool file_tool otool_tool
readonly lipo_tool unzip_tool curl_tool openssl_tool realpath_tool
readonly find_tool df_tool

readonly mkdir_tool="/bin/mkdir"
readonly mv_tool="/bin/mv"
readonly rm_tool="/bin/rm"
readonly ln_tool="/bin/ln"
readonly cp_tool="/bin/cp"
readonly chmod_tool="/bin/chmod"
readonly readlink_tool="/bin/readlink"
readonly mktemp_tool="/bin/mktemp"
readonly date_tool="/bin/date"
readonly ls_tool="/bin/ls"

for system_tool in "$mkdir_tool" "$mv_tool" "$rm_tool" "$ln_tool" \
  "$cp_tool" "$chmod_tool" "$readlink_tool" "$mktemp_tool" \
  "$date_tool" "$ls_tool"; do
  [[ -x "$system_tool" ]] ||
    die "required system command is missing: ${system_tool}"
done

[[ "$testing" == "0" || "$testing" == "1" ]] ||
  die 'ALTIVEC_LIB_TESTING must be 0 or 1'

cleanup_temp_dir() {
  local path="$1"

  [[ -n "$path" ]] || return 0
  case "$path" in
    "${library_root}"/.install.*|"${temporary_root}"/altivec-lib-verify.*)
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

  if [[ -n "$release_temp" && -f "$release_temp" &&
      ! -L "$release_temp" ]]; then
    case "$release_temp" in
      "${temporary_root}"/altivec-lib-release.*)
        "$rm_tool" -f -- "$release_temp" || cleanup_rc=1
        ;;
      *)
        warn "refusing to clean unexpected release metadata: ${release_temp}"
        cleanup_rc=1
        ;;
    esac
  fi

  if [[ -n "$receipt_temp" && -f "$receipt_temp" &&
      ! -L "$receipt_temp" ]]; then
    case "$receipt_temp" in
      "${receipt_dir}"/.*.json.*|"${library_root}"/*/.receipt.*)
        "$rm_tool" -f -- "$receipt_temp" || cleanup_rc=1
        ;;
      *)
        warn "refusing to clean unexpected receipt path: ${receipt_temp}"
        cleanup_rc=1
        ;;
    esac
  fi

  if [[ -n "$fragment_temp" && -f "$fragment_temp" &&
      ! -L "$fragment_temp" ]]; then
    case "$fragment_temp" in
      "${fragment_dir}"/.current.mk.*)
        "$rm_tool" -f -- "$fragment_temp" || cleanup_rc=1
        ;;
      *)
        warn "refusing to clean unexpected Make fragment: ${fragment_temp}"
        cleanup_rc=1
        ;;
    esac
  fi

  if [[ -n "$selection_temp" && -L "$selection_temp" ]]; then
    case "$selection_temp" in
      "${library_root}"/.Current.*)
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
  [[ "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]] ||
    die "invalid library version: ${version}"
}

version_is_newer() {
  local candidate="$1"
  local installed="$2"
  local candidate_major=""
  local candidate_minor=""
  local candidate_patch=""
  local installed_major=""
  local installed_minor=""
  local installed_patch=""

  IFS=. read -r candidate_major candidate_minor candidate_patch <<< "$candidate"
  IFS=. read -r installed_major installed_minor installed_patch <<< "$installed"

  if ((10#$candidate_major != 10#$installed_major)); then
    ((10#$candidate_major > 10#$installed_major))
    return
  fi
  if ((10#$candidate_minor != 10#$installed_minor)); then
    ((10#$candidate_minor > 10#$installed_minor))
    return
  fi
  ((10#$candidate_patch > 10#$installed_patch))
}

ensure_runtime_dirs() {
  "$mkdir_tool" -p "$library_root" "$receipt_dir" "$download_dir" \
    "$fragment_dir"
  "$chmod_tool" 0755 "$library_root" "$state_root" "$receipt_dir" \
    "$fragment_dir"
  "$chmod_tool" 0700 "$cache_root" "$download_dir"
}

acquire_lock() {
  if ! "$mkdir_tool" "$lock_dir" 2>/dev/null; then
    die "another library operation holds the lock: ${lock_dir}"
  fi
  lock_held=1
  printf '%s\n' "$$" > "${lock_dir}/owner"
  printf '%s\n' "${1:-unknown}" > "${lock_dir}/command"
}

fetch_release() {
  local endpoint="$1"
  local url="${github_api_base}/${endpoint}"
  local curl_args=(
    --fail
    --silent
    --show-error
    --location
    --retry 5
    --retry-delay 2
    --retry-all-errors
    --connect-timeout 30
    --header 'Accept: application/vnd.github+json'
    --header 'X-GitHub-Api-Version: 2022-11-28'
    --header 'User-Agent: altivec-lib'
  )

  if [[ "$testing" != "1" ]]; then
    curl_args+=(--proto '=https' --proto-redir '=https')
  fi

  release_temp="$($mktemp_tool "${temporary_root}/altivec-lib-release.XXXXXX")"
  printf 'Fetching AltivecIntelligence release information...\n'
  "$curl_tool" "${curl_args[@]}" --output "$release_temp" "$url" ||
    die "could not fetch GitHub release information: ${url}"

  "$jq_tool" -e '
    type == "object" and
    (.tag_name | type == "string") and
    .draft == false and
    .prerelease == false and
    (.assets | type == "array")
  ' "$release_temp" >/dev/null ||
    die 'GitHub returned invalid or unsupported release metadata'
  release_file="$release_temp"
}

load_release_assets() {
  local expected_version="$1"
  local tag_name=""
  local asset_line=""
  local expected_url=""

  tag_name="$($jq_tool -er '.tag_name' "$release_file")"
  [[ "$tag_name" == v* ]] ||
    die "release tag does not start with v: ${tag_name}"
  release_version="${tag_name#v}"
  validate_version "$release_version"
  [[ "$release_version" == "$expected_version" ]] ||
    die "GitHub returned ${tag_name}, expected v${expected_version}"

  core_asset="AltivecCore-${release_version}-iOS-static.zip"
  # shellcheck disable=SC2016
  asset_line="$($jq_tool -er --arg name "$core_asset" '
    [.assets[] | select(.name == $name)] |
    if length != 1 then error("expected exactly one matching asset")
    else .[0] end |
    select(.state == "uploaded") |
    select(.browser_download_url | type == "string") |
    select(.digest | type == "string" and
      test("^sha256:[0-9a-f]{64}$")) |
    select(.size | type == "number" and . > 0) |
    [.browser_download_url, (.digest | sub("^sha256:"; "")),
      (.size | tostring)] | @tsv
  ' "$release_file")" ||
    die "release v${release_version} has no valid ${core_asset} asset"
  IFS=$'\t' read -r core_url core_sha256 core_bytes <<< "$asset_line"
  [[ "$core_bytes" =~ ^[0-9]+$ ]] ||
    die "release has an invalid AltivecCore asset size: ${core_bytes}"
  expected_url="${github_download_prefix}/v${release_version}/${core_asset}"
  [[ "$core_url" == "$expected_url" ]] ||
    die "unexpected AltivecCore download URL: ${core_url}"

  cocoa_asset="AltivecCocoa-${release_version}-iOS-static.zip"
  # shellcheck disable=SC2016
  asset_line="$($jq_tool -er --arg name "$cocoa_asset" '
    [.assets[] | select(.name == $name)] |
    if length != 1 then error("expected exactly one matching asset")
    else .[0] end |
    select(.state == "uploaded") |
    select(.browser_download_url | type == "string") |
    select(.digest | type == "string" and
      test("^sha256:[0-9a-f]{64}$")) |
    select(.size | type == "number" and . > 0) |
    [.browser_download_url, (.digest | sub("^sha256:"; "")),
      (.size | tostring)] | @tsv
  ' "$release_file")" ||
    die "release v${release_version} has no valid ${cocoa_asset} asset"
  IFS=$'\t' read -r cocoa_url cocoa_sha256 cocoa_bytes <<< "$asset_line"
  [[ "$cocoa_bytes" =~ ^[0-9]+$ ]] ||
    die "release has an invalid AltivecCocoa asset size: ${cocoa_bytes}"
  expected_url="${github_download_prefix}/v${release_version}/${cocoa_asset}"
  [[ "$cocoa_url" == "$expected_url" ]] ||
    die "unexpected AltivecCocoa download URL: ${cocoa_url}"
}

prepare_release() {
  local version="$1"
  local endpoint="$2"

  fetch_release "$endpoint"
  load_release_assets "$version"
}

format_mib() {
  local bytes="$1"
  "$awk_tool" -v bytes="$bytes" \
    'BEGIN { printf "%.1f MiB", bytes / 1048576 }'
}

file_size_bytes() {
  local path="$1"
  local bytes=""

  # shellcheck disable=SC2016
  bytes="$("$ls_tool" -ln "$path" |
    "$awk_tool" 'NR == 1 { print $5 }')" || return 1
  [[ "$bytes" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$bytes"
}

check_free_space() {
  local total_download_bytes=$((core_bytes + cocoa_bytes))
  local required_kb=$(((total_download_bytes * 4 + 16777215) / 1024))
  local free_kb=""

  # shellcheck disable=SC2016
  free_kb="$($df_tool -Pk "$library_root" |
    "$awk_tool" 'NR == 2 { print $4 }')"
  [[ "$free_kb" =~ ^[0-9]+$ ]] ||
    die "could not determine free space for ${library_root}"
  if ((free_kb < required_kb)); then
    die "library installation needs approximately ${required_kb} KiB free; only ${free_kb} KiB is available"
  fi
}

download_asset() {
  local label="$1"
  local asset="$2"
  local url="$3"
  local expected_sha="$4"
  local expected_bytes="$5"
  local download_path="${download_dir}/${asset}.part"
  local digest_output=""
  local actual_sha=""
  local actual_bytes=""
  local curl_args=(
    --fail
    --location
    --retry 5
    --retry-delay 2
    --retry-all-errors
    --connect-timeout 30
    --continue-at -
  )

  if [[ "$testing" != "1" ]]; then
    curl_args+=(--proto '=https' --proto-redir '=https')
  fi

  if [[ -e "$download_path" || -L "$download_path" ]]; then
    [[ -f "$download_path" && ! -L "$download_path" ]] ||
      die "cached download path is unsafe: ${download_path}"
    actual_bytes="$(file_size_bytes "$download_path")" ||
      die "could not determine cached download size: ${download_path}"
    if [[ "$actual_bytes" == "$expected_bytes" ]]; then
      digest_output="$($openssl_tool dgst -sha256 "$download_path")"
      actual_sha="${digest_output##*= }"
      if [[ "$actual_sha" == "$expected_sha" ]]; then
        printf 'Using cached %s %s; SHA-256 %s is valid.\n' \
          "$label" "$release_version" "$expected_sha"
        return 0
      fi
      "$rm_tool" -f -- "$download_path"
    elif [[ "$actual_bytes" =~ ^[0-9]+$ ]] &&
        ((actual_bytes > expected_bytes)); then
      "$rm_tool" -f -- "$download_path"
    fi
  fi

  printf 'Downloading %s %s (%s)...\n' \
    "$label" "$release_version" "$(format_mib "$expected_bytes")"
  "$curl_tool" "${curl_args[@]}" --output "$download_path" "$url" ||
    die "download failed; the partial file was retained for retry: ${download_path}"

  actual_bytes="$(file_size_bytes "$download_path")" ||
    die "could not determine download size: ${download_path}"
  [[ "$actual_bytes" == "$expected_bytes" ]] || {
    "$rm_tool" -f -- "$download_path"
    die "${label} download size is ${actual_bytes}, expected ${expected_bytes}"
  }

  digest_output="$($openssl_tool dgst -sha256 "$download_path")"
  actual_sha="${digest_output##*= }"
  [[ "$actual_sha" == "$expected_sha" ]] || {
    "$rm_tool" -f -- "$download_path"
    die "${label} checksum mismatch: got ${actual_sha}, expected ${expected_sha}"
  }
  printf 'Verified %s SHA-256 %s.\n' "$label" "$expected_sha"
}

validate_archive_paths() {
  local archive_path="$1"
  local expected_directory="$2"
  local member=""
  local normalized=""
  local member_count=0

  "$unzip_tool" -tqq "$archive_path" >/dev/null ||
    die "downloaded asset is not a valid ZIP archive: ${archive_path}"

  while IFS= read -r member; do
    [[ -n "$member" ]] || continue
    case "$member" in
      /*|*\\*)
        die "library archive contains an unsafe path: ${member}"
        ;;
    esac

    normalized="${member#./}"
    normalized="${normalized%/}"
    [[ -n "$normalized" ]] ||
      die "library archive contains an unsafe path: ${member}"
    case "$normalized" in
      *'//'*)
        die "library archive contains an unsafe path: ${member}"
        ;;
    esac
    case "/${normalized}/" in
      *'/../'*|*'/./'*)
        die "library archive contains an unsafe path: ${member}"
        ;;
    esac
    case "$normalized" in
      "$expected_directory"|"$expected_directory"/*)
        ;;
      *)
        die "library archive has an unexpected top-level path: ${member}"
        ;;
    esac
    member_count=$((member_count + 1))
  done < <("$unzip_tool" -Z1 "$archive_path")

  [[ "$member_count" -gt 0 ]] || die 'library archive is empty'
}

validate_extracted_tree() {
  local root="$1"
  local unexpected=""

  unexpected="$($find_tool "$root" -type l -print -quit)"
  [[ -z "$unexpected" ]] ||
    die "library archive contains a symbolic link: ${unexpected}"
  unexpected="$($find_tool "$root" ! -type d ! -type f -print -quit)"
  [[ -z "$unexpected" ]] ||
    die "library archive contains a special file: ${unexpected}"
}

validate_bundle_tree() {
  local bundle_dir="$1"
  local resource=""
  local relative=""

  for resource in Info.plist PkgInfo _CodeSignature embedded.mobileprovision; do
    [[ ! -e "${bundle_dir}/${resource}" &&
      ! -L "${bundle_dir}/${resource}" ]] ||
      die "managed resources use reserved app path: ${resource}"
  done

  while IFS= read -r resource; do
    relative="${resource#"${bundle_dir}"/}"
    [[ "$relative" =~ ^[A-Za-z0-9._/@+-]+$ ]] ||
      die "managed resource path is unsupported by Make: ${relative}"
  done < <("$find_tool" "$bundle_dir" -type f -print)
}

validate_library_set() {
  local version="$1"
  local version_root="$2"
  local cocoa_resource_root="${version_root}/AltivecCocoa/Resources"
  local framework_path=""
  local lipo_output=""
  local required_directory=""
  local required_file=""
  local resource=""
  local relative_resource=""

  [[ -d "$version_root" && ! -L "$version_root" ]] ||
    die "library version is not a real directory: ${version_root}"

  # Keep this to the package entry points consumed by altivec-lib. Importing
  # the umbrella headers below verifies their changing internal header trees.
  for required_directory in \
    AltivecCore/include/AltivecCore \
    AltivecCocoa/include/AltivecCocoa \
    Bundle; do
    [[ -d "${version_root}/${required_directory}" &&
      ! -L "${version_root}/${required_directory}" ]] ||
      die "Altivec libraries ${version} are missing directory ${required_directory}"
  done

  for required_file in \
    AltivecCore/include/AltivecCore/AltivecCore.h \
    AltivecCore/lib/libAltivecCore.a \
    AltivecCore/lib/cacert.pem \
    AltivecCocoa/include/AltivecCocoa/AltivecCocoa.h \
    AltivecCocoa/lib/libAltivecCocoa.a \
    Bundle/cacert.pem; do
    [[ -f "${version_root}/${required_file}" &&
      ! -L "${version_root}/${required_file}" ]] ||
      die "Altivec libraries ${version} are missing ${required_file}"
  done

  framework_path="$($find_tool "$version_root" -type d \
    -name '*.framework' -print -quit)"
  [[ -z "$framework_path" ]] ||
    die "iOS static package unexpectedly contains a framework: ${framework_path}"

  validate_extracted_tree "$version_root"
  validate_bundle_tree "${version_root}/Bundle"

  if [[ -e "$cocoa_resource_root" || -L "$cocoa_resource_root" ]]; then
    [[ -d "$cocoa_resource_root" && ! -L "$cocoa_resource_root" ]] ||
      die 'AltivecCocoa Resources is not a real directory'
    while IFS= read -r resource; do
      [[ "${resource##*/}" != '.stamp' ]] || continue
      relative_resource="${resource#"${cocoa_resource_root}"/}"
      [[ -f "${version_root}/Bundle/${relative_resource}" &&
        ! -L "${version_root}/Bundle/${relative_resource}" ]] ||
        die "managed AltivecCocoa resource is missing: ${relative_resource}"
    done < <("$find_tool" "$cocoa_resource_root" -type f -print)
  fi

  for required_file in \
    "${version_root}/AltivecCore/lib/libAltivecCore.a" \
    "${version_root}/AltivecCocoa/lib/libAltivecCocoa.a"; do
    lipo_output="$($lipo_tool -info "$required_file" 2>&1)" ||
      die "could not inspect static archive: ${required_file}"
    [[ "$lipo_output" == *armv7* || "$lipo_output" == *arm_v7* ]] ||
      die "static archive has no armv7 slice: ${required_file}"
  done
}

run_library_smoke_test() {
  local version="$1"
  local version_root="$2"
  local selected_sdk="${sdk_root}/Current.sdk"
  local resolved_sdk=""
  local source_path=""
  local executable_path=""
  local file_output=""

  [[ -d "$selected_sdk" ]] ||
    die "no selected iPhoneOS SDK at ${selected_sdk}; install and select an SDK first"
  resolved_sdk="$($realpath_tool "$selected_sdk")"
  [[ -f "${resolved_sdk}/System/Library/Frameworks/UIKit.framework/Headers/UIKit.h" ]] ||
    die "selected SDK is missing UIKit headers: ${resolved_sdk}"

  verify_dir="$($mktemp_tool -d \
    "${temporary_root}/altivec-lib-verify.${version}.XXXXXX")"
  source_path="${verify_dir}/main.m"
  executable_path="${verify_dir}/altivec-lib-smoke"

  printf '%s\n' \
    '#import <AltivecCore/AltivecCore.h>' \
    '#import <AltivecCocoa/AltivecCocoa.h>' \
    'int main(void) {' \
    '  return 0;' \
    '}' > "$source_path"

  printf 'Compiling and linking Altivec libraries %s for armv7...\n' "$version"
  "$clang_tool" \
    --target=armv7-apple-ios4.3 \
    -arch armv7 \
    -miphoneos-version-min=4.3 \
    -isysroot "$resolved_sdk" \
    "-B${bin_dir}" \
    "-I${version_root}/AltivecCore/include" \
    "-I${version_root}/AltivecCocoa/include" \
    "$source_path" \
    -Wl,-ObjC \
    "${version_root}/AltivecCocoa/lib/libAltivecCocoa.a" \
    "${version_root}/AltivecCore/lib/libAltivecCore.a" \
    -framework Foundation \
    -framework UIKit \
    -framework CoreGraphics \
    -framework CoreText \
    -o "$executable_path"

  file_output="$($file_tool "$executable_path")"
  [[ "$file_output" == *Mach-O* &&
    ( "$file_output" == *armv7* || "$file_output" == *arm_v7* ) ]] ||
    die "library smoke test produced an unexpected file: ${file_output}"
  "$otool_tool" -hv "$executable_path" >/dev/null

  cleanup_temp_dir "$verify_dir"
  verify_dir=""
}

write_receipt_file() {
  local version="$1"
  local destination="$2"
  local installed_at="$3"

  # shellcheck disable=SC2016
  "$jq_tool" -n \
    --arg repository "$repository" \
    --arg version "$version" \
    --arg tag "v${version}" \
    --arg installed_at "$installed_at" \
    --arg verified_at "$installed_at" \
    --arg core_asset "$core_asset" \
    --arg core_url "$core_url" \
    --arg core_sha256 "$core_sha256" \
    --argjson core_bytes "$core_bytes" \
    --arg cocoa_asset "$cocoa_asset" \
    --arg cocoa_url "$cocoa_url" \
    --arg cocoa_sha256 "$cocoa_sha256" \
    --argjson cocoa_bytes "$cocoa_bytes" \
    '{
      schema: 1,
      repository: $repository,
      version: $version,
      tag: $tag,
      installed_at: $installed_at,
      verified_at: $verified_at,
      verified_architectures: ["armv7"],
      assets: {
        AltivecCore: {
          name: $core_asset,
          url: $core_url,
          sha256: $core_sha256,
          bytes: $core_bytes
        },
        AltivecCocoa: {
          name: $cocoa_asset,
          url: $cocoa_url,
          sha256: $cocoa_sha256,
          bytes: $cocoa_bytes
        }
      }
    }' > "$destination"
  "$chmod_tool" 0644 "$destination"
}

validate_receipt() {
  local version="$1"
  local receipt_path="$2"

  [[ -f "$receipt_path" && ! -L "$receipt_path" ]] ||
    die "library version ${version} is not managed by altivec-lib"
  # shellcheck disable=SC2016
  "$jq_tool" -e --arg repository "$repository" --arg version "$version" '
    .schema == 1 and
    .repository == $repository and
    .version == $version and
    .tag == ("v" + $version) and
    (.verified_architectures | index("armv7") != null) and
    (.assets.AltivecCore.sha256 |
      type == "string" and test("^[0-9a-f]{64}$")) and
    (.assets.AltivecCocoa.sha256 |
      type == "string" and test("^[0-9a-f]{64}$"))
  ' "$receipt_path" >/dev/null ||
    die "library version ${version} has an invalid manager receipt"
}

copy_external_receipt() {
  local version="$1"
  local source="${library_root}/${version}/.altivec-lib-receipt.json"
  local destination="${receipt_dir}/${version}.json"

  receipt_temp="${receipt_dir}/.${version}.json.$$"
  "$cp_tool" -f "$source" "$receipt_temp"
  "$chmod_tool" 0644 "$receipt_temp"
  "$mv_tool" "$receipt_temp" "$destination"
  receipt_temp=""
}

update_verified_at() {
  local version="$1"
  local receipt_path="${library_root}/${version}/.altivec-lib-receipt.json"
  local verified_at=""

  verified_at="$($date_tool -u '+%Y-%m-%dT%H:%M:%SZ')"
  receipt_temp="${library_root}/${version}/.receipt.$$"
  # shellcheck disable=SC2016
  "$jq_tool" -e --arg verified_at "$verified_at" \
    '.verified_at = $verified_at' "$receipt_path" > "$receipt_temp"
  "$chmod_tool" 0644 "$receipt_temp"
  "$mv_tool" "$receipt_temp" "$receipt_path"
  receipt_temp=""
  copy_external_receipt "$version"
}

write_make_fragment() {
  local version="$1"
  local version_root="${library_root}/${version}"
  local resource=""
  local resource_files=""

  while IFS= read -r resource; do
    resource_files="${resource_files} ${resource}"
  done < <("$find_tool" "${version_root}/Bundle" -type f -print)

  fragment_temp="${fragment_dir}/.current.mk.$$"
  {
    printf '%s\n' \
      '# Generated by altivec-lib. Do not edit.' \
      "ALTIVEC_MANAGED_VERSION := ${version}" \
      "ALTIVEC_MANAGED_ROOT := ${version_root}" \
      "ALTIVEC_MANAGED_INCLUDE_DIRS := ${version_root}/AltivecCore/include ${version_root}/AltivecCocoa/include" \
      "ALTIVEC_MANAGED_ARCHIVES := ${version_root}/AltivecCocoa/lib/libAltivecCocoa.a ${version_root}/AltivecCore/lib/libAltivecCore.a" \
      'ALTIVEC_MANAGED_FRAMEWORKS := CoreText' \
      "ALTIVEC_MANAGED_BUNDLE_DIR := ${version_root}/Bundle" \
      "ALTIVEC_MANAGED_RESOURCE_FILES :=${resource_files}"
  } > "$fragment_temp"
  "$chmod_tool" 0644 "$fragment_temp"
}

select_library_set() {
  local version="$1"
  local version_root="${library_root}/${version}"
  local receipt_path="${version_root}/.altivec-lib-receipt.json"

  validate_receipt "$version" "$receipt_path"
  validate_library_set "$version" "$version_root"

  if [[ -e "$current_link" && ! -L "$current_link" ]]; then
    die "selection path exists and is not a symlink: ${current_link}"
  fi

  write_make_fragment "$version"
  selection_temp="${library_root}/.Current.$$"
  "$ln_tool" -s "$version" "$selection_temp"
  if [[ -L "$current_link" ]]; then
    "$rm_tool" -f -- "$current_link"
  fi
  "$mv_tool" "$selection_temp" "$current_link"
  selection_temp=""
  "$mv_tool" "$fragment_temp" "$current_fragment"
  fragment_temp=""

  printf 'Selected Altivec libraries %s: %s -> %s\n' \
    "$version" "$current_link" "$version"
}

current_version() {
  local selected=""

  if [[ -L "$current_link" ]]; then
    selected="$($readlink_tool "$current_link")"
    if [[ "$selected" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ &&
        -d "${library_root}/${selected}" &&
        ! -L "${library_root}/${selected}" ]]; then
      printf '%s\n' "$selected"
      return 0
    fi
    warn "selection is invalid or broken: ${current_link} -> ${selected}"
  elif [[ -e "$current_link" ]]; then
    warn "selection path is not a symlink: ${current_link}"
  fi
  return 1
}

install_prepared_release() {
  local version="$1"
  local final_root="${library_root}/${version}"
  local internal_receipt="${final_root}/.altivec-lib-receipt.json"
  local core_download="${download_dir}/${core_asset}.part"
  local cocoa_download="${download_dir}/${cocoa_asset}.part"
  local core_extract=""
  local cocoa_extract=""
  local payload_root=""
  local installed_at=""
  local stamp_file=""

  if [[ -d "$final_root" && ! -L "$final_root" ]]; then
    validate_receipt "$version" "$internal_receipt"
    validate_library_set "$version" "$final_root"
    if [[ ! -f "${receipt_dir}/${version}.json" ]]; then
      copy_external_receipt "$version"
    fi
    printf 'Altivec libraries %s are already installed at %s.\n' \
      "$version" "$final_root"
    return 0
  fi
  [[ ! -e "$final_root" && ! -L "$final_root" ]] ||
    die "library destination is unsafe: ${final_root}"

  check_free_space
  download_asset AltivecCore "$core_asset" "$core_url" \
    "$core_sha256" "$core_bytes"
  download_asset AltivecCocoa "$cocoa_asset" "$cocoa_url" \
    "$cocoa_sha256" "$cocoa_bytes"
  validate_archive_paths "$core_download" 'AltivecCore-iOS-static'
  validate_archive_paths "$cocoa_download" 'AltivecCocoa-iOS-static'

  staging_dir="$($mktemp_tool -d \
    "${library_root}/.install.${version}.XXXXXX")"
  core_extract="${staging_dir}/core-extract"
  cocoa_extract="${staging_dir}/cocoa-extract"
  payload_root="${staging_dir}/${version}"
  "$mkdir_tool" -p "$core_extract" "$cocoa_extract" "$payload_root/Bundle"

  printf 'Extracting Altivec libraries into a private staging directory...\n'
  "$unzip_tool" -q "$core_download" -d "$core_extract"
  "$unzip_tool" -q "$cocoa_download" -d "$cocoa_extract"
  validate_extracted_tree "$core_extract"
  validate_extracted_tree "$cocoa_extract"

  "$mv_tool" "${core_extract}/AltivecCore-iOS-static" \
    "${payload_root}/AltivecCore"
  "$mv_tool" "${cocoa_extract}/AltivecCocoa-iOS-static" \
    "${payload_root}/AltivecCocoa"
  /bin/rmdir "$core_extract" "$cocoa_extract"

  "$cp_tool" -f "${payload_root}/AltivecCore/lib/cacert.pem" \
    "${payload_root}/Bundle/cacert.pem"
  if [[ -d "${payload_root}/AltivecCocoa/Resources" &&
      ! -L "${payload_root}/AltivecCocoa/Resources" ]]; then
    "$cp_tool" -R "${payload_root}/AltivecCocoa/Resources/." \
      "${payload_root}/Bundle/"
  elif [[ -e "${payload_root}/AltivecCocoa/Resources" ||
      -L "${payload_root}/AltivecCocoa/Resources" ]]; then
    die 'AltivecCocoa Resources is not a real directory'
  fi
  while IFS= read -r stamp_file; do
    "$rm_tool" -f -- "$stamp_file"
  done < <("$find_tool" "${payload_root}/Bundle" -type f \
    -name '.stamp' -print)

  validate_library_set "$version" "$payload_root"
  run_library_smoke_test "$version" "$payload_root"

  installed_at="$($date_tool -u '+%Y-%m-%dT%H:%M:%SZ')"
  write_receipt_file "$version" \
    "${payload_root}/.altivec-lib-receipt.json" "$installed_at"

  "$mv_tool" "$payload_root" "$final_root"
  /bin/rmdir "$staging_dir"
  staging_dir=""
  copy_external_receipt "$version"
  "$rm_tool" -f -- "$core_download" "$cocoa_download"

  printf 'Installed Altivec libraries %s at %s.\n' "$version" "$final_root"
}

command_list() {
  local selected=""
  local version_path=""
  local version=""
  local status=""
  local current=""
  local versions_temp=""

  selected="$(current_version 2>/dev/null || true)"
  versions_temp="$($mktemp_tool \
    "${temporary_root}/altivec-lib-release.XXXXXX")"
  release_temp="$versions_temp"

  if [[ -d "$library_root" ]]; then
    for version_path in "$library_root"/*; do
      [[ -d "$version_path" && ! -L "$version_path" ]] || continue
      version="${version_path##*/}"
      [[ "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]] || continue
      printf '%s\n' "$version" >> "$versions_temp"
    done
  fi

  printf '%-12s %-12s %-8s\n' VERSION STATUS CURRENT
  if [[ -s "$versions_temp" ]]; then
    while IFS= read -r version; do
      version_path="${library_root}/${version}"
      if [[ -f "${version_path}/.altivec-lib-receipt.json" ]]; then
        status="installed"
      else
        status="unmanaged"
      fi
      if [[ "$version" == "$selected" ]]; then
        current="yes"
      else
        current="-"
      fi
      printf '%-12s %-12s %-8s\n' "$version" "$status" "$current"
    done < "$versions_temp"
  fi
}

command_install() {
  local version="$1"
  local selected=""
  local final_root="${library_root}/${version}"

  require_root
  ensure_runtime_dirs
  acquire_lock "install ${version}"

  if [[ -d "$final_root" && ! -L "$final_root" ]]; then
    validate_receipt "$version" \
      "${final_root}/.altivec-lib-receipt.json"
    validate_library_set "$version" "$final_root"
    if [[ ! -f "${receipt_dir}/${version}.json" ||
        -L "${receipt_dir}/${version}.json" ]]; then
      copy_external_receipt "$version"
    fi
    selected="$(current_version 2>/dev/null || true)"
    if [[ -z "$selected" ||
        ( "$selected" == "$version" && ! -f "$current_fragment" ) ]]; then
      select_library_set "$version"
    fi
    printf 'Altivec libraries %s are already installed at %s.\n' \
      "$version" "$final_root"
    return 0
  fi

  prepare_release "$version" "tags/v${version}"
  install_prepared_release "$version"
  selected="$(current_version 2>/dev/null || true)"
  if [[ -z "$selected" ]]; then
    select_library_set "$version"
  fi
}

command_update() {
  local selected=""
  local latest=""

  require_root
  ensure_runtime_dirs
  acquire_lock update
  fetch_release latest
  latest="$($jq_tool -er '.tag_name | select(startswith("v")) | ltrimstr("v")' \
    "$release_file")" || die 'latest release has an invalid tag'
  validate_version "$latest"
  load_release_assets "$latest"

  selected="$(current_version 2>/dev/null || true)"
  if [[ -n "$selected" ]] && ! version_is_newer "$latest" "$selected"; then
    if [[ "$latest" == "$selected" ]]; then
      printf 'Altivec libraries %s are already current.\n' "$selected"
    else
      printf 'Selected Altivec libraries %s are newer than GitHub release %s; no update performed.\n' \
        "$selected" "$latest"
    fi
    return 0
  fi

  install_prepared_release "$latest"
  select_library_set "$latest"
  printf 'Updated Altivec libraries to %s.\n' "$latest"
}

command_select() {
  local version="$1"

  require_root
  ensure_runtime_dirs
  acquire_lock "select ${version}"
  select_library_set "$version"
}

command_verify() {
  local version="$1"
  local version_root="${library_root}/${version}"

  require_root
  ensure_runtime_dirs
  acquire_lock "verify ${version}"
  validate_receipt "$version" \
    "${version_root}/.altivec-lib-receipt.json"
  validate_library_set "$version" "$version_root"
  run_library_smoke_test "$version" "$version_root"
  update_verified_at "$version"
  printf 'Altivec libraries %s verification passed.\n' "$version"
}

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
    (($# == 2)) || die 'install requires exactly one library version'
    validate_version "$2"
    command_install "$2"
    ;;
  update)
    (($# == 1)) || die 'update takes no arguments'
    command_update
    ;;
  select)
    (($# == 2)) || die 'select requires exactly one library version'
    validate_version "$2"
    command_select "$2"
    ;;
  verify)
    (($# == 2)) || die 'verify requires exactly one library version'
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
