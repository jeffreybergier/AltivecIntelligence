#!/usr/bin/env bash

set -euo pipefail

# Portable command-line tools.
readonly DIFFUTILS_VERSION="3.12"
readonly DIFFUTILS_SHA256="7c8b7f9fc8609141fdea9cece85249d308624391ff61dedaf528fcb337727dfd"
readonly FINDUTILS_VERSION="4.10.0"
readonly FINDUTILS_SHA256="1387e0b67ff247d2abde998f90dfbf70c1491391a59ddfecb8ae698789f0a4f5"
readonly GREP_VERSION="3.12"
readonly GREP_SHA256="2649b27c0e90e632eadcd757be06c6e9a4f48d941de51e7c0f83ff76408a07b9"
readonly SED_VERSION="4.9"
readonly SED_SHA256="6e226b732e1cd739464ad6862bd1a1aba42d7982922da7a53519631d24975181"
readonly TAR_VERSION="1.35"
readonly TAR_SHA256="4d62ff37342ec7aed748535323930c7cf94acf71c3591882b26a7ea50f3edc16"
readonly GZIP_VERSION="1.14"
readonly GZIP_SHA256="01a7b881bd220bfdf615f97b8718f80bdfd3f6add385b993dcf6efd14e8c0ac6"
readonly BZIP2_VERSION="1.0.8"
readonly BZIP2_SHA256="ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269"

# Terminal-oriented tools and their private static dependencies.
readonly NCURSES_VERSION="6.5"
readonly NCURSES_SHA256="136d91bc269a9a5785e5f9e980bc76ab57428f604ce3e5a5a90cebc767971cc6"
readonly LESS_VERSION="668"
readonly LESS_SHA256="2819f55564d86d542abbecafd82ff61e819a3eec967faa36cd3e68f1596a44b8"
readonly VIM_VERSION="8.2.5172"
readonly VIM_SHA256="366a45168f59d7218ea22597432e64ac05c2626703b5d8fa70f37bfd674cd2c1"
readonly HTOP_VERSION="2.2.0"
readonly HTOP_SHA256="d9d6826f10ce3887950d709b53ee1d8c1849a70fa38e91d5896ad8cbc6ba3c57"
readonly PROCPS_VERSION="3.3.17"
readonly PROCPS_SHA256="4518b3e7aafd34ec07d0063d250fd474999b20b200218c3ae56f5d2113f141b4"
readonly MANDOC_VERSION="1.14.6"
readonly MANDOC_SHA256="8bf0d570f01e70a6e124884088870cbed7537f36328d512909eb10cd53179d9c"
readonly TREE_VERSION="2.2.1"
readonly TREE_SHA256="70d9c6fc7c5f4cb1f7560b43e2785194594b9b8f6855ab53376f6bd88667ee04"

# Darwin-native tools.  The network versions are deliberately split:
# network_cmds 481 supplies ping, while 356 supplies an ifconfig whose
# structures still match the public headers usable by the iPhoneOS SDK.
readonly SHELL_CMDS_VERSION="198"
readonly SHELL_CMDS_SHA256="dce4e7152b3723b6e6f6e5c1b56d5566b94660d12333b289e38e7eba3fc68623"
readonly TEXT_CMDS_VERSION="118"
readonly TEXT_CMDS_SHA256="b830038e3821c46dfbb0acf0199a36a351a3ded27936a6e1fffbabd437c23b40"
readonly ADV_CMDS_VERSION="163"
readonly ADV_CMDS_SHA256="66da7c00b59cbe2129b61a2263cb6d5b3188f0e72c2f3b142e396a7bc188cf0f"
readonly NETWORK_CMDS_PING_VERSION="481.20.1"
readonly NETWORK_CMDS_PING_SHA256="23cf422c8b301a179ec0e8e2359c104e05af59b866d2ab41e7e294ab3c674393"
readonly NETWORK_CMDS_IFCONFIG_VERSION="356.9"
readonly NETWORK_CMDS_IFCONFIG_SHA256="6633b35db61fa1c6ada3aea718547380ceb9e92b6c1d01cc3c224b4cdde38555"
readonly NETCAT_VERSION="7"
readonly NETCAT_SHA256="615dfe75b289d8a362f15eb32900f8416cfd7b1099f462b408f3d0a00bd72ca6"
readonly PKILL_DARWIN_VERSION="1.0+"
readonly PKILL_DARWIN_SHA256="6191571014efebd7987fc4c9ab5bc72c7f39aedd0524e6cfb9e17a93d6375201"
readonly PKILL_DARWIN_MAN_SHA256="c3da1786540942c5e35c496c3773fb4cba80f58dc3c22098e993fcd094703880"
readonly FREEBSD_VERSION="10.2"
readonly FREEBSD_LOGGER_SHA256="58eaeae16e3015a4a21e6269501579bffec81e693d4429d574ec0ac4c9b7e984"
readonly FREEBSD_LOGGER_MAN_SHA256="e1392603a08a8855d8a7e29860aac41d918e981a7f6a64d434c2be6e0c408d16"
readonly FREEBSD_REALPATH_SHA256="62c5845f289e4a14d542255ce1785ff458cd9b9ebc93480807a9a2a5493979de"
readonly FREEBSD_REALPATH_MAN_SHA256="c05e73688cb2d548b0652359c65dfd402a3e64216de4a1e1954f71b184f5d70d"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/.." && pwd -P)"

action="stage"
if (($# > 0)) && [[ "$1" != -* ]]; then
  action="$1"
  shift
fi

work_dir="${repo_root}/build-release/Intermediates/core-tools-armv7"
archives_dir=""
sources_dir=""
sdk_dir="/osxcross/target/SDK/iPhoneOS8.4.sdk"
cctools_bin="/osxcross/target/bin"
deployment_target="6.0"
jobs="2"
install_prefix="/var/altivec"
cc="/usr/bin/clang-14"
zlib_static=""
ps_patch="${script_dir}/adv-cmds-ps-ios-workqueue.patch"
mandoc_config_template="${script_dir}/mandoc-ios-configure.local.in"

usage() {
  printf '%s\n' \
    "Usage: $(basename "$0") [source|stage|verify] [options]" \
    "" \
    "  source  Download, verify, extract, and patch the pinned sources." \
    "  stage   Build and stage the approved extra tools (default)." \
    "  verify  Validate an existing matching component stage." \
    "" \
    "Options:" \
    "  --work-dir <path>          Parent core-tools work directory." \
    "  --archives-dir <path>      Shared archive cache." \
    "  --sources-dir <path>       Extra-tools source directory." \
    "  --sdk <path>               iPhoneOS SDK." \
    "  --cctools-bin <path>       Mach-O archive and linker tools." \
    "  --deployment-target <ver>  Minimum iOS version." \
    "  --jobs <count>             Parallel build jobs." \
    "  --prefix <path>            Phone installation prefix." \
    "  --cc <path>                Host Clang executable." \
    "  --zlib-static <path>       Target libz.a used by mandoc." \
    "  --ps-patch <path>          adv_cmds ps compatibility patch." \
    "  --mandoc-config <path>     mandoc configure.local template."
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

while (($# > 0)); do
  case "$1" in
    --work-dir)
      (($# >= 2)) || die "--work-dir requires a value"
      work_dir="$2"
      shift 2
      ;;
    --archives-dir)
      (($# >= 2)) || die "--archives-dir requires a value"
      archives_dir="$2"
      shift 2
      ;;
    --sources-dir)
      (($# >= 2)) || die "--sources-dir requires a value"
      sources_dir="$2"
      shift 2
      ;;
    --sdk)
      (($# >= 2)) || die "--sdk requires a value"
      sdk_dir="$2"
      shift 2
      ;;
    --cctools-bin)
      (($# >= 2)) || die "--cctools-bin requires a value"
      cctools_bin="$2"
      shift 2
      ;;
    --deployment-target)
      (($# >= 2)) || die "--deployment-target requires a value"
      deployment_target="$2"
      shift 2
      ;;
    --jobs)
      (($# >= 2)) || die "--jobs requires a value"
      jobs="$2"
      shift 2
      ;;
    --prefix)
      (($# >= 2)) || die "--prefix requires a value"
      install_prefix="$2"
      shift 2
      ;;
    --cc)
      (($# >= 2)) || die "--cc requires a value"
      cc="$2"
      shift 2
      ;;
    --zlib-static)
      (($# >= 2)) || die "--zlib-static requires a value"
      zlib_static="$2"
      shift 2
      ;;
    --ps-patch)
      (($# >= 2)) || die "--ps-patch requires a value"
      ps_patch="$2"
      shift 2
      ;;
    --mandoc-config)
      (($# >= 2)) || die "--mandoc-config requires a value"
      mandoc_config_template="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

case "$action" in
  source|stage|verify)
    ;;
  *)
    die "unknown action: ${action}"
    ;;
esac

[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive integer"
[[ "$deployment_target" =~ ^[0-9]+([.][0-9]+)*$ ]] ||
  die "invalid deployment target: ${deployment_target}"
[[ "$install_prefix" == /* && "$install_prefix" != "/" ]] ||
  die "install prefix must be an absolute non-root path"

if [[ -z "$archives_dir" ]]; then
  archives_dir="${work_dir}/../Archives"
fi
if [[ -z "$sources_dir" ]]; then
  sources_dir="${work_dir}/sources/extra-tools"
fi

mkdir -p "$work_dir" "$archives_dir" "$sources_dir"
work_dir="$(realpath "$work_dir")"
archives_dir="$(realpath "$archives_dir")"
sources_dir="$(realpath "$sources_dir")"
sdk_dir="$(realpath "$sdk_dir")"
cctools_bin="$(realpath "$cctools_bin")"
cc="$(realpath "$cc")"
ps_patch="$(realpath "$ps_patch")"
mandoc_config_template="$(realpath "$mandoc_config_template")"

readonly work_dir archives_dir sources_dir sdk_dir cctools_bin cc
readonly ps_patch mandoc_config_template
readonly target_triple="armv7-apple-ios${deployment_target}"
readonly autoconf_host="armv7-apple-darwin11"
readonly prefix_rel="${install_prefix#/}"
readonly component_root="${work_dir}/extra-tools"
readonly component_stage="${component_root}/stage"
readonly stage_prefix="${component_stage}/${prefix_rel}"
readonly host_tools_dir="${component_root}/host-tools"
readonly host_man_indexer="${host_tools_dir}/makewhatis"
readonly completed_marker="${component_root}/.completed"
readonly stamp="${component_root}/.altivec-toolchain-config"
readonly build_root_stamp="${component_root}/.altivec-toolchain-build-root"
macos_compat_sdk="$(dirname "$sdk_dir")/MacOSX10.5.sdk"
readonly macos_compat_sdk
readonly macho_ar="${cctools_bin}/x86_64-apple-darwin9-ar"
readonly macho_ranlib="${cctools_bin}/x86_64-apple-darwin9-ranlib"
readonly macho_strip="${cctools_bin}/x86_64-apple-darwin9-strip"
readonly macho_otool="${cctools_bin}/x86_64-apple-darwin9-otool"
readonly repo_prefix_map_flags="-ffile-prefix-map=${repo_root}=. -fdebug-prefix-map=${repo_root}=. -fmacro-prefix-map=${repo_root}=."
readonly cc_command="${cc} --target=${target_triple} -isysroot ${sdk_dir} -B${cctools_bin} ${repo_prefix_map_flags}"
readonly common_cppflags="-idirafter ${macos_compat_sdk}/usr/include"
readonly common_cflags="-O2 -miphoneos-version-min=${deployment_target}"
readonly common_ldflags="-miphoneos-version-min=${deployment_target} -isysroot ${sdk_dir} -B${cctools_bin}"

for required in \
  "$sdk_dir" "$macos_compat_sdk" "$cctools_bin" "$ps_patch" \
  "$mandoc_config_template"; do
  [[ -e "$required" ]] || die "required build input is missing: ${required}"
done
for required in \
  "$cc" "$macho_ar" "$macho_ranlib" "$macho_strip" "$macho_otool"; do
  [[ -x "$required" ]] || die "required tool is not executable: ${required}"
done
for required in curl tar make patch sha256sum file sed install; do
  command -v "$required" >/dev/null 2>&1 ||
    die "required host tool is missing: ${required}"
done

readonly diffutils_archive="${archives_dir}/diffutils-${DIFFUTILS_VERSION}.tar.xz"
readonly findutils_archive="${archives_dir}/findutils-${FINDUTILS_VERSION}.tar.xz"
readonly grep_archive="${archives_dir}/grep-${GREP_VERSION}.tar.xz"
readonly sed_archive="${archives_dir}/sed-${SED_VERSION}.tar.xz"
readonly tar_archive="${archives_dir}/tar-${TAR_VERSION}.tar.xz"
readonly gzip_archive="${archives_dir}/gzip-${GZIP_VERSION}.tar.xz"
readonly bzip2_archive="${archives_dir}/bzip2-${BZIP2_VERSION}.tar.gz"
readonly ncurses_archive="${archives_dir}/ncurses-${NCURSES_VERSION}.tar.gz"
readonly less_archive="${archives_dir}/less-${LESS_VERSION}.tar.gz"
readonly vim_archive="${archives_dir}/vim-${VIM_VERSION}.tar.gz"
readonly htop_archive="${archives_dir}/htop-${HTOP_VERSION}.tar.gz"
readonly procps_archive="${archives_dir}/procps-ng-${PROCPS_VERSION}.tar.xz"
readonly mandoc_archive="${archives_dir}/mandoc-${MANDOC_VERSION}.tar.gz"
readonly tree_archive="${archives_dir}/tree-${TREE_VERSION}.tar.gz"
readonly shell_cmds_archive="${archives_dir}/shell_cmds-${SHELL_CMDS_VERSION}.tar.gz"
readonly text_cmds_archive="${archives_dir}/text_cmds-${TEXT_CMDS_VERSION}.tar.gz"
readonly adv_cmds_archive="${archives_dir}/adv_cmds-${ADV_CMDS_VERSION}.tar.gz"
readonly network_ping_archive="${archives_dir}/network_cmds-${NETWORK_CMDS_PING_VERSION}.tar.gz"
readonly network_ifconfig_archive="${archives_dir}/network_cmds-${NETWORK_CMDS_IFCONFIG_VERSION}.tar.gz"
readonly netcat_archive="${archives_dir}/netcat-${NETCAT_VERSION}.tar.gz"
readonly pkill_source="${sources_dir}/pkill-darwin-${PKILL_DARWIN_VERSION}.c"
readonly pkill_man="${sources_dir}/pkill-darwin-${PKILL_DARWIN_VERSION}.1"
readonly logger_source="${sources_dir}/freebsd-${FREEBSD_VERSION}-logger.c"
readonly logger_man="${sources_dir}/freebsd-${FREEBSD_VERSION}-logger.1"
readonly realpath_source="${sources_dir}/freebsd-${FREEBSD_VERSION}-realpath.c"
readonly realpath_man="${sources_dir}/freebsd-${FREEBSD_VERSION}-realpath.1"

readonly diffutils_source="${sources_dir}/diffutils-${DIFFUTILS_VERSION}"
readonly findutils_source="${sources_dir}/findutils-${FINDUTILS_VERSION}"
readonly grep_source="${sources_dir}/grep-${GREP_VERSION}"
readonly sed_source="${sources_dir}/sed-${SED_VERSION}"
readonly tar_source="${sources_dir}/tar-${TAR_VERSION}"
readonly gzip_source="${sources_dir}/gzip-${GZIP_VERSION}"
readonly bzip2_source="${sources_dir}/bzip2-${BZIP2_VERSION}"
readonly ncurses_source="${sources_dir}/ncurses-${NCURSES_VERSION}"
readonly less_source="${sources_dir}/less-${LESS_VERSION}"
readonly vim_source="${sources_dir}/vim-${VIM_VERSION}"
readonly htop_source="${sources_dir}/htop-${HTOP_VERSION}"
readonly procps_source="${sources_dir}/procps-${PROCPS_VERSION}"
readonly mandoc_source="${sources_dir}/mandoc-${MANDOC_VERSION}"
readonly tree_source="${sources_dir}/tree-${TREE_VERSION}"
readonly shell_cmds_source="${sources_dir}/shell_cmds-${SHELL_CMDS_VERSION}"
readonly text_cmds_source="${sources_dir}/text_cmds-${TEXT_CMDS_VERSION}"
readonly adv_cmds_source="${sources_dir}/adv_cmds-${ADV_CMDS_VERSION}"
readonly network_ping_source="${sources_dir}/network_cmds-${NETWORK_CMDS_PING_VERSION}"
readonly network_ifconfig_source="${sources_dir}/network_cmds-${NETWORK_CMDS_IFCONFIG_VERSION}"
readonly netcat_source="${sources_dir}/netcat-${NETCAT_VERSION}"

fetch_file() {
  local destination="$1"
  local url="$2"
  local expected_sha256="$3"
  local actual_sha256=""
  local temporary=""

  if [[ ! -f "$destination" ]]; then
    temporary="$(mktemp "${archives_dir}/.extra-download.XXXXXX")"
    printf 'Downloading %s\n' "$url"
    if ! curl -fL --retry 3 --retry-delay 2 -o "$temporary" "$url"; then
      rm -f -- "$temporary"
      die "download failed: ${url}"
    fi
    actual_sha256="$(sha256sum "$temporary" | awk '{print $1}')"
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
      rm -f -- "$temporary"
      die "checksum mismatch for ${url}: expected ${expected_sha256}, got ${actual_sha256}"
    fi
    mv -- "$temporary" "$destination"
  fi

  actual_sha256="$(sha256sum "$destination" | awk '{print $1}')"
  [[ "$actual_sha256" == "$expected_sha256" ]] ||
    die "cached source checksum mismatch: ${destination}"
}

extract_archive() {
  local archive="$1"
  local destination="$2"
  local compression="$3"
  local strip_components="$4"
  local temporary=""
  local -a tar_flags=()

  [[ ! -d "$destination" ]] || return 0
  temporary="$(mktemp -d "${sources_dir}/.extra-source.XXXXXX")"
  case "$compression" in
    gz)
      tar_flags=(-xzf)
      ;;
    xz)
      tar_flags=(-xJf)
      ;;
    *)
      die "unsupported source compression: ${compression}"
      ;;
  esac
  if [[ "$strip_components" == "1" ]]; then
    if ! tar "${tar_flags[@]}" "$archive" --strip-components=1 -C "$temporary"; then
      rm -rf -- "$temporary"
      die "could not extract ${archive}"
    fi
  else
    if ! tar "${tar_flags[@]}" "$archive" -C "$temporary"; then
      rm -rf -- "$temporary"
      die "could not extract ${archive}"
    fi
  fi
  [[ -n "$(find "$temporary" -mindepth 1 -maxdepth 1 -print -quit)" ]] || {
    rm -rf -- "$temporary"
    die "source archive extracted no files: ${archive}"
  }
  mv -- "$temporary" "$destination"
}

apply_patch_once() {
  local source_dir="$1"
  local patch_file="$2"
  local description="$3"

  if patch -d "$source_dir" -p1 --batch --forward --dry-run \
      < "$patch_file" >/dev/null 2>&1; then
    printf 'Applying %s\n' "$description"
    patch -d "$source_dir" -p1 --batch --forward < "$patch_file"
  elif patch -d "$source_dir" -p1 --batch --reverse --dry-run \
      < "$patch_file" >/dev/null 2>&1; then
    return 0
  else
    die "could not apply or verify patch: ${patch_file}"
  fi
}

prepare_sources() {
  fetch_file "$diffutils_archive" \
    "https://ftpmirror.gnu.org/diffutils/diffutils-${DIFFUTILS_VERSION}.tar.xz" \
    "$DIFFUTILS_SHA256"
  extract_archive "$diffutils_archive" "$diffutils_source" xz 1

  fetch_file "$findutils_archive" \
    "https://ftpmirror.gnu.org/findutils/findutils-${FINDUTILS_VERSION}.tar.xz" \
    "$FINDUTILS_SHA256"
  extract_archive "$findutils_archive" "$findutils_source" xz 1

  fetch_file "$grep_archive" \
    "https://ftpmirror.gnu.org/grep/grep-${GREP_VERSION}.tar.xz" \
    "$GREP_SHA256"
  extract_archive "$grep_archive" "$grep_source" xz 1

  fetch_file "$sed_archive" \
    "https://ftpmirror.gnu.org/sed/sed-${SED_VERSION}.tar.xz" \
    "$SED_SHA256"
  extract_archive "$sed_archive" "$sed_source" xz 1

  fetch_file "$tar_archive" \
    "https://ftpmirror.gnu.org/tar/tar-${TAR_VERSION}.tar.xz" \
    "$TAR_SHA256"
  extract_archive "$tar_archive" "$tar_source" xz 1

  fetch_file "$gzip_archive" \
    "https://ftpmirror.gnu.org/gzip/gzip-${GZIP_VERSION}.tar.xz" \
    "$GZIP_SHA256"
  extract_archive "$gzip_archive" "$gzip_source" xz 1

  fetch_file "$bzip2_archive" \
    "https://sourceware.org/pub/bzip2/bzip2-${BZIP2_VERSION}.tar.gz" \
    "$BZIP2_SHA256"
  extract_archive "$bzip2_archive" "$bzip2_source" gz 1

  fetch_file "$ncurses_archive" \
    "https://invisible-island.net/archives/ncurses/ncurses-${NCURSES_VERSION}.tar.gz" \
    "$NCURSES_SHA256"
  extract_archive "$ncurses_archive" "$ncurses_source" gz 1

  fetch_file "$less_archive" \
    "https://www.greenwoodsoftware.com/less/less-${LESS_VERSION}.tar.gz" \
    "$LESS_SHA256"
  extract_archive "$less_archive" "$less_source" gz 1

  fetch_file "$vim_archive" \
    "https://github.com/vim/vim/archive/refs/tags/v${VIM_VERSION}.tar.gz" \
    "$VIM_SHA256"
  extract_archive "$vim_archive" "$vim_source" gz 1

  fetch_file "$htop_archive" \
    "https://hisham.hm/htop/releases/${HTOP_VERSION}/htop-${HTOP_VERSION}.tar.gz" \
    "$HTOP_SHA256"
  extract_archive "$htop_archive" "$htop_source" gz 1

  fetch_file "$procps_archive" \
    "https://sourceforge.net/projects/procps-ng/files/Production/procps-ng-${PROCPS_VERSION}.tar.xz/download" \
    "$PROCPS_SHA256"
  extract_archive "$procps_archive" "$procps_source" xz 1

  fetch_file "$mandoc_archive" \
    "https://mandoc.bsd.lv/snapshots/mandoc-${MANDOC_VERSION}.tar.gz" \
    "$MANDOC_SHA256"
  extract_archive "$mandoc_archive" "$mandoc_source" gz 1

  fetch_file "$tree_archive" \
    "https://gitlab.com/OldManProgrammer/unix-tree/-/archive/${TREE_VERSION}/unix-tree-${TREE_VERSION}.tar.gz" \
    "$TREE_SHA256"
  extract_archive "$tree_archive" "$tree_source" gz 1

  fetch_file "$shell_cmds_archive" \
    "https://github.com/apple-oss-distributions/shell_cmds/archive/refs/tags/shell_cmds-${SHELL_CMDS_VERSION}.tar.gz" \
    "$SHELL_CMDS_SHA256"
  extract_archive "$shell_cmds_archive" "$shell_cmds_source" gz 1

  fetch_file "$text_cmds_archive" \
    "https://github.com/apple-oss-distributions/text_cmds/archive/refs/tags/text_cmds-${TEXT_CMDS_VERSION}.tar.gz" \
    "$TEXT_CMDS_SHA256"
  extract_archive "$text_cmds_archive" "$text_cmds_source" gz 1

  fetch_file "$adv_cmds_archive" \
    "https://github.com/apple-oss-distributions/adv_cmds/archive/refs/tags/adv_cmds-${ADV_CMDS_VERSION}.tar.gz" \
    "$ADV_CMDS_SHA256"
  extract_archive "$adv_cmds_archive" "$adv_cmds_source" gz 1
  apply_patch_once "$adv_cmds_source" "$ps_patch" \
    "adv_cmds ps public-SDK workqueue fallback"

  fetch_file "$network_ping_archive" \
    "https://github.com/apple-oss-distributions/network_cmds/archive/refs/tags/network_cmds-${NETWORK_CMDS_PING_VERSION}.tar.gz" \
    "$NETWORK_CMDS_PING_SHA256"
  extract_archive "$network_ping_archive" "$network_ping_source" gz 1

  fetch_file "$network_ifconfig_archive" \
    "https://github.com/apple-oss-distributions/network_cmds/archive/refs/tags/network_cmds-${NETWORK_CMDS_IFCONFIG_VERSION}.tar.gz" \
    "$NETWORK_CMDS_IFCONFIG_SHA256"
  extract_archive "$network_ifconfig_archive" "$network_ifconfig_source" gz 1

  fetch_file "$netcat_archive" \
    "https://github.com/apple-oss-distributions/netcat/archive/refs/tags/netcat-${NETCAT_VERSION}.tar.gz" \
    "$NETCAT_SHA256"
  extract_archive "$netcat_archive" "$netcat_source" gz 1

  fetch_file "$pkill_source" \
    "https://sourceforge.net/p/pkilldarwin/code/ci/default/tree/pkill.c?format=raw" \
    "$PKILL_DARWIN_SHA256"
  fetch_file "$pkill_man" \
    "https://sourceforge.net/p/pkilldarwin/code/ci/default/tree/pkill.1?format=raw" \
    "$PKILL_DARWIN_MAN_SHA256"

  fetch_file "$logger_source" \
    "https://raw.githubusercontent.com/freebsd/freebsd-src/release/10.2.0/usr.bin/logger/logger.c" \
    "$FREEBSD_LOGGER_SHA256"
  fetch_file "$logger_man" \
    "https://raw.githubusercontent.com/freebsd/freebsd-src/release/10.2.0/usr.bin/logger/logger.1" \
    "$FREEBSD_LOGGER_MAN_SHA256"
  fetch_file "$realpath_source" \
    "https://raw.githubusercontent.com/freebsd/freebsd-src/release/10.2.0/bin/realpath/realpath.c" \
    "$FREEBSD_REALPATH_SHA256"
  fetch_file "$realpath_man" \
    "https://raw.githubusercontent.com/freebsd/freebsd-src/release/10.2.0/bin/realpath/realpath.1" \
    "$FREEBSD_REALPATH_MAN_SHA256"
}

safe_remove_component() {
  local path="$1"
  case "$path" in
    "${work_dir}/"*)
      ;;
    *)
      die "refusing to remove path outside the work directory: ${path}"
      ;;
  esac
  [[ "$path" != "$work_dir" ]] ||
    die "refusing to remove the work directory itself"
  if [[ -e "$path" || -L "$path" ]]; then
    rm -rf -- "$path"
  fi
}

compiler_version() {
  "$cc" --version | sed -n '1p'
}

repo_path_identity() {
  local path=""
  path="$(realpath -m "$1")"
  case "$path" in
    "$repo_root")
      printf '.\n'
      ;;
    "${repo_root}/"*)
      printf './%s\n' "${path#"${repo_root}/"}"
      ;;
    *)
      printf '%s\n' "$path"
      ;;
  esac
}

component_key() {
  local builder_sha=""
  local patch_sha=""
  local mandoc_config_sha=""

  builder_sha="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
  patch_sha="$(sha256sum "$ps_patch" | awk '{print $1}')"
  mandoc_config_sha="$(sha256sum "$mandoc_config_template" | awk '{print $1}')"
  printf '%s\n' \
    "extra-schema=3;builder=${builder_sha};diffutils=${DIFFUTILS_VERSION};findutils=${FINDUTILS_VERSION};grep=${GREP_VERSION};sed=${SED_VERSION};tar=${TAR_VERSION};gzip=${GZIP_VERSION};bzip2=${BZIP2_VERSION};ncurses=${NCURSES_VERSION};less=${LESS_VERSION};vim=${VIM_VERSION};htop=${HTOP_VERSION};procps=${PROCPS_VERSION};mandoc=${MANDOC_VERSION};tree=${TREE_VERSION};shell-cmds=${SHELL_CMDS_VERSION};text-cmds=${TEXT_CMDS_VERSION};adv-cmds=${ADV_CMDS_VERSION};network-ping=${NETWORK_CMDS_PING_VERSION};network-ifconfig=${NETWORK_CMDS_IFCONFIG_VERSION};netcat=${NETCAT_VERSION};pkill-darwin=${PKILL_DARWIN_VERSION};freebsd=${FREEBSD_VERSION};ps-patch=${patch_sha};mandoc-config=${mandoc_config_sha};sdk=${sdk_dir};target=${target_triple};cc=${cc}:$(compiler_version);prefix=${install_prefix};sources=$(repo_path_identity "$sources_dir")"
}

prepare_component() {
  local key=""
  local current=""
  local build_root_current=""
  local build_root_identity="repo-root=${repo_root};work-dir=${work_dir};sources-dir=${sources_dir}"

  key="$(component_key)"

  if [[ -f "$stamp" ]]; then
    current="$(<"$stamp")"
  fi
  if [[ -f "$build_root_stamp" ]]; then
    build_root_current="$(<"$build_root_stamp")"
  fi
  if [[ "$current" != "$key" ||
      "$build_root_current" != "$build_root_identity" ]]; then
    safe_remove_component "$component_root"
    mkdir -p "$component_root"
    printf '%s\n' "$key" > "$stamp"
    printf '%s\n' "$build_root_identity" > "$build_root_stamp"
  fi
}

validate_component_cache() {
  local expected=""
  local current=""

  expected="$(component_key)"
  [[ -f "$stamp" ]] ||
    die "extra-tools component cache is missing; build it with the stage action"
  current="$(<"$stamp")"
  [[ "$current" == "$expected" ]] ||
    die "extra-tools component cache has different build inputs; rebuild it"
  [[ -f "$completed_marker" ]] ||
    die "extra-tools component cache is incomplete; rebuild it"
  verify_stage
}

build_gnu_component() {
  local name="$1"
  local source="$2"
  local libs="$3"
  shift 3
  local build="${component_root}/build-${name}"
  local stage="${component_root}/stage-${name}"

  mkdir -p "$build" "$stage"
  if [[ ! -f "${build}/Makefile" ]]; then
    printf 'Configuring %s\n' "$name"
    (
      cd "$build"
      # The iOS 8.4 SDK declares these POSIX.1-2008 APIs, but they are not
      # present in the iOS 6 runtime.  Force gnulib to build its fallbacks.
      CC="$cc_command" \
      AR="$macho_ar" \
      RANLIB="$macho_ranlib" \
      STRIP="$macho_strip" \
      CPPFLAGS="$common_cppflags" \
      CFLAGS="$common_cflags" \
      LDFLAGS="$common_ldflags" \
      LIBS="$libs" \
      gl_cv_func_strcasecmp_works=yes \
      ac_cv_func_malloc_0_nonnull=yes \
      ac_cv_func_realloc_0_nonnull=yes \
      ac_cv_func_faccessat=no \
      ac_cv_func_fchmodat=no \
      ac_cv_func_fchownat=no \
      ac_cv_func_fdopendir=no \
      ac_cv_func_fstatat=no \
      ac_cv_func_linkat=no \
      ac_cv_func_mkdirat=no \
      ac_cv_func_openat=no \
      ac_cv_func_readlinkat=no \
      ac_cv_func_renameat=no \
      ac_cv_func_symlinkat=no \
      ac_cv_func_unlinkat=no \
      "${source}/configure" \
        --build="$("$cc" -dumpmachine)" \
        --host="$autoconf_host" \
        --prefix="$install_prefix" \
        "$@"
    )
  fi
  printf 'Building %s\n' "$name"
  make -C "$build" -j"$jobs"
  make -C "$build" DESTDIR="$stage" install
}

build_portable_tools() {
  build_gnu_component "diffutils-${DIFFUTILS_VERSION}" "$diffutils_source" "" \
    --disable-dependency-tracking --disable-nls --disable-rpath \
    --disable-threads --disable-year2038
  build_gnu_component "findutils-${FINDUTILS_VERSION}" "$findutils_source" "" \
    --disable-dependency-tracking --disable-nls --disable-rpath \
    --disable-threads --disable-year2038 --without-selinux
  build_gnu_component "grep-${GREP_VERSION}" "$grep_source" "" \
    --disable-dependency-tracking --disable-nls --disable-rpath \
    --disable-threads --disable-year2038
  build_gnu_component "sed-${SED_VERSION}" "$sed_source" "" \
    --disable-acl --disable-dependency-tracking --disable-nls \
    --disable-rpath --disable-threads --disable-year2038 --without-selinux
  build_gnu_component "tar-${TAR_VERSION}" "$tar_source" "-liconv" \
    --disable-acl --disable-dependency-tracking --disable-nls \
    --disable-rpath --disable-threads --disable-year2038 \
    --without-selinux --without-xattrs
  build_gnu_component "gzip-${GZIP_VERSION}" "$gzip_source" "" \
    --disable-dependency-tracking --disable-nls --disable-rpath \
    --disable-threads --disable-year2038

  local bzip_build="${component_root}/build-bzip2-${BZIP2_VERSION}"
  if [[ ! -f "${bzip_build}/Makefile" ]]; then
    mkdir -p "$bzip_build"
    cp -a "${bzip2_source}/." "$bzip_build/"
  fi
  printf 'Building bzip2 %s\n' "$BZIP2_VERSION"
  make -C "$bzip_build" -j"$jobs" \
    CC="$cc_command" \
    AR="$macho_ar" \
    RANLIB="$macho_ranlib" \
    CFLAGS="${common_cflags} -Wall -Winline" \
    bzip2
  [[ -x "${bzip_build}/bzip2" ]] || die "bzip2 was not built"
}

build_ncurses() {
  local build="${component_root}/build-ncurses-${NCURSES_VERSION}"
  local stage="${component_root}/stage-ncurses-${NCURSES_VERSION}"

  mkdir -p "$build" "$stage"
  if [[ ! -f "${build}/Makefile" ]]; then
    printf 'Configuring ncurses %s\n' "$NCURSES_VERSION"
    (
      cd "$build"
      CC="$cc_command" \
      BUILD_CC="$cc" \
      AR="$macho_ar" \
      RANLIB="$macho_ranlib" \
      STRIP="$macho_strip" \
      CPPFLAGS="$common_cppflags" \
      CFLAGS="$common_cflags" \
      LDFLAGS="$common_ldflags" \
      "${ncurses_source}/configure" \
        --build="$("$cc" -dumpmachine)" \
        --host="$autoconf_host" \
        --prefix="$install_prefix" \
        --with-build-cc="$cc" \
        --without-ada \
        --without-cxx \
        --without-cxx-binding \
        --without-debug \
        --without-shared \
        --with-normal \
        --without-tests \
        --enable-widec \
        --enable-termcap \
        --disable-home-terminfo \
        --with-default-terminfo-dir="${install_prefix}/share/terminfo" \
        --with-terminfo-dirs="${install_prefix}/share/terminfo"
    )
  fi
  printf 'Building ncurses %s\n' "$NCURSES_VERSION"
  make -C "$build" -j"$jobs"
  make -C "$build" \
    DESTDIR="$stage" \
    INSTALL_PROG="/usr/bin/install -c" \
    install
  ln -sfn libncursesw.a "${stage}/${prefix_rel}/lib/libncurses.a"
  ln -sfn libncursesw.a "${stage}/${prefix_rel}/lib/libtinfo.a"
  [[ -x "${stage}/${prefix_rel}/bin/clear" ]] ||
    die "ncurses clear was not staged"
  [[ -x "${stage}/${prefix_rel}/bin/tset" ]] ||
    die "ncurses tset/reset implementation was not staged"
}

build_less() {
  local nc_stage="${component_root}/stage-ncurses-${NCURSES_VERSION}/${prefix_rel}"
  local build="${component_root}/build-less-${LESS_VERSION}"
  local stage="${component_root}/stage-less-${LESS_VERSION}"

  mkdir -p "$build" "$stage"
  if [[ ! -f "${build}/Makefile" ]]; then
    printf 'Configuring less %s\n' "$LESS_VERSION"
    (
      cd "$build"
      CC="$cc_command" \
      AR="$macho_ar" \
      RANLIB="$macho_ranlib" \
      STRIP="$macho_strip" \
      CPPFLAGS="-I${nc_stage}/include -I${nc_stage}/include/ncursesw ${common_cppflags}" \
      CFLAGS="$common_cflags" \
      LDFLAGS="${common_ldflags} -L${nc_stage}/lib" \
      LIBS="-lncursesw" \
      ac_cv_func_malloc_0_nonnull=yes \
      ac_cv_func_realloc_0_nonnull=yes \
      "${less_source}/configure" \
        --build="$("$cc" -dumpmachine)" \
        --host="$autoconf_host" \
        --prefix="$install_prefix" \
        --with-editor=vi \
        --with-regex=posix
    )
  fi
  printf 'Building less %s\n' "$LESS_VERSION"
  make -C "$build" -j"$jobs"
  make -C "$build" DESTDIR="$stage" install
  [[ -x "${stage}/${prefix_rel}/bin/less" ]] || die "less was not staged"
}

build_vim() {
  local nc_stage="${component_root}/stage-ncurses-${NCURSES_VERSION}/${prefix_rel}"
  local build_source="${component_root}/build-vim-${VIM_VERSION}"
  local nc_stage_rel=""
  local vim_cc_command="${cc} --target=${target_triple} -isysroot ${sdk_dir} -B${cctools_bin}"

  if [[ ! -f "${build_source}/src/configure" ]]; then
    mkdir -p "$build_source"
    cp -a "${vim_source}/." "$build_source/"
  fi
  nc_stage_rel="$(realpath --relative-to="${build_source}/src" "$nc_stage")"
  if [[ ! -f "${build_source}/.altivec-configured" ]]; then
    printf 'Configuring Vim %s (tiny vi/xxd build)\n' "$VIM_VERSION"
    (
      cd "${build_source}/src"
      CC="$vim_cc_command" \
      AR="$macho_ar" \
      RANLIB="$macho_ranlib" \
      STRIP="$macho_strip" \
      CPPFLAGS="-I${nc_stage_rel}/include -I${nc_stage_rel}/include/ncursesw" \
      CFLAGS="$common_cflags" \
      LDFLAGS="${common_ldflags} -L${nc_stage_rel}/lib" \
      LIBS="-lncursesw" \
      vim_cv_uname_output=Darwin \
      vim_cv_uname_r=13.0.0 \
      vim_cv_uname_m=armv7 \
      vim_cv_toupper_broken=no \
      vim_cv_terminfo=yes \
      vim_cv_tgetent=zero \
      vim_cv_getcwd_broken=no \
      vim_cv_stat_ignores_slash=no \
      vim_cv_memmove_handles_overlap=yes \
      ./configure \
        --build="$("$cc" -dumpmachine)" \
        --host="$autoconf_host" \
        --prefix="$install_prefix" \
        --disable-darwin \
        --enable-gui=no \
        --without-x \
        --with-features=tiny \
        --with-tlib=ncursesw \
        --with-compiledby="Altivec Toolchain" \
        --disable-acl \
        --disable-channel \
        --disable-libsodium \
        --disable-netbeans \
        --disable-nls \
        --disable-selinux \
        --disable-xsmp
    )
    printf 'configured\n' > "${build_source}/.altivec-configured"
  fi
  printf 'Building Vim %s vi and xxd\n' "$VIM_VERSION"
  make -C "${build_source}/src" -j"$jobs" \
    CC="$vim_cc_command"
  [[ -x "${build_source}/src/vim" ]] || die "Vim vi implementation was not built"
  [[ -x "${build_source}/src/xxd/xxd" ]] || die "Vim xxd was not built"
}

build_htop() {
  local nc_stage="${component_root}/stage-ncurses-${NCURSES_VERSION}/${prefix_rel}"
  local build_source="${component_root}/build-htop-${HTOP_VERSION}"

  if [[ ! -f "${build_source}/configure" ]]; then
    mkdir -p "$build_source"
    cp -a "${htop_source}/." "$build_source/"
  fi
  if [[ ! -f "${build_source}/Makefile" ]]; then
    printf 'Configuring htop %s for Darwin\n' "$HTOP_VERSION"
    (
      cd "$build_source"
      CC="$cc_command" \
      AR="$macho_ar" \
      RANLIB="$macho_ranlib" \
      STRIP="$macho_strip" \
      CPPFLAGS="-D_DARWIN_C_SOURCE -I${nc_stage}/include -I${nc_stage}/include/ncursesw ${common_cppflags} -F${macos_compat_sdk}/System/Library/Frameworks" \
      CFLAGS="${common_cflags} -fcommon" \
      LDFLAGS="${common_ldflags} -L${nc_stage}/lib -F${sdk_dir}/System/Library/Frameworks" \
      LIBS="-framework IOKit -framework CoreFoundation" \
      ac_cv_func_malloc_0_nonnull=yes \
      ac_cv_func_realloc_0_nonnull=yes \
      ./configure \
        --build="$("$cc" -dumpmachine)" \
        --host="$autoconf_host" \
        --prefix="$install_prefix" \
        --disable-unicode \
        --disable-linux-affinity
    )
  fi
  printf 'Building htop %s\n' "$HTOP_VERSION"
  make -C "$build_source" -j"$jobs" \
    CFLAGS="${common_cflags} -fcommon"
  [[ -x "${build_source}/htop" ]] || die "htop was not built"
}

build_watch() {
  local nc_stage="${component_root}/stage-ncurses-${NCURSES_VERSION}/${prefix_rel}"
  local build="${component_root}/build-procps-${PROCPS_VERSION}"

  mkdir -p "$build"
  if [[ ! -f "${build}/Makefile" ]]; then
    printf 'Configuring procps-ng %s watch\n' "$PROCPS_VERSION"
    (
      cd "$build"
      CC="$cc_command" \
      AR="$macho_ar" \
      RANLIB="$macho_ranlib" \
      STRIP="$macho_strip" \
      CPPFLAGS="-D_DARWIN_C_SOURCE -I${nc_stage}/include -I${nc_stage}/include/ncursesw ${common_cppflags}" \
      CFLAGS="$common_cflags" \
      LDFLAGS="${common_ldflags} -L${nc_stage}/lib" \
      ac_cv_func_malloc_0_nonnull=yes \
      ac_cv_func_realloc_0_nonnull=yes \
      "${procps_source}/configure" \
        --build="$("$cc" -dumpmachine)" \
        --host="$autoconf_host" \
        --prefix="$install_prefix" \
        --disable-dependency-tracking \
        --disable-nls \
        --disable-shared \
        --enable-static \
        --disable-pidof \
        --disable-kill \
        --disable-rpath \
        --without-systemd \
        --without-elogind
    )
  fi
  printf 'Building procps-ng %s watch\n' "$PROCPS_VERSION"
  make -C "$build" -j"$jobs" watch
  [[ -x "${build}/watch" ]] || die "watch was not built"
}

sed_escape_replacement() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//&/\\&}"
  value="${value//|/\\|}"
  printf '%s\n' "$value"
}

build_man() {
  local build_source="${component_root}/build-mandoc-${MANDOC_VERSION}"
  local mandoc_cc=""
  local mandoc_cflags=""
  local mandoc_ldflags=""
  local escaped_cc=""
  local escaped_cflags=""
  local escaped_ldflags=""
  local escaped_prefix=""

  [[ -f "$zlib_static" ]] ||
    die "mandoc requires the target static zlib archive: ${zlib_static}"
  mandoc_cc="$cc_command"
  mandoc_cflags="${common_cflags} ${common_cppflags} -fgnu89-inline"
  mandoc_ldflags="${common_ldflags} -L$(dirname "$zlib_static")"
  escaped_cc="$(sed_escape_replacement "$mandoc_cc")"
  escaped_cflags="$(sed_escape_replacement "$mandoc_cflags")"
  escaped_ldflags="$(sed_escape_replacement "$mandoc_ldflags")"
  escaped_prefix="$(sed_escape_replacement "$install_prefix")"

  if [[ ! -f "${build_source}/configure" ]]; then
    mkdir -p "$build_source"
    cp -a "${mandoc_source}/." "$build_source/"
  fi
  if [[ ! -f "${build_source}/Makefile.local" ]]; then
    sed \
      -e "s|@CC@|${escaped_cc}|" \
      -e "s|@AR@|${macho_ar}|" \
      -e "s|@CFLAGS@|${escaped_cflags}|" \
      -e "s|@LDFLAGS@|${escaped_ldflags}|" \
      -e "s|@PREFIX@|${escaped_prefix}|g" \
      "$mandoc_config_template" > "${build_source}/configure.local"
    printf 'Configuring mandoc %s\n' "$MANDOC_VERSION"
    (
      cd "$build_source"
      ./configure
    )
  fi
  printf 'Building mandoc %s man\n' "$MANDOC_VERSION"
  make -C "$build_source" -j"$jobs" \
    CFLAGS="$mandoc_cflags" \
    mandoc
  [[ -x "${build_source}/mandoc" ]] || die "mandoc man implementation was not built"
}

build_host_man_indexer() {
  local build_source="${component_root}/build-mandoc-host-${MANDOC_VERSION}"

  if [[ ! -f "${build_source}/configure" ]]; then
    mkdir -p "$build_source"
    cp -a "${mandoc_source}/." "$build_source/"
  fi
  if [[ ! -f "${build_source}/Makefile.local" ]]; then
    printf 'Configuring host mandoc %s indexer\n' "$MANDOC_VERSION"
    (
      cd "$build_source"
      ./configure
    )
  fi
  printf 'Building host mandoc %s indexer\n' "$MANDOC_VERSION"
  make -C "$build_source" -j"$jobs" mandoc
  [[ -x "${build_source}/mandoc" ]] ||
    die "host mandoc indexer was not built"

  mkdir -p "$host_tools_dir"
  install -m 0755 "${build_source}/mandoc" "${host_tools_dir}/mandoc"
  ln -sfn mandoc "$host_man_indexer"
}

build_tree() {
  local build_source="${component_root}/build-tree-${TREE_VERSION}"

  if [[ ! -f "${build_source}/Makefile" ]]; then
    mkdir -p "$build_source"
    cp -a "${tree_source}/." "$build_source/"
  fi
  printf 'Building tree %s\n' "$TREE_VERSION"
  make -C "$build_source" -j"$jobs" \
    CC="$cc_command" \
    CFLAGS="${common_cflags} -std=c11 -Wall" \
    CPPFLAGS="-D_DARWIN_C_SOURCE" \
    LDFLAGS="$common_ldflags"
  [[ -x "${build_source}/tree" ]] || die "tree was not built"
}

darwin_compile() {
  "$cc" \
    --target="$target_triple" \
    -isysroot "$sdk_dir" \
    "-B${cctools_bin}" \
    -O2 \
    "-ffile-prefix-map=${repo_root}=." \
    "-fdebug-prefix-map=${repo_root}=." \
    "-fmacro-prefix-map=${repo_root}=." \
    "-miphoneos-version-min=${deployment_target}" \
    -idirafter "${macos_compat_sdk}/usr/include" \
    "$@"
}

build_darwin_tools() {
  local output="${component_root}/darwin-bin"
  local shell_source="$shell_cmds_source"
  local text_source="$text_cmds_source"
  local ps_source="${adv_cmds_source}/ps"
  local ping_source="${network_ping_source}/ping.tproj"
  local ifconfig_source="${network_ifconfig_source}/ifconfig.tproj"

  mkdir -p "$output"
  printf 'Building Apple and BSD Darwin-native tools\n'

  darwin_compile "${shell_source}/hostname/hostname.c" \
    -o "${output}/hostname"
  darwin_compile "${shell_source}/killall/killall.c" \
    -o "${output}/killall"
  darwin_compile "${shell_source}/which/which.c" \
    -o "${output}/which"
  darwin_compile \
    "${shell_source}/hexdump/conv.c" \
    "${shell_source}/hexdump/display.c" \
    "${shell_source}/hexdump/hexdump.c" \
    "${shell_source}/hexdump/hexsyntax.c" \
    "${shell_source}/hexdump/odsyntax.c" \
    "${shell_source}/hexdump/parse.c" \
    -o "${output}/hexdump"
  darwin_compile "${text_source}/wc/wc.c" \
    -o "${output}/wc"

  darwin_compile \
    -I"$ps_source" \
    "${ps_source}/fmt.c" \
    "${ps_source}/keyword.c" \
    "${ps_source}/nlist.c" \
    "${ps_source}/print.c" \
    "${ps_source}/ps.c" \
    "${ps_source}/tasks.c" \
    -o "${output}/ps"

  darwin_compile "$pkill_source" -o "${output}/pkill"

  darwin_compile \
    -DSO_TRAFFIC_CLASS=0x1086 \
    -DSO_RECV_TRAFFIC_CLASS=0x1087 \
    -DSO_RECV_ANYIF=0x1104 \
    -DIP_NO_IFT_CELLULAR=6969 \
    -DSO_TC_BK_SYS=100 \
    -DSO_TC_BK=200 \
    -DSO_TC_BE=0 \
    -DSO_TC_RD=300 \
    -DSO_TC_OAM=400 \
    -DSO_TC_AV=500 \
    -DSO_TC_RV=600 \
    -DSO_TC_VI=700 \
    -DSO_TC_VO=800 \
    -DSO_TC_CTL=900 \
    -I"$ping_source" \
    "${ping_source}/ping.c" \
    -o "${output}/ping"

  darwin_compile \
    -I"$ifconfig_source" \
    "${ifconfig_source}/ifconfig.c" \
    "${ifconfig_source}/ifmedia.c" \
    "${ifconfig_source}/af_inet.c" \
    "${ifconfig_source}/af_inet6.c" \
    "${ifconfig_source}/af_link.c" \
    "${ifconfig_source}/ifclone.c" \
    -o "${output}/ifconfig"

  darwin_compile \
    -I"$netcat_source" \
    "${netcat_source}/atomicio.c" \
    "${netcat_source}/netcat.c" \
    "${netcat_source}/socks.c" \
    -o "${output}/nc"

  darwin_compile '-D__FBSDID(x)=' "$logger_source" \
    -o "${output}/logger"
  darwin_compile '-D__FBSDID(x)=' "$realpath_source" \
    -o "${output}/realpath"

  for expected in \
    hostname killall which hexdump wc ps pkill ping ifconfig nc logger realpath; do
    [[ -x "${output}/${expected}" ]] ||
      die "Darwin-native tool was not built: ${expected}"
  done
}

install_man_if_present() {
  local source="$1"
  local destination="$2"
  if [[ -f "$source" ]]; then
    install -m 0644 "$source" "$destination"
  fi
}

write_extra_documentation() {
  local doc_dir="$1"
  local manifest="${doc_dir}/EXTRA-SOURCE-MANIFEST.txt"
  local notices="${doc_dir}/extra-tools-BSD-NOTICES.txt"

  {
    printf 'Additional Altivec command-line tools\n'
    printf 'Target: %s\n' "$target_triple"
    printf 'Minimum iOS: %s\n' "$deployment_target"
    printf 'Portable: diffutils %s, findutils %s, grep %s, sed %s, tar %s, gzip %s, bzip2 %s\n' \
      "$DIFFUTILS_VERSION" "$FINDUTILS_VERSION" "$GREP_VERSION" \
      "$SED_VERSION" "$TAR_VERSION" "$GZIP_VERSION" "$BZIP2_VERSION"
    printf 'Terminal: ncurses %s, less %s, Vim %s (tiny vi/xxd), htop %s, procps-ng watch %s, mandoc %s\n' \
      "$NCURSES_VERSION" "$LESS_VERSION" "$VIM_VERSION" "$HTOP_VERSION" \
      "$PROCPS_VERSION" "$MANDOC_VERSION"
    printf 'Darwin: shell_cmds %s, text_cmds %s (wc), adv_cmds %s, network_cmds ping %s, ifconfig %s, netcat %s\n' \
      "$SHELL_CMDS_VERSION" "$TEXT_CMDS_VERSION" "$ADV_CMDS_VERSION" \
      "$NETWORK_CMDS_PING_VERSION" "$NETWORK_CMDS_IFCONFIG_VERSION" \
      "$NETCAT_VERSION"
    printf 'Miscellaneous: tree %s, pkill-darwin %s, FreeBSD %s logger/realpath\n' \
      "$TREE_VERSION" "$PKILL_DARWIN_VERSION" "$FREEBSD_VERSION"
    printf 'netstat: not included; Apple sources require private, version-coupled kernel headers absent from the SDK.\n'
    printf 'ifconfig: core IPv4/IPv6/link/media support; bridge, bond, and VLAN modules omitted with their private headers.\n'
  } > "${doc_dir}/EXTRA-BUILD-INFO.txt"

  {
    printf '%s  %s\n' "$DIFFUTILS_SHA256" \
      "https://ftpmirror.gnu.org/diffutils/diffutils-${DIFFUTILS_VERSION}.tar.xz"
    printf '%s  %s\n' "$FINDUTILS_SHA256" \
      "https://ftpmirror.gnu.org/findutils/findutils-${FINDUTILS_VERSION}.tar.xz"
    printf '%s  %s\n' "$GREP_SHA256" \
      "https://ftpmirror.gnu.org/grep/grep-${GREP_VERSION}.tar.xz"
    printf '%s  %s\n' "$SED_SHA256" \
      "https://ftpmirror.gnu.org/sed/sed-${SED_VERSION}.tar.xz"
    printf '%s  %s\n' "$TAR_SHA256" \
      "https://ftpmirror.gnu.org/tar/tar-${TAR_VERSION}.tar.xz"
    printf '%s  %s\n' "$GZIP_SHA256" \
      "https://ftpmirror.gnu.org/gzip/gzip-${GZIP_VERSION}.tar.xz"
    printf '%s  %s\n' "$BZIP2_SHA256" \
      "https://sourceware.org/pub/bzip2/bzip2-${BZIP2_VERSION}.tar.gz"
    printf '%s  %s\n' "$NCURSES_SHA256" \
      "https://invisible-island.net/archives/ncurses/ncurses-${NCURSES_VERSION}.tar.gz"
    printf '%s  %s\n' "$LESS_SHA256" \
      "https://www.greenwoodsoftware.com/less/less-${LESS_VERSION}.tar.gz"
    printf '%s  %s\n' "$VIM_SHA256" \
      "https://github.com/vim/vim/archive/refs/tags/v${VIM_VERSION}.tar.gz"
    printf '%s  %s\n' "$HTOP_SHA256" \
      "https://hisham.hm/htop/releases/${HTOP_VERSION}/htop-${HTOP_VERSION}.tar.gz"
    printf '%s  %s\n' "$PROCPS_SHA256" \
      "https://sourceforge.net/projects/procps-ng/files/Production/procps-ng-${PROCPS_VERSION}.tar.xz/download"
    printf '%s  %s\n' "$MANDOC_SHA256" \
      "https://mandoc.bsd.lv/snapshots/mandoc-${MANDOC_VERSION}.tar.gz"
    printf '%s  %s\n' "$TREE_SHA256" \
      "https://gitlab.com/OldManProgrammer/unix-tree/-/archive/${TREE_VERSION}/unix-tree-${TREE_VERSION}.tar.gz"
    printf '%s  %s\n' "$SHELL_CMDS_SHA256" \
      "https://github.com/apple-oss-distributions/shell_cmds/archive/refs/tags/shell_cmds-${SHELL_CMDS_VERSION}.tar.gz"
    printf '%s  %s\n' "$TEXT_CMDS_SHA256" \
      "https://github.com/apple-oss-distributions/text_cmds/archive/refs/tags/text_cmds-${TEXT_CMDS_VERSION}.tar.gz"
    printf '%s  %s\n' "$ADV_CMDS_SHA256" \
      "https://github.com/apple-oss-distributions/adv_cmds/archive/refs/tags/adv_cmds-${ADV_CMDS_VERSION}.tar.gz"
    printf '%s  %s\n' "$NETWORK_CMDS_PING_SHA256" \
      "https://github.com/apple-oss-distributions/network_cmds/archive/refs/tags/network_cmds-${NETWORK_CMDS_PING_VERSION}.tar.gz"
    printf '%s  %s\n' "$NETWORK_CMDS_IFCONFIG_SHA256" \
      "https://github.com/apple-oss-distributions/network_cmds/archive/refs/tags/network_cmds-${NETWORK_CMDS_IFCONFIG_VERSION}.tar.gz"
    printf '%s  %s\n' "$NETCAT_SHA256" \
      "https://github.com/apple-oss-distributions/netcat/archive/refs/tags/netcat-${NETCAT_VERSION}.tar.gz"
    printf '%s  %s\n' "$PKILL_DARWIN_SHA256" \
      "https://sourceforge.net/p/pkilldarwin/code/ci/default/tree/pkill.c?format=raw"
    printf '%s  %s\n' "$PKILL_DARWIN_MAN_SHA256" \
      "https://sourceforge.net/p/pkilldarwin/code/ci/default/tree/pkill.1?format=raw"
    printf '%s  %s\n' "$FREEBSD_LOGGER_SHA256" \
      "https://raw.githubusercontent.com/freebsd/freebsd-src/release/10.2.0/usr.bin/logger/logger.c"
    printf '%s  %s\n' "$FREEBSD_LOGGER_MAN_SHA256" \
      "https://raw.githubusercontent.com/freebsd/freebsd-src/release/10.2.0/usr.bin/logger/logger.1"
    printf '%s  %s\n' "$FREEBSD_REALPATH_SHA256" \
      "https://raw.githubusercontent.com/freebsd/freebsd-src/release/10.2.0/bin/realpath/realpath.c"
    printf '%s  %s\n' "$FREEBSD_REALPATH_MAN_SHA256" \
      "https://raw.githubusercontent.com/freebsd/freebsd-src/release/10.2.0/bin/realpath/realpath.1"
  } > "$manifest"

  install -m 0644 "${diffutils_source}/COPYING" "${doc_dir}/diffutils-COPYING"
  install -m 0644 "${findutils_source}/COPYING" "${doc_dir}/findutils-COPYING"
  install -m 0644 "${grep_source}/COPYING" "${doc_dir}/grep-COPYING"
  install -m 0644 "${sed_source}/COPYING" "${doc_dir}/sed-COPYING"
  install -m 0644 "${tar_source}/COPYING" "${doc_dir}/tar-COPYING"
  install -m 0644 "${gzip_source}/COPYING" "${doc_dir}/gzip-COPYING"
  install -m 0644 "${bzip2_source}/LICENSE" "${doc_dir}/bzip2-LICENSE"
  install -m 0644 "${ncurses_source}/COPYING" "${doc_dir}/ncurses-COPYING"
  install -m 0644 "${less_source}/LICENSE" "${doc_dir}/less-LICENSE"
  install -m 0644 "${vim_source}/LICENSE" "${doc_dir}/vim-LICENSE"
  install -m 0644 "${htop_source}/COPYING" "${doc_dir}/htop-COPYING"
  install -m 0644 "${procps_source}/COPYING" "${doc_dir}/procps-COPYING"
  install -m 0644 "${procps_source}/COPYING.LIB" "${doc_dir}/procps-COPYING.LIB"
  install -m 0644 "${mandoc_source}/LICENSE" "${doc_dir}/mandoc-LICENSE"
  install -m 0644 "${tree_source}/LICENSE" "${doc_dir}/tree-LICENSE"
  install -m 0644 "${network_ping_source}/APPLE_LICENSE" \
    "${doc_dir}/network_cmds-APPLE_LICENSE"

  {
    for notice_source in \
      "${shell_cmds_source}/hostname/hostname.c" \
      "${shell_cmds_source}/killall/killall.c" \
      "${shell_cmds_source}/hexdump/hexdump.c" \
      "${shell_cmds_source}/which/which.c" \
      "${text_cmds_source}/wc/wc.c" \
      "${adv_cmds_source}/ps/ps.c" \
      "${network_ping_source}/ping.tproj/ping.c" \
      "${network_ifconfig_source}/ifconfig.tproj/ifconfig.c" \
      "${netcat_source}/netcat.c" \
      "$pkill_source" \
      "$logger_source" \
      "$realpath_source"; do
      printf '\n===== %s =====\n' "${notice_source##*/}"
      sed -n '1,80p' "$notice_source"
    done
  } > "$notices"
}

assemble_stage() {
  local bin_dir=""
  local man1_dir=""
  local doc_dir=""
  local nc_stage="${component_root}/stage-ncurses-${NCURSES_VERSION}/${prefix_rel}"
  local vim_build="${component_root}/build-vim-${VIM_VERSION}"
  local htop_build="${component_root}/build-htop-${HTOP_VERSION}"
  local watch_build="${component_root}/build-procps-${PROCPS_VERSION}"
  local mandoc_build="${component_root}/build-mandoc-${MANDOC_VERSION}"
  local tree_build="${component_root}/build-tree-${TREE_VERSION}"
  local darwin_bin="${component_root}/darwin-bin"

  safe_remove_component "$component_stage"
  bin_dir="${stage_prefix}/bin"
  man1_dir="${stage_prefix}/share/man/man1"
  doc_dir="${stage_prefix}/share/doc/altivec-toolchain"
  mkdir -p "$bin_dir" "$man1_dir" "$doc_dir" "${stage_prefix}/share"

  install -m 0755 \
    "${component_root}/stage-diffutils-${DIFFUTILS_VERSION}/${prefix_rel}/bin/diff" \
    "${bin_dir}/diff"
  install -m 0755 \
    "${component_root}/stage-diffutils-${DIFFUTILS_VERSION}/${prefix_rel}/bin/cmp" \
    "${bin_dir}/cmp"
  install -m 0755 \
    "${component_root}/stage-diffutils-${DIFFUTILS_VERSION}/${prefix_rel}/bin/diff3" \
    "${bin_dir}/diff3"
  install -m 0755 \
    "${component_root}/stage-findutils-${FINDUTILS_VERSION}/${prefix_rel}/bin/find" \
    "${bin_dir}/find"
  install -m 0755 \
    "${component_root}/stage-findutils-${FINDUTILS_VERSION}/${prefix_rel}/bin/xargs" \
    "${bin_dir}/xargs"
  install -m 0755 \
    "${component_root}/stage-grep-${GREP_VERSION}/${prefix_rel}/bin/grep" \
    "${bin_dir}/grep"
  install -m 0755 \
    "${component_root}/stage-sed-${SED_VERSION}/${prefix_rel}/bin/sed" \
    "${bin_dir}/sed"
  install -m 0755 \
    "${component_root}/stage-tar-${TAR_VERSION}/${prefix_rel}/bin/tar" \
    "${bin_dir}/tar"
  install -m 0755 \
    "${component_root}/stage-gzip-${GZIP_VERSION}/${prefix_rel}/bin/gzip" \
    "${bin_dir}/gzip"
  install -m 0755 \
    "${component_root}/build-bzip2-${BZIP2_VERSION}/bzip2" \
    "${bin_dir}/bzip2"

  install -m 0755 "${nc_stage}/bin/clear" "${bin_dir}/clear"
  install -m 0755 "${nc_stage}/bin/tset" "${bin_dir}/reset"
  cp -a "${nc_stage}/share/terminfo" "${stage_prefix}/share/terminfo"
  install -m 0755 \
    "${component_root}/stage-less-${LESS_VERSION}/${prefix_rel}/bin/less" \
    "${bin_dir}/less"
  install -m 0755 "${vim_build}/src/vim" "${bin_dir}/vi"
  install -m 0755 "${vim_build}/src/xxd/xxd" "${bin_dir}/xxd"
  install -m 0755 "${htop_build}/htop" "${bin_dir}/htop"
  install -m 0755 "${watch_build}/watch" "${bin_dir}/watch"
  install -m 0755 "${mandoc_build}/mandoc" "${bin_dir}/man"
  install -m 0755 "${tree_build}/tree" "${bin_dir}/tree"

  for command in \
    hostname killall which hexdump wc ps pkill ping ifconfig nc logger realpath; do
    install -m 0755 "${darwin_bin}/${command}" "${bin_dir}/${command}"
  done
  ln -s pkill "${bin_dir}/pgrep"

  for manual in diff cmp diff3; do
    install_man_if_present \
      "${component_root}/stage-diffutils-${DIFFUTILS_VERSION}/${prefix_rel}/share/man/man1/${manual}.1" \
      "${man1_dir}/${manual}.1"
  done
  for manual in find xargs; do
    install_man_if_present \
      "${component_root}/stage-findutils-${FINDUTILS_VERSION}/${prefix_rel}/share/man/man1/${manual}.1" \
      "${man1_dir}/${manual}.1"
  done
  install_man_if_present \
    "${component_root}/stage-grep-${GREP_VERSION}/${prefix_rel}/share/man/man1/grep.1" \
    "${man1_dir}/grep.1"
  install_man_if_present \
    "${component_root}/stage-sed-${SED_VERSION}/${prefix_rel}/share/man/man1/sed.1" \
    "${man1_dir}/sed.1"
  install_man_if_present \
    "${component_root}/stage-tar-${TAR_VERSION}/${prefix_rel}/share/man/man1/tar.1" \
    "${man1_dir}/tar.1"
  install_man_if_present \
    "${component_root}/stage-gzip-${GZIP_VERSION}/${prefix_rel}/share/man/man1/gzip.1" \
    "${man1_dir}/gzip.1"
  install_man_if_present "${bzip2_source}/bzip2.1" "${man1_dir}/bzip2.1"
  install_man_if_present "${nc_stage}/share/man/man1/clear.1" "${man1_dir}/clear.1"
  install_man_if_present "${nc_stage}/share/man/man1/tset.1" "${man1_dir}/reset.1"
  install_man_if_present \
    "${component_root}/stage-less-${LESS_VERSION}/${prefix_rel}/share/man/man1/less.1" \
    "${man1_dir}/less.1"
  install_man_if_present "${vim_source}/runtime/doc/vim.1" "${man1_dir}/vi.1"
  install_man_if_present "${vim_source}/runtime/doc/xxd.1" "${man1_dir}/xxd.1"
  install_man_if_present "${htop_build}/htop.1" "${man1_dir}/htop.1"
  install_man_if_present "${procps_source}/watch.1" "${man1_dir}/watch.1"
  install_man_if_present "${mandoc_source}/man.1" "${man1_dir}/man.1"
  install_man_if_present "${tree_source}/doc/tree.1" "${man1_dir}/tree.1"
  install_man_if_present "${shell_cmds_source}/hostname/hostname.1" \
    "${man1_dir}/hostname.1"
  install_man_if_present "${shell_cmds_source}/killall/killall.1" \
    "${man1_dir}/killall.1"
  install_man_if_present "${shell_cmds_source}/which/which.1" \
    "${man1_dir}/which.1"
  install_man_if_present "${shell_cmds_source}/hexdump/hexdump.1" \
    "${man1_dir}/hexdump.1"
  install_man_if_present "${text_cmds_source}/wc/wc.1" "${man1_dir}/wc.1"
  install_man_if_present "${adv_cmds_source}/ps/ps.1" "${man1_dir}/ps.1"
  install_man_if_present "$pkill_man" "${man1_dir}/pkill.1"
  ln -s pkill.1 "${man1_dir}/pgrep.1"
  install_man_if_present "${network_ping_source}/ping.tproj/ping.8" \
    "${man1_dir}/ping.1"
  install_man_if_present "${network_ifconfig_source}/ifconfig.tproj/ifconfig.8" \
    "${man1_dir}/ifconfig.1"
  install_man_if_present "${netcat_source}/nc.1" "${man1_dir}/nc.1"
  install_man_if_present "$logger_man" "${man1_dir}/logger.1"
  install_man_if_present "$realpath_man" "${man1_dir}/realpath.1"

  "$host_man_indexer" "${stage_prefix}/share/man"
  write_extra_documentation "$doc_dir"
}

verify_stage() {
  local bin_dir="${stage_prefix}/bin"
  local expected=""
  local actual=""
  local binary=""
  local description=""
  local load_commands=""
  local deployment_major="${deployment_target%%.*}"
  local unsupported_symbol=""
  local -a expected_tools=(
    bzip2 clear cmp diff diff3 find grep hexdump hostname htop ifconfig
    killall less logger man nc pgrep ping pkill ps realpath reset sed tar
    tree vi watch wc which xargs xxd gzip
  )

  for expected in "${expected_tools[@]}"; do
    [[ -x "${bin_dir}/${expected}" ]] ||
      die "staged extra tool is missing: ${bin_dir}/${expected}"
  done
  actual="$(
    find "$bin_dir" -mindepth 1 -maxdepth 1 \( -type f -o -type l \) \
      -printf '%f\n' | LC_ALL=C sort
  )"
  expected="$(printf '%s\n' "${expected_tools[@]}" | LC_ALL=C sort)"
  [[ "$actual" == "$expected" ]] ||
    die "extra stage contains an unapproved or missing command"

  while IFS= read -r -d '' binary; do
    description="$(file "$binary")"
    [[ "$description" == *"Mach-O armv7 executable"* ]] ||
      die "extra tool has an unexpected format: ${binary}"
    load_commands="$("$macho_otool" -l "$binary")"
    awk -v expected="$deployment_target" '
      $1 == "cmd" && $2 == "LC_VERSION_MIN_IPHONEOS" {
        in_version = 1
        next
      }
      in_version && $1 == "version" {
        if ($2 == expected) found = 1
        in_version = 0
      }
      END { exit(found ? 0 : 1) }
    ' <<< "$load_commands" ||
      die "extra tool has the wrong deployment target: ${binary}"

    if ((10#$deployment_major < 8)); then
      unsupported_symbol="$(
        "$macho_otool" -Iv "$binary" |
          awk '
            $NF ~ /^_(faccessat|fchmodat|fchownat|fdopendir|fstatat|linkat|mkdirat|openat|readlinkat|renameat|symlinkat|unlinkat)$/ {
              print $NF
              exit
            }
          '
      )"
      [[ -z "$unsupported_symbol" ]] ||
        die "extra tool imports ${unsupported_symbol}, which requires iOS 8.0: ${binary}"
    fi
  done < <(find "$bin_dir" -type f -perm /111 -print0)

  [[ -d "${stage_prefix}/share/terminfo" ]] ||
    die "terminal tools are missing the staged terminfo database"
  [[ -x "$host_man_indexer" ]] ||
    die "host manual-page indexer is missing: ${host_man_indexer}"
  [[ -s "${stage_prefix}/share/man/mandoc.db" ]] ||
    die "staged manual-page index is missing"
}

build_all() {
  if [[ -f "$completed_marker" ]]; then
    verify_stage
    printf 'Extra tools already built: %s\n' "$component_stage"
    return 0
  fi

  build_portable_tools
  build_ncurses
  build_less
  build_vim
  build_htop
  build_watch
  build_man
  build_host_man_indexer
  build_tree
  build_darwin_tools
  assemble_stage
  verify_stage
  printf 'complete\n' > "$completed_marker"
  printf 'Staged extra tools: %s\n' "$component_stage"
}

prepare_sources

case "$action" in
  source)
    printf 'Pinned extra-tool sources are available under %s\n' "$sources_dir"
    ;;
  stage)
    prepare_component
    build_all
    ;;
  verify)
    validate_component_cache
    printf 'Verified cached extra tools: %s\n' "$component_stage"
    ;;
esac
