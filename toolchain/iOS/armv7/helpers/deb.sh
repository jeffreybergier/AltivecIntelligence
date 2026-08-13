#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

required_environment=(
  AT_PROJECT_ROOT
  AT_INTERMEDIATES_DIR
  AT_STAGE_DIR
  AT_EXTRACT_DIR
  AT_LLVM_ARCHIVE
  AT_LLVM_PACKAGE_NAME
  AT_LLVM_VERSION
  AT_CORE_ARCHIVE
  AT_CORE_PACKAGE_NAME
  AT_INSTALL_PREFIX
  AT_PROFILE_SCRIPT
  AT_PROFILE_REL
  AT_SDK_MANAGER_SCRIPT
  AT_SDK_CATALOG
  AT_LIB_MANAGER_SCRIPT
  AT_IOS_APP_MAKEFILE
  AT_IOS_APP_TEMPLATE_DIR
  AT_IOS_APP_TOOL
  AT_OUTPUT
  AT_PACKAGE_ID
  AT_DISPLAY_NAME
  AT_VERSION
  AT_ARCH
  AT_SECTION
  AT_PRIORITY
  AT_MAINTAINER
  AT_DESCRIPTION
  AT_DEPENDS
  AT_CONFLICTS
  AT_REPLACES
  AT_COMPRESSION
  AT_FAKEROOT
  AT_DPKG_DEB
)

for variable_name in "${required_environment[@]}"; do
  [[ -n "${!variable_name:-}" ]] ||
    die "required environment variable is empty: ${variable_name}"
done

resolve_tool() {
  local requested="$1"
  local resolved=""

  if [[ "$requested" == */* ]]; then
    [[ -x "$requested" ]] || return 1
    realpath "$requested"
    return
  fi

  resolved="$(command -v "$requested" 2>/dev/null)" || return 1
  printf '%s\n' "$resolved"
}

for required_tool in awk chmod cp dirname du find grep install readlink \
  realpath rm sha256sum sort strings tar xargs; do
  command -v "$required_tool" >/dev/null 2>&1 ||
    die "required packaging tool not found: ${required_tool}"
done

fakeroot_tool="$(resolve_tool "$AT_FAKEROOT")" ||
  die "fakeroot not found: ${AT_FAKEROOT}"
dpkg_deb_tool="$(resolve_tool "$AT_DPKG_DEB")" ||
  die "dpkg-deb not found: ${AT_DPKG_DEB}"
readonly fakeroot_tool dpkg_deb_tool

project_root="$(realpath -m "$AT_PROJECT_ROOT")"
intermediates_dir="$(realpath -m "$AT_INTERMEDIATES_DIR")"
stage_dir="$(realpath -m "$AT_STAGE_DIR")"
extract_dir="$(realpath -m "$AT_EXTRACT_DIR")"
llvm_archive="$(realpath -m "$AT_LLVM_ARCHIVE")"
core_archive="$(realpath -m "$AT_CORE_ARCHIVE")"
profile_script="$(realpath -m "$AT_PROFILE_SCRIPT")"
sdk_manager_script="$(realpath -m "$AT_SDK_MANAGER_SCRIPT")"
sdk_catalog="$(realpath -m "$AT_SDK_CATALOG")"
lib_manager_script="$(realpath -m "$AT_LIB_MANAGER_SCRIPT")"
ios_app_makefile="$(realpath -m "$AT_IOS_APP_MAKEFILE")"
ios_app_template_dir="$(realpath -m "$AT_IOS_APP_TEMPLATE_DIR")"
ios_app_tool="$(realpath -m "$AT_IOS_APP_TOOL")"
output_path="$(realpath -m "$AT_OUTPUT")"
readonly project_root intermediates_dir stage_dir extract_dir
readonly llvm_archive core_archive profile_script sdk_manager_script
readonly sdk_catalog lib_manager_script ios_app_makefile ios_app_template_dir
readonly ios_app_tool
readonly output_path

[[ -d "$project_root" ]] || die "project root not found: ${project_root}"
[[ -d "$intermediates_dir" ]] ||
  die "intermediates directory not found: ${intermediates_dir}"
[[ -f "$llvm_archive" ]] || die "cached LLVM archive not found: ${llvm_archive}"
[[ -f "$core_archive" ]] ||
  die "cached core-tools archive not found: ${core_archive}"
[[ -f "$profile_script" ]] || die "profile script not found: ${profile_script}"
[[ -f "$sdk_manager_script" ]] ||
  die "SDK manager script not found: ${sdk_manager_script}"
[[ -f "$sdk_catalog" ]] || die "SDK catalog not found: ${sdk_catalog}"
[[ -f "$lib_manager_script" ]] ||
  die "library manager script not found: ${lib_manager_script}"
[[ -f "$ios_app_makefile" ]] ||
  die "common iOS app Makefile not found: ${ios_app_makefile}"
[[ -d "$ios_app_template_dir" && ! -L "$ios_app_template_dir" ]] ||
  die "iOS app project template not found: ${ios_app_template_dir}"
[[ -f "$ios_app_tool" && -x "$ios_app_tool" ]] ||
  die "iOS app initializer not found: ${ios_app_tool}"

case "${stage_dir}/" in
  "${intermediates_dir}/"*) ;;
  *) die "Debian stage must be inside Intermediates: ${stage_dir}" ;;
esac
case "${extract_dir}/" in
  "${intermediates_dir}/"*) ;;
  *) die "extraction directory must be inside Intermediates: ${extract_dir}" ;;
esac
case "${output_path}/" in
  "${project_root}/build-release/"*) ;;
  *) die "Debian output must be directly under build-release: ${output_path}" ;;
esac

readonly canonical_install_prefix="/var/altivec"
[[ "$AT_INSTALL_PREFIX" == "$canonical_install_prefix" ]] ||
  die "Debian payload prefix must be ${canonical_install_prefix}: ${AT_INSTALL_PREFIX}"

case "/${AT_PROFILE_REL#/}/" in
  */../*|*/./*) die "unsafe profile path: ${AT_PROFILE_REL}" ;;
esac

install_rel="${AT_INSTALL_PREFIX#/}"
profile_rel="${AT_PROFILE_REL#/}"
readonly install_rel profile_rel

rm -rf -- "$stage_dir" "$extract_dir"
mkdir -p \
  "$stage_dir/DEBIAN" \
  "$stage_dir/$install_rel" \
  "$stage_dir/$(dirname "$profile_rel")" \
  "$extract_dir/llvm" \
  "$extract_dir/core" \
  "$(dirname "$output_path")"

tar -xzf "$llvm_archive" -C "$extract_dir/llvm"
tar -xzf "$core_archive" -C "$extract_dir/core"

llvm_payload="$extract_dir/llvm/$AT_LLVM_PACKAGE_NAME"
core_payload="$extract_dir/core/$AT_CORE_PACKAGE_NAME"
readonly llvm_payload core_payload
[[ -d "$llvm_payload" ]] ||
  die "LLVM archive has no expected payload root: ${llvm_payload}"
[[ -d "$core_payload" ]] ||
  die "core-tools archive has no expected payload root: ${core_payload}"

[[ -x "$llvm_payload/bin/clang-15" ]] ||
  die "cached LLVM payload is missing clang-15"
for driver in clang clang++ clang++-15 clang-cpp cc c++; do
  [[ -L "$llvm_payload/bin/$driver" && -x "$llvm_payload/bin/$driver" ]] ||
    die "cached LLVM payload has an invalid driver alias: ${driver}"
done

cp -a \
  "$llvm_payload/bin" \
  "$llvm_payload/lib" \
  "$llvm_payload/share" \
  "$stage_dir/$install_rel/"
install -m 0644 "$llvm_payload/BUILD-INFO.txt" \
  "$stage_dir/$install_rel/share/doc/clang-${AT_LLVM_VERSION}/BUILD-INFO.txt"

core_source="$core_payload/$install_rel"
[[ -d "$core_source" && ! -L "$core_source" ]] ||
  die "core-tools archive is not built for ${AT_INSTALL_PREFIX}; run a full rebuild"
readonly core_source
cp -a "$core_source/." "$stage_dir/$install_rel/"

toolchain_doc_dir="$stage_dir/$install_rel/share/doc/altivec-toolchain"
readonly toolchain_doc_dir
[[ -d "$toolchain_doc_dir" ]] ||
  die "core-tools archive is missing its documentation directory"

install -m 0755 "$sdk_manager_script" \
  "$stage_dir/$install_rel/bin/altivec-sdk"
install -m 0755 "$lib_manager_script" \
  "$stage_dir/$install_rel/bin/altivec-lib"
install -m 0755 "$ios_app_tool" \
  "$stage_dir/$install_rel/bin/altivec-app"
install -D -m 0644 "$sdk_catalog" \
  "$stage_dir/$install_rel/share/altivec-sdk/catalog.json"
install -D -m 0644 "$ios_app_makefile" \
  "$stage_dir/$install_rel/share/altivec/make/ios-app.mk"
mkdir -p "$stage_dir/$install_rel/share/altivec/templates/ios-app"
cp -a "$ios_app_template_dir/." \
  "$stage_dir/$install_rel/share/altivec/templates/ios-app/"
install -m 0644 "$profile_script" "$stage_dir/$profile_rel"

core_bin="$stage_dir/$install_rel/bin"
for tool in altivec-sdk altivec-lib altivec-app ldid zip unzip curl git magick make file awk patch jq \
  xz unxz xzcat sqlite3 wc; do
  [[ -x "$core_bin/$tool" ]] ||
    die "combined payload is missing core tool: ${tool}"
done
[[ -L "$core_bin/ld" && -x "$core_bin/ld" ]] ||
  die "combined payload has an invalid ld alias"
for item in \
  etc/ssl/certs/cacert.pem \
  etc/ImageMagick-7/policy.xml \
  include/magic.h \
  include/sqlite3.h \
  include/sqlite3ext.h \
  lib/libmagic.a \
  lib/libsqlite3.a \
  share/ImageMagick-7/locale.xml \
  share/altivec/make/ios-app.mk \
  share/altivec/templates/ios-app/Makefile \
  share/altivec/templates/ios-app/source/iOS/Makefile \
  share/altivec/templates/ios-app/source/iOS/Info.plist \
  share/altivec/templates/ios-app/source/iOS/Resources/Default.png \
  share/altivec/templates/ios-app/source/shared/Resources/en.lproj/Localizable.strings \
  share/misc/magic.mgc; do
  [[ -f "$stage_dir/$install_rel/$item" ]] ||
    die "combined payload is missing core-tools file: ${item}"
done
[[ ! -e "$core_bin/cmake" ]] || die "CMake must remain container-only"
[[ -f "$stage_dir/$profile_rel" ]] ||
  die "combined payload is missing profile script: /${profile_rel}"
[[ ! -e "$stage_dir/etc/profile.d/altivecchain.sh" ]] ||
  die "legacy profile script leaked into combined payload"
[[ ! -e "$stage_dir/$install_rel/SDKs" ]] ||
  die "SDK payloads must not be embedded in the Debian package"
[[ ! -e "$stage_dir/$install_rel/Libraries" ]] ||
  die "managed libraries must not be embedded in the Debian package"
if find "$stage_dir" \
    \( -type d -name '*.sdk' -o -type f -name '*.sdk.tar.*' \
       -o -type f -iname '*arclite*' \) \
    -print -quit | grep -q .; then
  die "an SDK or ARCLite file leaked into the Debian package"
fi
while IFS= read -r -d '' staged_file; do
  if [[ "$(sha256sum "$staged_file" | awk '{print $1}')" == \
      f019ba9bf87bb7a47cfd063542d9e6ed81efe76472c869ad509230aafef18bf8 ]]; then
    die "Apple Xcode ARCLite leaked into the Debian package: ${staged_file}"
  fi
done < <(find "$stage_dir" -type f -size 284128c -print0)
[[ -d "$stage_dir/$install_rel" && ! -L "$stage_dir/$install_rel" ]] ||
  die "package install prefix must be a real directory, not a compatibility symlink"
[[ -d "$stage_dir/var" && ! -L "$stage_dir/var" ]] ||
  die "package must contain a real /var directory, not a package-created symlink"
for forbidden_path in "$stage_dir/usr" "$stage_dir/private"; do
  [[ ! -e "$forbidden_path" && ! -L "$forbidden_path" ]] ||
    die "package contains a forbidden top-level path: ${forbidden_path}"
done
grep -Fqx '_altivec_bin=/var/altivec/bin' "$stage_dir/$profile_rel" ||
  die "profile script does not export the canonical /var/altivec prefix"

while IFS= read -r -d '' staged_file; do
  if LC_ALL=C grep -aFq -- "${project_root}/" "$staged_file"; then
    die "combined payload embeds the repository's absolute path: ${staged_file}"
  fi
  if strings "$staged_file" | grep -Eq \
      '(^|[[:space:]"=:,])(-{1,2}[[:alnum:]_-]+=?){0,1}/[^[:space:]]*build-release/Intermediates/'; then
    die "combined payload embeds an absolute container build path: ${staged_file}"
  fi
  if LC_ALL=C grep -aFq -- "/usr/local/altivec" "$staged_file"; then
    die "combined payload embeds the obsolete /usr/local prefix: ${staged_file}"
  fi
  if LC_ALL=C grep -aFq -- "/private/var/altivec" "$staged_file"; then
    die "combined payload embeds /private/var directly instead of /var: ${staged_file}"
  fi
done < <(find "$stage_dir" -path "$stage_dir/DEBIAN" -prune -o \
  -type f -print0)

while IFS= read -r -d '' staged_link; do
  link_target="$(readlink "$staged_link")"
  [[ "$link_target" != /* ]] ||
    die "combined payload contains an absolute symlink: ${staged_link} -> ${link_target}"
done < <(find "$stage_dir" -path "$stage_dir/DEBIAN" -prune -o \
  -type l -print0)

checksum_file="$toolchain_doc_dir/SHA256SUMS"
rm -f -- "$checksum_file"
checksum_rel="${checksum_file#"${stage_dir}/"}"
(
  cd "$stage_dir"
  find . \
    -path ./DEBIAN -prune -o \
    -type f ! -path "./${checksum_rel}" -print0 |
    sort -z |
    xargs -0 sha256sum
) > "$checksum_file"

installed_size="$(
  du -sk "$stage_dir/etc" "$stage_dir/var" |
    awk '{total += $1} END {print total}'
)"

{
  printf 'Package: %s\n' "$AT_PACKAGE_ID"
  printf 'Name: %s\n' "$AT_DISPLAY_NAME"
  printf 'Version: %s\n' "$AT_VERSION"
  printf 'Architecture: %s\n' "$AT_ARCH"
  printf 'Section: %s\n' "$AT_SECTION"
  printf 'Priority: %s\n' "$AT_PRIORITY"
  printf 'Maintainer: %s\n' "$AT_MAINTAINER"
  printf 'Installed-Size: %s\n' "$installed_size"
  printf 'Depends: %s\n' "$AT_DEPENDS"
  printf 'Conflicts: %s\n' "$AT_CONFLICTS"
  printf 'Replaces: %s\n' "$AT_REPLACES"
  printf 'Description: %s\n' "$AT_DESCRIPTION"
} > "$stage_dir/DEBIAN/control"

find "$stage_dir" -type d -exec chmod 0755 {} +
chmod 0644 "$stage_dir/DEBIAN/control" "$stage_dir/$profile_rel"
chmod 0755 \
  "$stage_dir/$install_rel/bin/clang-15" \
  "$stage_dir/$install_rel/bin/altivec-sdk" \
  "$stage_dir/$install_rel/bin/altivec-lib" \
  "$stage_dir/$install_rel/bin/altivec-app" \
  "$stage_dir/$install_rel/share/altivec/templates/ios-app/tools/generate-launch-images.sh"

# The positional parameters are intentionally expanded by fakeroot's child shell.
# shellcheck disable=SC2016
"$fakeroot_tool" sh -c \
  'chown -R 0:0 "$1" && exec "$2" "-Z$4" --build "$1" "$3"' \
  sh "$stage_dir" "$dpkg_deb_tool" "$output_path" "$AT_COMPRESSION"

printf 'Combined Debian package: %s\n' "$output_path"
