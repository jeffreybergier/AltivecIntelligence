#!/usr/bin/env bash

set -euo pipefail

# Try each verified source independently before moving to its mirror.
readonly SOURCE_DOWNLOAD_ATTEMPTS=3

readonly CCTOOLS_VERSION="949.0.1"
readonly LD64_VERSION="530"
readonly CCTOOLS_COMMIT="b7230b3319891168397eae1c8f23670f48a6d1c1"
readonly CCTOOLS_ARCHIVE_SHA256="8d2246db6dcbfde5e59e8095823f6b711f0906bf78e60423d3d7b595a0ed10d7"

readonly LDID_VERSION="2.1.5-procursus7"
readonly LDID_COMMIT="aaf8f23d7975ecdb8e77e3a8f22253e0a2352cef"
readonly LDID_ARCHIVE_SHA256="5419d15fe665b956fe79f55ea79661965375888fc4d2fd8cae6dcded63ee2710"

readonly LIBPLIST_VERSION="2.7.0"
readonly LIBPLIST_ARCHIVE_SHA256="7ac42301e896b1ebe3c654634780c82baa7cb70df8554e683ff89f7c2643eb8b"

readonly OPENSSL_VERSION="3.6.3"
readonly OPENSSL_ARCHIVE_SHA256="243a86649cf6f23eeb6a2ff2456e09e5d77dd9018a54d3d96b0c6bdd6ba6c7f1"

readonly ZIP_VERSION="3.0"
readonly ZIP_DEBIAN_REVISION="15"
readonly ZIP_ARCHIVE_SHA256="f0e8bb1f9b7eb0b01285495a2699df3a4b766784c1765a8f1aeedf63c0806369"
readonly ZIP_DEBIAN_ARCHIVE_SHA256="6dc1711c67640e8d1dee867ff53e84387ddb980c40885bd088ac98c330bffce9"

readonly UNZIP_VERSION="6.0"
readonly UNZIP_DEBIAN_REVISION="29"
readonly UNZIP_ARCHIVE_SHA256="036d96991646d0449ed0aa952e4fbe21b476ce994abc276e49d30e686708bd37"
readonly UNZIP_DEBIAN_ARCHIVE_SHA256="14043e5ea351c02b3bc8676e1e6d20d79b9a690b6d7520e8138ac629cc048417"

readonly ZLIB_VERSION="1.3.2"
readonly ZLIB_ARCHIVE_SHA256="d7a0654783a4da529d1bb793b7ad9c3318020af77667bcae35f95d0e42a792f3"

readonly CURL_VERSION="8.21.0"
readonly CURL_ARCHIVE_SHA256="aa1b66a70eace83dc624508745646c08ae561de512ab403adffb93ac87fc72e6"
readonly CA_BUNDLE_DATE="2026-07-16"
readonly CA_BUNDLE_SHA256="3ff344e30b9b1ed2971044eabb438a08f2e2245ddb5f8ab1a3ad8b63ab4eaf91"

readonly GIT_VERSION="2.55.0"
readonly GIT_ARCHIVE_SHA256="457fdb04dc8728e007d4688695e6912e6f680727920f2a40bf11eacc17505357"

readonly LIBPNG_VERSION="1.6.58"
readonly LIBPNG_ARCHIVE_SHA256="28eb403f51f0f7405249132cecfe82ea5c0ef97f1b32c5a65828814ae0d34775"

readonly LIBJPEG_TURBO_VERSION="3.1.4.1"
readonly LIBJPEG_TURBO_ARCHIVE_SHA256="ecae8008e2cc9ade2f2c1bb9d5e6d4fb73e7c433866a056bd82980741571a022"

readonly IMAGEMAGICK_VERSION="7.1.2-27"
readonly IMAGEMAGICK_BASE_VERSION="${IMAGEMAGICK_VERSION%-*}"
readonly IMAGEMAGICK_ARCHIVE_SHA256="485dad5226fda2417ea65f3eb6e3f63e7d5dfacacdf6f57f9c39b6ef1e3cb667"

readonly GNU_MAKE_VERSION="4.4.1"
readonly GNU_MAKE_ARCHIVE_SHA256="dd16fb1d67bfab79a72f5e8390735c49e3e8e70b4945a15ab1f81ddb78658fb3"

readonly FILE_VERSION="5.48"
readonly FILE_ARCHIVE_SHA256="ed14656883b23a364b4057c05595d93252da9bc473d30106519519d0da141283"

readonly AWK_VERSION="20260426"
readonly AWK_COMMIT="5739fd79bcfc75ba7526773d0cf634521f8aca3c"
readonly AWK_ARCHIVE_SHA256="7ae5b9fc6a8149bc45ea0ba3ba434a69a16d1460d19f6d01b6f04cc885b8e02b"

readonly PATCH_VERSION="2.8"
readonly PATCH_ARCHIVE_SHA256="f87cee69eec2b4fcbf60a396b030ad6aa3415f192aa5f7ee84cad5e11f7f5ae3"

readonly JQ_VERSION="1.8.2"
readonly JQ_ARCHIVE_SHA256="71b8d6e8f5fe81f6c6d0d110e3892251f6ce76ed095abd315e26e6e1193af3af"

readonly XZ_VERSION="5.8.3"
readonly XZ_ARCHIVE_SHA256="fff1ffcf2b0da84d308a14de513a1aa23d4e9aa3464d17e64b9714bfdd0bbfb6"

readonly SQLITE_VERSION="3.43.2"
readonly SQLITE_AMALGAMATION_VERSION="3430200"
readonly SQLITE_YEAR="2023"
readonly SQLITE_ARCHIVE_SHA256="a17ac8792f57266847d57651c5259001d1e4e4b46be96ec0d985c953925b2a1c"

readonly CCTOOLS_PROGRAM_PREFIX="arm-apple-darwin11-"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "${script_dir}/.." && pwd -P)"
readonly cctools_patch="${script_dir}/cctools-ld64-armv7-atomic-alignment.patch"
readonly cctools_ios43_patch="${script_dir}/cctools-ld64-ios43-deployment-floor.patch"
readonly imagemagick_patch="${script_dir}/imagemagick-ios-target-conditionals.patch"
readonly gnu_make_patch="${script_dir}/make-ios-portable-ar-header.patch"
readonly jq_patch="${script_dir}/jq-ios6-exp10.patch"
readonly imagemagick_policy="${script_dir}/imagemagick-policy.xml"
readonly imagemagick_delegates="${script_dir}/imagemagick-delegates.xml"
readonly extra_tools_builder="${script_dir}/build-extra-tools.sh"
readonly extra_ps_patch="${script_dir}/adv-cmds-ps-ios-workqueue.patch"
readonly mandoc_config_template="${script_dir}/mandoc-ios-configure.local.in"

action="package"
if (($# > 0)) && [[ "$1" != -* ]]; then
  action="$1"
  shift
fi

work_dir="${repo_root}/build-release/Intermediates/core-tools-armv7"
archives_dir_input=""
sources_dir_input=""
sdk_dir="/osxcross/target/SDK/iPhoneOS8.4.sdk"
cctools_bin="/osxcross/target/bin"
deployment_target="6.0"
jobs="2"
install_prefix="/var/altivec"
cc="/usr/bin/clang-14"
cxx="/usr/bin/clang++-14"
ldid_signer="ldid"

usage() {
  printf '%s\n' \
    "Usage: $(basename "$0") [action] [options]" \
    "" \
    "Actions:" \
    "  source       Download and verify all pinned source archives." \
    "  cctools      Build cctools ${CCTOOLS_VERSION} and ld64 ${LD64_VERSION}." \
    "  libplist     Build static libplist ${LIBPLIST_VERSION} and plistutil." \
    "  openssl      Build OpenSSL ${OPENSSL_VERSION} CLI and private static libraries." \
    "  ldid         Build ldid ${LDID_VERSION} and its dependencies." \
    "  zip          Build Info-ZIP ${ZIP_VERSION} with Debian revision ${ZIP_DEBIAN_REVISION} patches." \
    "  unzip        Build Info-ZIP UnZip ${UNZIP_VERSION} with Debian revision ${UNZIP_DEBIAN_REVISION} patches." \
    "  zlib         Build the private static zlib ${ZLIB_VERSION} dependency." \
    "  curl         Build curl ${CURL_VERSION}, static OpenSSL, and the CA bundle." \
    "  git          Build Git ${GIT_VERSION} with SSH and HTTPS transports." \
    "  libpng       Build static libpng ${LIBPNG_VERSION}." \
    "  libjpeg      Build static libjpeg-turbo ${LIBJPEG_TURBO_VERSION}." \
    "  imagemagick  Build ImageMagick ${IMAGEMAGICK_VERSION} Q8 with PNG and JPEG." \
    "  make         Build GNU Make ${GNU_MAKE_VERSION}." \
    "  file         Build file/libmagic ${FILE_VERSION}." \
    "  awk          Build One True Awk ${AWK_VERSION}." \
    "  patch        Build GNU patch ${PATCH_VERSION}." \
    "  jq           Build jq ${JQ_VERSION} with its static regex engine." \
    "  xz           Build XZ Utils ${XZ_VERSION}." \
    "  sqlite       Build SQLite ${SQLITE_VERSION} CLI and static library." \
    "  extra        Build the approved shell, process, network, and manual tools." \
    "  stage        Build, strip, pseudo-sign, and stage all tools." \
    "  verify       Build and validate the staged ARMv7 payload." \
    "  package      Build the verified relocatable payload archive (default)." \
    "  package-from-cache  Reassemble and package existing component stages without building." \
    "" \
    "Options:" \
    "  --work-dir <path>          Generated build state." \
    "  --archives-dir <path>      Downloaded source archives." \
    "  --sources-dir <path>       Extracted source trees." \
    "  --sdk <path>               iPhoneOS SDK." \
    "  --cctools-bin <path>       Host Mach-O tools and Apple linker." \
    "  --deployment-target <ver>  Minimum iOS version (default: 6.0)." \
    "  --jobs <count>             Parallel build jobs (default: 2)." \
    "  --prefix <path>            Phone installation prefix." \
    "  --cc <path>                Modern host Clang C compiler." \
    "  --cxx <path>               Modern host Clang C++ compiler." \
    "  --ldid <path>              Host ldid used to sign staged binaries." \
    "  -h, --help                 Show this help."
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
      archives_dir_input="$2"
      shift 2
      ;;
    --sources-dir)
      (($# >= 2)) || die "--sources-dir requires a value"
      sources_dir_input="$2"
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
    --cxx)
      (($# >= 2)) || die "--cxx requires a value"
      cxx="$2"
      shift 2
      ;;
    --ldid)
      (($# >= 2)) || die "--ldid requires a value"
      ldid_signer="$2"
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
  source|cctools|libplist|openssl|ldid|zip|unzip|zlib|curl|git|libpng|libjpeg|imagemagick|make|file|awk|patch|jq|xz|sqlite|extra|stage|verify|package|package-from-cache)
    ;;
  *)
    die "unknown action: ${action}"
    ;;
esac

[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive integer"
[[ "$deployment_target" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
  die "--deployment-target must be a version such as 6.0"
[[ "$install_prefix" == /* && "$install_prefix" != "/" &&
  "$install_prefix" != */ ]] ||
  die "--prefix must be an absolute path other than / without a trailing slash"

work_dir="$(realpath -m "$work_dir")"
if [[ -n "$archives_dir_input" ]]; then
  archives_dir="$(realpath -m "$archives_dir_input")"
else
  archives_dir="${repo_root}/build-release/Intermediates/Archives"
fi
if [[ -n "$sources_dir_input" ]]; then
  sources_dir="$(realpath -m "$sources_dir_input")"
else
  sources_dir="${work_dir}/sources"
fi
sdk_dir="$(realpath -m "$sdk_dir")"
cctools_bin="$(realpath -m "$cctools_bin")"

case "${work_dir}/" in
  "${repo_root}/"*)
    case "${work_dir}/" in
      "${repo_root}/build-release/Intermediates/"*)
        ;;
      *)
        die "in-repo work directories must be under build-release/Intermediates"
        ;;
    esac
    ;;
esac

for generated_dir in "$archives_dir" "$sources_dir"; do
  [[ "$generated_dir" != "/" ]] || die "generated directories cannot be /"
  case "${generated_dir}/" in
    "${repo_root}/"*)
      case "${generated_dir}/" in
        "${repo_root}/build-release/Intermediates/"*)
          ;;
        *)
          die "in-repo generated directories must be under build-release/Intermediates"
          ;;
      esac
      ;;
  esac
done
[[ "$archives_dir" != "$sources_dir" ]] ||
  die "archive and extracted-source directories must differ"
[[ -d "$sdk_dir" ]] || die "iPhoneOS SDK not found: ${sdk_dir}"

resolve_tool() {
  local requested="$1"
  local resolved=""

  if [[ "$requested" == */* ]]; then
    [[ -x "$requested" ]] || return 1
    if [[ "$requested" == /* ]]; then
      printf '%s\n' "$requested"
    else
      printf '%s/%s\n' \
        "$(cd "$(dirname "$requested")" && pwd -P)" \
        "$(basename "$requested")"
    fi
    return
  fi

  resolved="$(command -v "$requested" 2>/dev/null)" || return 1
  printf '%s\n' "$resolved"
}

cc="$(resolve_tool "$cc")" || die "C compiler not found: ${cc}"
cxx="$(resolve_tool "$cxx")" || die "C++ compiler not found: ${cxx}"
ldid_signer="$(resolve_tool "$ldid_signer")" ||
  die "host ldid not found: ${ldid_signer}"
pkg_config="$(resolve_tool pkg-config)" ||
  die "pkg-config not found"
readonly pkg_config

readonly macho_ar="${cctools_bin}/x86_64-apple-darwin9-ar"
readonly macho_ranlib="${cctools_bin}/x86_64-apple-darwin9-ranlib"
readonly macho_nm="${cctools_bin}/x86_64-apple-darwin9-nm"
readonly macho_strip="${cctools_bin}/x86_64-apple-darwin9-strip"
readonly macho_otool="${cctools_bin}/x86_64-apple-darwin9-otool"

for required_tool in \
  bash bison cmake curl unzip tar patch make perl sha256sum realpath file \
  readlink strings "$cc" "$cxx" "$ldid_signer" "$pkg_config" \
  "$macho_ar" "$macho_ranlib" "$macho_nm" "$macho_strip" "$macho_otool"; do
  if [[ "$required_tool" == */* ]]; then
    [[ -x "$required_tool" ]] || die "required tool not executable: ${required_tool}"
  else
    command -v "$required_tool" >/dev/null 2>&1 ||
      die "required tool not found: ${required_tool}"
  fi
done

for required_file in \
  "$cctools_patch" "$cctools_ios43_patch" \
  "$imagemagick_patch" "$gnu_make_patch" "$jq_patch" \
  "$imagemagick_policy" "$imagemagick_delegates" \
  "$extra_tools_builder" "$extra_ps_patch" "$mandoc_config_template"; do
  [[ -f "$required_file" ]] || die "required build input is missing: ${required_file}"
done

mkdir -p "$work_dir" "$archives_dir" "$sources_dir"

readonly target_triple="armv7-apple-ios${deployment_target}"
readonly autoconf_host="armv7-apple-darwin11"
readonly autoconf_target="arm-apple-darwin11"
install_prefix_tag="${install_prefix#/}"
install_prefix_tag="${install_prefix_tag//\//-}"
[[ "$install_prefix_tag" =~ ^[A-Za-z0-9._+-]+$ ]] ||
  die "install prefix cannot be represented safely in the artifact name"
readonly install_prefix_tag
readonly package_name="altivec-toolchain-core-tools-armv7-ios${deployment_target}-${install_prefix_tag}"
readonly sdk_name="${sdk_dir##*/}"
if [[ "$sdk_name" =~ ^iPhoneOS([0-9]+([.][0-9]+)*)[.]sdk$ ]]; then
  sdk_version="${BASH_REMATCH[1]}"
else
  die "cannot determine SDK version from directory name: ${sdk_name}"
fi
readonly sdk_version
build_triple="$("$cc" -dumpmachine)"
readonly build_triple
readonly prefix_rel="${install_prefix#/}"

readonly cctools_archive="${archives_dir}/cctools-port-${CCTOOLS_COMMIT}.zip"
readonly cctools_source="${sources_dir}/cctools-port-${CCTOOLS_COMMIT}"
readonly ldid_archive="${archives_dir}/ldid-${LDID_COMMIT}.zip"
readonly ldid_source="${sources_dir}/ldid-${LDID_COMMIT}"
readonly libplist_archive="${archives_dir}/libplist-${LIBPLIST_VERSION}.tar.bz2"
readonly libplist_source="${sources_dir}/libplist-${LIBPLIST_VERSION}"
readonly openssl_archive="${archives_dir}/openssl-${OPENSSL_VERSION}.tar.gz"
readonly openssl_source="${sources_dir}/openssl-${OPENSSL_VERSION}"
readonly zip_archive="${archives_dir}/zip_${ZIP_VERSION}.orig.tar.gz"
readonly zip_debian_archive="${archives_dir}/zip_${ZIP_VERSION}-${ZIP_DEBIAN_REVISION}.debian.tar.xz"
readonly zip_source="${sources_dir}/zip-${ZIP_VERSION}-debian${ZIP_DEBIAN_REVISION}"
readonly unzip_archive="${archives_dir}/unzip_${UNZIP_VERSION}.orig.tar.gz"
readonly unzip_debian_archive="${archives_dir}/unzip_${UNZIP_VERSION}-${UNZIP_DEBIAN_REVISION}.debian.tar.xz"
readonly unzip_source="${sources_dir}/unzip-${UNZIP_VERSION}-debian${UNZIP_DEBIAN_REVISION}"
readonly zlib_archive="${archives_dir}/zlib-${ZLIB_VERSION}.tar.xz"
readonly zlib_source="${sources_dir}/zlib-${ZLIB_VERSION}"
readonly curl_archive="${archives_dir}/curl-${CURL_VERSION}.tar.xz"
readonly curl_source="${sources_dir}/curl-${CURL_VERSION}"
readonly ca_bundle="${archives_dir}/cacert-${CA_BUNDLE_DATE}.pem"
readonly git_archive="${archives_dir}/git-${GIT_VERSION}.tar.xz"
readonly git_source="${sources_dir}/git-${GIT_VERSION}"
readonly libpng_archive="${archives_dir}/libpng-${LIBPNG_VERSION}.tar.xz"
readonly libpng_source="${sources_dir}/libpng-${LIBPNG_VERSION}"
readonly libjpeg_archive="${archives_dir}/libjpeg-turbo-${LIBJPEG_TURBO_VERSION}.tar.gz"
readonly libjpeg_source="${sources_dir}/libjpeg-turbo-${LIBJPEG_TURBO_VERSION}"
readonly imagemagick_archive="${archives_dir}/ImageMagick-${IMAGEMAGICK_VERSION}.tar.gz"
readonly imagemagick_source="${sources_dir}/ImageMagick-${IMAGEMAGICK_VERSION}"
readonly gnu_make_archive="${archives_dir}/make-${GNU_MAKE_VERSION}.tar.gz"
readonly gnu_make_source="${sources_dir}/make-${GNU_MAKE_VERSION}"
readonly file_archive="${archives_dir}/file-${FILE_VERSION}.tar.gz"
readonly file_source="${sources_dir}/file-${FILE_VERSION}"
readonly awk_archive="${archives_dir}/awk-${AWK_VERSION}.tar.gz"
readonly awk_source="${sources_dir}/awk-${AWK_VERSION}"
readonly patch_archive="${archives_dir}/patch-${PATCH_VERSION}.tar.xz"
readonly patch_source="${sources_dir}/patch-${PATCH_VERSION}"
readonly jq_archive="${archives_dir}/jq-${JQ_VERSION}.tar.gz"
readonly jq_source="${sources_dir}/jq-${JQ_VERSION}"
readonly xz_archive="${archives_dir}/xz-${XZ_VERSION}.tar.xz"
readonly xz_source="${sources_dir}/xz-${XZ_VERSION}"
readonly sqlite_archive="${archives_dir}/sqlite-amalgamation-${SQLITE_AMALGAMATION_VERSION}.zip"
readonly sqlite_source="${sources_dir}/sqlite-amalgamation-${SQLITE_AMALGAMATION_VERSION}"

readonly cctools_root="${work_dir}/cctools-${CCTOOLS_VERSION}-ld64-${LD64_VERSION}"
readonly cctools_build="${cctools_root}/build"
readonly cctools_stage="${cctools_root}/stage"
readonly libplist_root="${work_dir}/libplist-${LIBPLIST_VERSION}"
readonly libplist_build="${libplist_root}/build"
readonly openssl_root="${work_dir}/openssl-${OPENSSL_VERSION}"
readonly openssl_build_source="${openssl_root}/source"
readonly openssl_build="${openssl_root}/build"
readonly openssl_stage="${openssl_root}/stage"
readonly ldid_root="${work_dir}/ldid-${LDID_VERSION}"
readonly zip_root="${work_dir}/zip-${ZIP_VERSION}-debian${ZIP_DEBIAN_REVISION}"
readonly zip_build="${zip_root}/source"
readonly unzip_root="${work_dir}/unzip-${UNZIP_VERSION}-debian${UNZIP_DEBIAN_REVISION}"
readonly unzip_build="${unzip_root}/source"
readonly zlib_root="${work_dir}/zlib-${ZLIB_VERSION}"
readonly zlib_build="${zlib_root}/build"
readonly zlib_stage="${zlib_root}/stage"
readonly curl_root="${work_dir}/curl-${CURL_VERSION}"
readonly curl_build="${curl_root}/build"
readonly curl_stage="${curl_root}/stage"
readonly git_root="${work_dir}/git-${GIT_VERSION}"
readonly git_build="${git_root}/source"
readonly git_stage="${git_root}/stage"
readonly libpng_root="${work_dir}/libpng-${LIBPNG_VERSION}"
readonly libpng_build="${libpng_root}/build"
readonly libpng_stage="${libpng_root}/stage"
readonly libjpeg_root="${work_dir}/libjpeg-turbo-${LIBJPEG_TURBO_VERSION}"
readonly libjpeg_build="${libjpeg_root}/build"
readonly libjpeg_stage="${libjpeg_root}/stage"
readonly imagemagick_root="${work_dir}/imagemagick-${IMAGEMAGICK_VERSION}"
readonly imagemagick_build_source="${imagemagick_root}/source"
readonly imagemagick_build="${imagemagick_root}/build"
readonly imagemagick_stage="${imagemagick_root}/stage"
readonly gnu_make_root="${work_dir}/make-${GNU_MAKE_VERSION}"
readonly gnu_make_build_source="${gnu_make_root}/source"
readonly gnu_make_build="${gnu_make_root}/build"
readonly gnu_make_stage="${gnu_make_root}/stage"
readonly file_root="${work_dir}/file-${FILE_VERSION}"
readonly file_native_build="${file_root}/native-build"
readonly file_target_build="${file_root}/target-build"
readonly file_stage="${file_root}/stage"
readonly awk_root="${work_dir}/awk-${AWK_VERSION}"
readonly awk_build="${awk_root}/source"
readonly patch_root="${work_dir}/patch-${PATCH_VERSION}"
readonly patch_build="${patch_root}/build"
readonly patch_stage="${patch_root}/stage"
readonly jq_root="${work_dir}/jq-${JQ_VERSION}"
readonly jq_build="${jq_root}/build"
readonly jq_stage="${jq_root}/stage"
readonly xz_root="${work_dir}/xz-${XZ_VERSION}"
readonly xz_build="${xz_root}/build"
readonly xz_stage="${xz_root}/stage"
readonly sqlite_root="${work_dir}/sqlite-${SQLITE_VERSION}"
readonly sqlite_build="${sqlite_root}/build"
readonly extra_root="${work_dir}/extra-tools"
readonly extra_stage="${extra_root}/stage"
readonly extra_man_indexer="${extra_root}/host-tools/makewhatis"
readonly package_root="${work_dir}/package-root"
readonly payload_dir="${package_root}/${package_name}"
readonly artifact_dir="${work_dir}/artifacts"
readonly package_archive="${artifact_dir}/${package_name}.tar.gz"

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

work_dir_identity="$(repo_path_identity "$work_dir")"
sources_dir_identity="$(repo_path_identity "$sources_dir")"
readonly work_dir_identity sources_dir_identity
readonly component_cache_identity="cache-schema=3;install-prefix=${install_prefix};work-dir=${work_dir_identity};sources-dir=${sources_dir_identity}"
readonly component_build_root_identity="repo-root=${repo_root};work-dir=${work_dir};sources-dir=${sources_dir}"
readonly repo_prefix_map_flags="-ffile-prefix-map=${repo_root}=. -fdebug-prefix-map=${repo_root}=. -fmacro-prefix-map=${repo_root}=."

compiler_version() {
  "$1" --version | sed -n '1p'
}

fetch_archive() {
  local destination="$1"
  local primary_url="$2"
  local primary_sha256="$3"
  local mirror_url="$4"
  local mirror_sha256="${5:-$primary_sha256}"
  local actual_sha256=""
  local attempt=0
  local expected_sha256=""
  local source_index=0
  local source_label=""
  local temporary=""
  local url=""
  local -a expected_sha256s=("$primary_sha256" "$mirror_sha256")
  local -a source_labels=(primary mirror)
  local -a urls=("$primary_url" "$mirror_url")

  if [[ -f "$destination" ]]; then
    actual_sha256="$(sha256sum "$destination" | awk '{print $1}')"
    if [[ "$actual_sha256" == "$primary_sha256" ||
        "$actual_sha256" == "$mirror_sha256" ]]; then
      return 0
    fi

    printf 'warning: discarding cached archive with checksum %s: %s\n' \
      "$actual_sha256" "$destination" >&2
    rm -f -- "$destination"
  fi

  for source_index in "${!urls[@]}"; do
    url="${urls[$source_index]}"
    expected_sha256="${expected_sha256s[$source_index]}"
    source_label="${source_labels[$source_index]}"

    if [[ "$source_label" == mirror ]]; then
      printf 'Primary source exhausted; trying mirror %s\n' "$url"
    fi

    for ((attempt = 1; attempt <= SOURCE_DOWNLOAD_ATTEMPTS; attempt++)); do
      temporary="$(mktemp "${archives_dir}/.download.XXXXXX")"
      printf 'Downloading %s source (attempt %d/%d): %s\n' \
        "$source_label" "$attempt" "$SOURCE_DOWNLOAD_ATTEMPTS" "$url"

      if curl -fL --connect-timeout 30 -o "$temporary" "$url"; then
        actual_sha256="$(sha256sum "$temporary" | awk '{print $1}')"
        if [[ "$actual_sha256" == "$expected_sha256" ]]; then
          mv -- "$temporary" "$destination"
          return 0
        fi
        printf 'warning: checksum mismatch for %s: expected %s, got %s\n' \
          "$url" "$expected_sha256" "$actual_sha256" >&2
      else
        printf 'warning: download failed: %s\n' "$url" >&2
      fi

      rm -f -- "$temporary"
      temporary=""

      if ((attempt < SOURCE_DOWNLOAD_ATTEMPTS)); then
        sleep $((attempt * 2))
      fi
    done
  done

  die "verified download failed from ${primary_url} and ${mirror_url}"
}

apply_source_patch_once() {
  local source_dir="$1"
  local patch_file="$2"
  local description="$3"

  if patch -d "$source_dir" -p1 --batch --forward --dry-run \
      < "$patch_file" >/dev/null 2>&1; then
    printf 'Applying %s\n' "$description"
    patch -d "$source_dir" -p1 --batch --forward < "$patch_file"
  elif patch -d "$source_dir" -p1 --batch --reverse --dry-run \
      < "$patch_file" >/dev/null 2>&1; then
    return
  else
    die "could not apply or verify patch: ${patch_file}"
  fi
}

run_extra_tools() {
  local extra_action="$1"

  "$extra_tools_builder" "$extra_action" \
    --work-dir "$work_dir" \
    --archives-dir "$archives_dir" \
    --sources-dir "${sources_dir}/extra-tools" \
    --sdk "$sdk_dir" \
    --cctools-bin "$cctools_bin" \
    --deployment-target "$deployment_target" \
    --jobs "$jobs" \
    --prefix "$install_prefix" \
    --cc "$cc" \
    --zlib-static "${zlib_stage}/${prefix_rel}/lib/libz.a" \
    --ps-patch "$extra_ps_patch" \
    --mandoc-config "$mandoc_config_template"
}

prepare_sources() {
  local zip_source_tmp=""
  local unzip_source_tmp=""

  fetch_archive \
    "$cctools_archive" \
    "https://github.com/tpoechtrager/cctools-port/archive/${CCTOOLS_COMMIT}.zip" \
    "$CCTOOLS_ARCHIVE_SHA256" \
    "https://codeload.github.com/tpoechtrager/cctools-port/zip/${CCTOOLS_COMMIT}"
  if [[ ! -d "$cctools_source" ]]; then
    printf 'Extracting cctools %s / ld64 %s\n' "$CCTOOLS_VERSION" "$LD64_VERSION"
    unzip -q "$cctools_archive" -d "$sources_dir"
  fi
  apply_source_patch_once \
    "$cctools_source" \
    "$cctools_patch" \
    "ld64 ARMv7 64-bit counter alignment fix"
  apply_source_patch_once \
    "$cctools_source" \
    "$cctools_ios43_patch" \
    "ld64 iOS 4.3 deployment floor"

  fetch_archive \
    "$ldid_archive" \
    "https://github.com/ProcursusTeam/ldid/archive/${LDID_COMMIT}.zip" \
    "$LDID_ARCHIVE_SHA256" \
    "https://codeload.github.com/ProcursusTeam/ldid/zip/${LDID_COMMIT}"
  if [[ ! -d "$ldid_source" ]]; then
    printf 'Extracting ldid %s\n' "$LDID_VERSION"
    unzip -q "$ldid_archive" -d "$sources_dir"
  fi

  fetch_archive \
    "$libplist_archive" \
    "https://github.com/libimobiledevice/libplist/releases/download/${LIBPLIST_VERSION}/libplist-${LIBPLIST_VERSION}.tar.bz2" \
    "$LIBPLIST_ARCHIVE_SHA256" \
    "https://distfiles.macports.org/libplist/libplist-${LIBPLIST_VERSION}.tar.bz2"
  if [[ ! -d "$libplist_source" ]]; then
    printf 'Extracting libplist %s\n' "$LIBPLIST_VERSION"
    tar -xjf "$libplist_archive" -C "$sources_dir"
  fi

  fetch_archive \
    "$openssl_archive" \
    "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" \
    "$OPENSSL_ARCHIVE_SHA256" \
    "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"
  if [[ ! -d "$openssl_source" ]]; then
    printf 'Extracting OpenSSL %s\n' "$OPENSSL_VERSION"
    tar -xzf "$openssl_archive" -C "$sources_dir"
  fi

  fetch_archive \
    "$zip_archive" \
    "https://deb.debian.org/debian/pool/main/z/zip/zip_${ZIP_VERSION}.orig.tar.gz" \
    "$ZIP_ARCHIVE_SHA256" \
    "https://mirrors.kernel.org/debian/pool/main/z/zip/zip_${ZIP_VERSION}.orig.tar.gz"
  fetch_archive \
    "$zip_debian_archive" \
    "https://deb.debian.org/debian/pool/main/z/zip/zip_${ZIP_VERSION}-${ZIP_DEBIAN_REVISION}.debian.tar.xz" \
    "$ZIP_DEBIAN_ARCHIVE_SHA256" \
    "https://mirrors.kernel.org/debian/pool/main/z/zip/zip_${ZIP_VERSION}-${ZIP_DEBIAN_REVISION}.debian.tar.xz"
  if [[ ! -d "$zip_source" ]]; then
    printf 'Extracting Info-ZIP %s and Debian revision %s metadata\n' \
      "$ZIP_VERSION" "$ZIP_DEBIAN_REVISION"
    zip_source_tmp="$(mktemp -d "${sources_dir}/.zip-source.XXXXXX")"
    if ! tar -xzf "$zip_archive" --strip-components=1 -C "$zip_source_tmp"; then
      rm -rf -- "$zip_source_tmp"
      die "could not extract Info-ZIP source"
    fi
    if ! tar -xJf "$zip_debian_archive" -C "$zip_source_tmp"; then
      rm -rf -- "$zip_source_tmp"
      die "could not extract Debian Info-ZIP metadata"
    fi
    mv -- "$zip_source_tmp" "$zip_source"
  fi

  fetch_archive \
    "$unzip_archive" \
    "https://deb.debian.org/debian/pool/main/u/unzip/unzip_${UNZIP_VERSION}.orig.tar.gz" \
    "$UNZIP_ARCHIVE_SHA256" \
    "https://mirrors.kernel.org/debian/pool/main/u/unzip/unzip_${UNZIP_VERSION}.orig.tar.gz"
  fetch_archive \
    "$unzip_debian_archive" \
    "https://deb.debian.org/debian/pool/main/u/unzip/unzip_${UNZIP_VERSION}-${UNZIP_DEBIAN_REVISION}.debian.tar.xz" \
    "$UNZIP_DEBIAN_ARCHIVE_SHA256" \
    "https://mirrors.kernel.org/debian/pool/main/u/unzip/unzip_${UNZIP_VERSION}-${UNZIP_DEBIAN_REVISION}.debian.tar.xz"
  if [[ ! -d "$unzip_source" ]]; then
    printf 'Extracting Info-ZIP UnZip %s and Debian revision %s metadata\n' \
      "$UNZIP_VERSION" "$UNZIP_DEBIAN_REVISION"
    unzip_source_tmp="$(mktemp -d "${sources_dir}/.unzip-source.XXXXXX")"
    if ! tar -xzf "$unzip_archive" --strip-components=1 -C "$unzip_source_tmp"; then
      rm -rf -- "$unzip_source_tmp"
      die "could not extract Info-ZIP UnZip source"
    fi
    if ! tar -xJf "$unzip_debian_archive" -C "$unzip_source_tmp"; then
      rm -rf -- "$unzip_source_tmp"
      die "could not extract Debian Info-ZIP UnZip metadata"
    fi
    mv -- "$unzip_source_tmp" "$unzip_source"
  fi

  fetch_archive \
    "$zlib_archive" \
    "https://zlib.net/zlib-${ZLIB_VERSION}.tar.xz" \
    "$ZLIB_ARCHIVE_SHA256" \
    "https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.xz"
  if [[ ! -d "$zlib_source" ]]; then
    printf 'Extracting zlib %s\n' "$ZLIB_VERSION"
    tar -xJf "$zlib_archive" -C "$sources_dir"
  fi

  fetch_archive \
    "$curl_archive" \
    "https://curl.se/download/curl-${CURL_VERSION}.tar.xz" \
    "$CURL_ARCHIVE_SHA256" \
    "https://github.com/curl/curl/releases/download/curl-${CURL_VERSION//./_}/curl-${CURL_VERSION}.tar.xz"
  if [[ ! -d "$curl_source" ]]; then
    printf 'Extracting curl %s\n' "$CURL_VERSION"
    tar -xJf "$curl_archive" -C "$sources_dir"
  fi

  fetch_archive \
    "$ca_bundle" \
    "https://curl.se/ca/cacert-${CA_BUNDLE_DATE}.pem" \
    "$CA_BUNDLE_SHA256" \
    "https://julialangcache.s3.amazonaws.com/c464e96f9a62fc4b1cbd46cc51453c11ed24c7a47b15711d8fed9e251fab68c0/cacert-${CA_BUNDLE_DATE}.pem"

  fetch_archive \
    "$git_archive" \
    "https://www.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.xz" \
    "$GIT_ARCHIVE_SHA256" \
    "https://distfiles.macports.org/git/git-${GIT_VERSION}.tar.xz"
  if [[ ! -d "$git_source" ]]; then
    printf 'Extracting Git %s\n' "$GIT_VERSION"
    tar -xJf "$git_archive" -C "$sources_dir"
  fi

  fetch_archive \
    "$libpng_archive" \
    "https://download.sourceforge.net/libpng/libpng-${LIBPNG_VERSION}.tar.xz" \
    "$LIBPNG_ARCHIVE_SHA256" \
    "https://distfiles.macports.org/libpng/libpng-${LIBPNG_VERSION}.tar.xz"
  if [[ ! -d "$libpng_source" ]]; then
    printf 'Extracting libpng %s\n' "$LIBPNG_VERSION"
    tar -xJf "$libpng_archive" -C "$sources_dir"
  fi

  fetch_archive \
    "$libjpeg_archive" \
    "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/${LIBJPEG_TURBO_VERSION}/libjpeg-turbo-${LIBJPEG_TURBO_VERSION}.tar.gz" \
    "$LIBJPEG_TURBO_ARCHIVE_SHA256" \
    "https://distfiles.macports.org/libjpeg-turbo/libjpeg-turbo-${LIBJPEG_TURBO_VERSION}.tar.gz"
  if [[ ! -d "$libjpeg_source" ]]; then
    printf 'Extracting libjpeg-turbo %s\n' "$LIBJPEG_TURBO_VERSION"
    tar -xzf "$libjpeg_archive" -C "$sources_dir"
  fi

  fetch_archive \
    "$imagemagick_archive" \
    "https://github.com/ImageMagick/ImageMagick/archive/refs/tags/${IMAGEMAGICK_VERSION}.tar.gz" \
    "$IMAGEMAGICK_ARCHIVE_SHA256" \
    "https://codeload.github.com/ImageMagick/ImageMagick/tar.gz/refs/tags/${IMAGEMAGICK_VERSION}"
  if [[ ! -d "$imagemagick_source" ]]; then
    printf 'Extracting ImageMagick %s\n' "$IMAGEMAGICK_VERSION"
    tar -xzf "$imagemagick_archive" -C "$sources_dir"
  fi

  fetch_archive \
    "$gnu_make_archive" \
    "https://ftp.gnu.org/gnu/make/make-${GNU_MAKE_VERSION}.tar.gz" \
    "$GNU_MAKE_ARCHIVE_SHA256" \
    "https://mirrors.kernel.org/gnu/make/make-${GNU_MAKE_VERSION}.tar.gz"
  if [[ ! -d "$gnu_make_source" ]]; then
    printf 'Extracting GNU Make %s\n' "$GNU_MAKE_VERSION"
    tar -xzf "$gnu_make_archive" -C "$sources_dir"
  fi

  fetch_archive \
    "$file_archive" \
    "https://astron.com/pub/file/file-${FILE_VERSION}.tar.gz" \
    "$FILE_ARCHIVE_SHA256" \
    "https://distfiles.macports.org/file/file-${FILE_VERSION}.tar.gz"
  if [[ ! -d "$file_source" ]]; then
    printf 'Extracting file/libmagic %s\n' "$FILE_VERSION"
    tar -xzf "$file_archive" -C "$sources_dir"
  fi

  fetch_archive \
    "$awk_archive" \
    "https://github.com/onetrueawk/awk/archive/refs/tags/${AWK_VERSION}.tar.gz" \
    "$AWK_ARCHIVE_SHA256" \
    "https://codeload.github.com/onetrueawk/awk/tar.gz/refs/tags/${AWK_VERSION}"
  if [[ ! -d "$awk_source" ]]; then
    printf 'Extracting One True Awk %s\n' "$AWK_VERSION"
    tar -xzf "$awk_archive" -C "$sources_dir"
  fi

  fetch_archive \
    "$patch_archive" \
    "https://ftp.gnu.org/gnu/patch/patch-${PATCH_VERSION}.tar.xz" \
    "$PATCH_ARCHIVE_SHA256" \
    "https://mirrors.kernel.org/gnu/patch/patch-${PATCH_VERSION}.tar.xz"
  if [[ ! -d "$patch_source" ]]; then
    printf 'Extracting GNU patch %s\n' "$PATCH_VERSION"
    tar -xJf "$patch_archive" -C "$sources_dir"
  fi

  fetch_archive \
    "$jq_archive" \
    "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-${JQ_VERSION}.tar.gz" \
    "$JQ_ARCHIVE_SHA256" \
    "https://distfiles.macports.org/jq/jq-${JQ_VERSION}.tar.gz"
  if [[ ! -d "$jq_source" ]]; then
    printf 'Extracting jq %s\n' "$JQ_VERSION"
    tar -xzf "$jq_archive" -C "$sources_dir"
  fi
  apply_source_patch_once \
    "$jq_source" \
    "$jq_patch" \
    "jq iOS 6 exp10 fallback"

  fetch_archive \
    "$xz_archive" \
    "https://github.com/tukaani-project/xz/releases/download/v${XZ_VERSION}/xz-${XZ_VERSION}.tar.xz" \
    "$XZ_ARCHIVE_SHA256" \
    "https://tukaani.org/xz/xz-${XZ_VERSION}.tar.xz"
  if [[ ! -d "$xz_source" ]]; then
    printf 'Extracting XZ Utils %s\n' "$XZ_VERSION"
    tar -xJf "$xz_archive" -C "$sources_dir"
  fi

  fetch_archive \
    "$sqlite_archive" \
    "https://www.sqlite.org/${SQLITE_YEAR}/sqlite-amalgamation-${SQLITE_AMALGAMATION_VERSION}.zip" \
    "$SQLITE_ARCHIVE_SHA256" \
    "https://sqlite.org/${SQLITE_YEAR}/sqlite-amalgamation-${SQLITE_AMALGAMATION_VERSION}.zip"
  if [[ ! -d "$sqlite_source" ]]; then
    printf 'Extracting SQLite %s amalgamation\n' "$SQLITE_VERSION"
    unzip -q "$sqlite_archive" -d "$sources_dir"
  fi

  [[ -x "${cctools_source}/cctools/configure" ]] ||
    die "invalid cctools source tree"
  [[ -f "${ldid_source}/ldid.cpp" ]] || die "invalid ldid source tree"
  [[ -x "${libplist_source}/configure" ]] || die "invalid libplist source tree"
  [[ -x "${openssl_source}/Configure" ]] || die "invalid OpenSSL source tree"
  [[ -f "${zip_source}/zip.c" ]] || die "invalid Info-ZIP source tree"
  [[ -f "${zip_source}/unix/Makefile" ]] ||
    die "invalid Info-ZIP Unix makefile"
  [[ -f "${zip_source}/debian/patches/series" ]] ||
    die "invalid Debian Info-ZIP patch bundle"
  [[ -f "${zip_source}/LICENSE" ]] || die "Info-ZIP license is missing"
  [[ -f "${unzip_source}/unzip.c" ]] ||
    die "invalid Info-ZIP UnZip source tree"
  [[ -f "${unzip_source}/unix/Makefile" ]] ||
    die "invalid Info-ZIP UnZip Unix makefile"
  [[ -f "${unzip_source}/debian/patches/series" ]] ||
    die "invalid Debian Info-ZIP UnZip patch bundle"
  [[ -f "${unzip_source}/LICENSE" ]] ||
    die "Info-ZIP UnZip license is missing"
  [[ -x "${zlib_source}/configure" ]] || die "invalid zlib source tree"
  [[ -x "${curl_source}/configure" ]] || die "invalid curl source tree"
  grep -q -- 'BEGIN CERTIFICATE' "$ca_bundle" ||
    die "invalid CA certificate bundle"
  [[ -f "${git_source}/Makefile" ]] || die "invalid Git source tree"
  [[ -x "${libpng_source}/configure" ]] || die "invalid libpng source tree"
  [[ -f "${libjpeg_source}/CMakeLists.txt" ]] ||
    die "invalid libjpeg-turbo source tree"
  [[ -x "${imagemagick_source}/configure" ]] ||
    die "invalid ImageMagick source tree"
  [[ -x "${gnu_make_source}/configure" ]] ||
    die "invalid GNU Make source tree"
  [[ -x "${file_source}/configure" ]] ||
    die "invalid file/libmagic source tree"
  [[ -f "${awk_source}/awkgram.y" && -f "${awk_source}/maketab.c" ]] ||
    die "invalid One True Awk source tree"
  [[ -x "${patch_source}/configure" ]] ||
    die "invalid GNU patch source tree"
  [[ -x "${jq_source}/configure" && -d "${jq_source}/vendor/oniguruma" ]] ||
    die "invalid jq source tree"
  [[ -x "${xz_source}/configure" ]] ||
    die "invalid XZ Utils source tree"
  [[ -f "${sqlite_source}/sqlite3.c" && -f "${sqlite_source}/shell.c" ]] ||
    die "invalid SQLite amalgamation"
  grep -q "#define SQLITE_VERSION        \"${SQLITE_VERSION}\"" \
    "${sqlite_source}/sqlite3.h" ||
    die "SQLite amalgamation version does not match ${SQLITE_VERSION}"

  run_extra_tools source
}

safe_remove_component() {
  local path
  path="$(realpath -m "$1")"
  case "${path}/" in
    "${work_dir}/"*)
      rm -rf -- "$path"
      ;;
    *)
      die "refusing to remove path outside work directory: ${path}"
      ;;
  esac
}

prepare_component() {
  local component_root="$1"
  local key="$2"
  local stamp="${component_root}/.altivec-toolchain-config"
  local build_root_stamp="${component_root}/.altivec-toolchain-build-root"
  local current=""
  local build_root_current=""

  # The portable configuration stamp lets packaging reuse a verified stage
  # after the repository moves. The separate build-root stamp prevents a full
  # build from resuming generated Makefiles that contain the former mount path.
  key="${key};${component_cache_identity}"

  if [[ -f "$stamp" ]]; then
    current="$(<"$stamp")"
  fi
  if [[ -f "$build_root_stamp" ]]; then
    build_root_current="$(<"$build_root_stamp")"
  fi

  if [[ "$current" != "$key" ||
      "$build_root_current" != "$component_build_root_identity" ]]; then
    safe_remove_component "$component_root"
    mkdir -p "$component_root"
    printf '%s\n' "$key" > "$stamp"
    printf '%s\n' "$component_build_root_identity" > "$build_root_stamp"
  fi
}

validate_cached_components() {
  local component_root=""
  local stamp=""
  local current=""
  local -a component_roots=(
    "$cctools_root"
    "$libplist_root"
    "$openssl_root"
    "$ldid_root"
    "$zip_root"
    "$unzip_root"
    "$zlib_root"
    "$curl_root"
    "$git_root"
    "$libpng_root"
    "$libjpeg_root"
    "$imagemagick_root"
    "$gnu_make_root"
    "$file_root"
    "$awk_root"
    "$patch_root"
    "$jq_root"
    "$xz_root"
    "$sqlite_root"
  )

  for component_root in "${component_roots[@]}"; do
    stamp="${component_root}/.altivec-toolchain-config"
    [[ -f "$stamp" ]] ||
      die "component cache predates the ${install_prefix} layout; rebuild it: ${component_root}"
    current="$(<"$stamp")"
    [[ "$current" == *";${component_cache_identity}" ]] ||
      die "component cache has a different prefix or build root; rebuild it: ${component_root}"
  done

  run_extra_tools verify
}

build_cctools() {
  local key=""
  local cc_command=""
  local cxx_command=""
  local patch_sha=""
  local ios43_patch_sha=""

  patch_sha="$(sha256sum "$cctools_patch" | awk '{print $1}')"
  ios43_patch_sha="$(sha256sum "$cctools_ios43_patch" | awk '{print $1}')"
  key="cctools=${CCTOOLS_COMMIT};patches=${patch_sha},${ios43_patch_sha};sdk=${sdk_dir};target=${target_triple};cc=${cc}:$(compiler_version "$cc");cxx=${cxx}:$(compiler_version "$cxx");prefix=${install_prefix}"
  prepare_component "$cctools_root" "$key"
  mkdir -p "$cctools_build" "$cctools_stage"

  cc_command="${cc} --target=${target_triple} -isysroot ${sdk_dir} -B${cctools_bin} ${repo_prefix_map_flags}"
  cxx_command="${cxx} --target=${target_triple} -isysroot ${sdk_dir} -B${cctools_bin} -stdlib=libc++ ${repo_prefix_map_flags}"

  if [[ ! -f "${cctools_build}/Makefile" ]]; then
    printf 'Configuring cctools %s / ld64 %s\n' "$CCTOOLS_VERSION" "$LD64_VERSION"
    (
      cd "$cctools_build"
      CC="$cc_command" \
      CXX="$cxx_command" \
      AR="$macho_ar" \
      RANLIB="$macho_ranlib" \
      NM="$macho_nm" \
      STRIP="$macho_strip" \
      HOST_AR="$macho_ar" \
      HOST_RANLIB="$macho_ranlib" \
      CFLAGS="-O2 -miphoneos-version-min=${deployment_target}" \
      CXXFLAGS="-O2 -miphoneos-version-min=${deployment_target} -stdlib=libc++" \
      LDFLAGS="-miphoneos-version-min=${deployment_target} -isysroot ${sdk_dir} -B${cctools_bin}" \
      "${cctools_source}/cctools/configure" \
        --build="$build_triple" \
        --host="$autoconf_host" \
        --target="$autoconf_target" \
        --prefix="$install_prefix" \
        --disable-tapi-support \
        --disable-xar-support \
        --without-llvm-config
    )
  fi

  printf 'Building cctools %s / ld64 %s\n' "$CCTOOLS_VERSION" "$LD64_VERSION"
  make -C "$cctools_build" -j"$jobs"
  make -C "$cctools_build" DESTDIR="$cctools_stage" install
  [[ -x "${cctools_stage}/${prefix_rel}/bin/${CCTOOLS_PROGRAM_PREFIX}ld" ]] ||
    die "cctools linker was not staged"
}

build_libplist() {
  local key=""
  local cc_command=""
  local cxx_command=""

  key="libplist=${LIBPLIST_VERSION};sdk=${sdk_dir};target=${target_triple};cc=${cc}:$(compiler_version "$cc");cxx=${cxx}:$(compiler_version "$cxx")"
  prepare_component "$libplist_root" "$key"
  mkdir -p "$libplist_build"

  cc_command="${cc} --target=${target_triple} -isysroot ${sdk_dir} -B${cctools_bin} ${repo_prefix_map_flags}"
  cxx_command="${cxx} --target=${target_triple} -isysroot ${sdk_dir} -B${cctools_bin} -stdlib=libc++ ${repo_prefix_map_flags}"

  if [[ ! -f "${libplist_build}/Makefile" ]]; then
    printf 'Configuring libplist %s\n' "$LIBPLIST_VERSION"
    (
      cd "$libplist_build"
      CC="$cc_command" \
      CXX="$cxx_command" \
      AR="$macho_ar" \
      RANLIB="$macho_ranlib" \
      NM="$macho_nm" \
      STRIP="$macho_strip" \
      CFLAGS="-O2 -miphoneos-version-min=${deployment_target}" \
      CXXFLAGS="-O2 -miphoneos-version-min=${deployment_target} -stdlib=libc++" \
      LDFLAGS="-miphoneos-version-min=${deployment_target} -isysroot ${sdk_dir} -B${cctools_bin}" \
      "${libplist_source}/configure" \
        --build="$build_triple" \
        --host="$autoconf_host" \
        --prefix="$install_prefix" \
        --disable-shared \
        --enable-static \
        --without-cython \
        --without-tests
    )
  fi

  printf 'Building libplist %s\n' "$LIBPLIST_VERSION"
  make -C "$libplist_build" -j"$jobs"
  [[ -f "${libplist_build}/src/.libs/libplist-2.0.a" ]] ||
    die "static libplist was not built"
  [[ -x "${libplist_build}/tools/plistutil" ]] ||
    die "plistutil was not built"
}

build_openssl() {
  local key=""
  local cross_root="${openssl_root}/cross"
  local cross_root_rel=""
  local linked_sdk="${cross_root}/SDKs/iPhoneOS8.4.sdk"
  local cc_command=""

  key="openssl=${OPENSSL_VERSION};source-copy=v1;sdk=${sdk_dir};target=${target_triple};cc=${cc}:$(compiler_version "$cc");apps=on;threads=off;asm=off"
  prepare_component "$openssl_root" "$key"
  if [[ ! -f "${openssl_build_source}/Configure" ]]; then
    mkdir -p "$openssl_build_source"
    cp -a "${openssl_source}/." "$openssl_build_source/"
  fi
  mkdir -p "$openssl_build" "$openssl_stage" "${cross_root}/SDKs"

  if [[ ! -e "$linked_sdk" ]]; then
    ln -s "$sdk_dir" "$linked_sdk"
  elif [[ "$(realpath "$linked_sdk")" != "$sdk_dir" ]]; then
    die "OpenSSL SDK link points at the wrong SDK: ${linked_sdk}"
  fi

  cross_root_rel="$(realpath --relative-to="$openssl_build" "$cross_root")"
  # OpenSSL records its compiler command in the runtime version string. Its
  # sources are built through relative paths, so keep the repo mapping flags
  # out of that recorded command and make CROSS_TOP relative instead.
  cc_command="${cc} --target=${target_triple} -B${cctools_bin}"

  if [[ ! -f "${openssl_build}/Makefile" ]]; then
    printf 'Configuring OpenSSL %s\n' "$OPENSSL_VERSION"
    (
      cd "$openssl_build"
      CC="$cc_command" \
      AR="$macho_ar" \
      RANLIB="$macho_ranlib" \
      CROSS_TOP="$cross_root_rel" \
      CROSS_SDK="iPhoneOS8.4.sdk" \
      "${openssl_build_source}/Configure" ios-cross \
        --prefix="$install_prefix" \
        --openssldir="${install_prefix}/etc/ssl" \
        "-miphoneos-version-min=${deployment_target}" \
        no-shared \
        no-tests \
        no-docs \
        no-module \
        no-asm \
        no-threads
    )
  fi

  printf 'Building OpenSSL %s CLI and static libraries\n' "$OPENSSL_VERSION"
  make -C "$openssl_build" -j"$jobs" \
    CROSS_TOP="$cross_root_rel" \
    CROSS_SDK="iPhoneOS8.4.sdk" \
    build_sw
  if [[ ! -f "${openssl_stage}/${prefix_rel}/lib/libssl.a" ]]; then
    make -C "$openssl_build" \
      CROSS_TOP="$cross_root_rel" \
      CROSS_SDK="iPhoneOS8.4.sdk" \
      DESTDIR="$openssl_stage" \
      install_dev
  fi
  mkdir -p "${openssl_stage}/${prefix_rel}/bin"
  install -m 0755 "${openssl_build}/apps/openssl" \
    "${openssl_stage}/${prefix_rel}/bin/openssl"
  [[ -f "${openssl_build}/libcrypto.a" ]] || die "static libcrypto was not built"
  [[ -f "${openssl_build}/libssl.a" ]] || die "static libssl was not built"
  [[ -x "${openssl_stage}/${prefix_rel}/bin/openssl" ]] ||
    die "OpenSSL CLI was not staged"
  [[ -f "${openssl_stage}/${prefix_rel}/lib/libcrypto.a" ]] ||
    die "OpenSSL development files were not staged"
}

build_ldid() {
  local key=""

  build_libplist
  build_openssl

  key="ldid=${LDID_COMMIT};libplist=${LIBPLIST_VERSION};openssl=${OPENSSL_VERSION};sdk=${sdk_dir};target=${target_triple};cxx=${cxx}:$(compiler_version "$cxx")"
  prepare_component "$ldid_root" "$key"

  printf 'Building ldid %s\n' "$LDID_VERSION"
  "$cxx" \
    --target="$target_triple" \
    -isysroot "$sdk_dir" \
    "-B${cctools_bin}" \
    -stdlib=libc++ \
    -std=c++11 \
    -O2 \
    "-ffile-prefix-map=${repo_root}=." \
    "-fdebug-prefix-map=${repo_root}=." \
    "-fmacro-prefix-map=${repo_root}=." \
    "-miphoneos-version-min=${deployment_target}" \
    "-I${ldid_source}" \
    "-I${libplist_source}/include" \
    "-I${openssl_build}/include" \
    "-I${openssl_build_source}/include" \
    "-DLDID_VERSION=\"${LDID_VERSION}\"" \
    -c "${ldid_source}/ldid.cpp" \
    -o "${ldid_root}/ldid.cpp.o"

  "$cxx" \
    --target="$target_triple" \
    -isysroot "$sdk_dir" \
    "-B${cctools_bin}" \
    -stdlib=libc++ \
    "-miphoneos-version-min=${deployment_target}" \
    "${ldid_root}/ldid.cpp.o" \
    "${libplist_build}/src/.libs/libplist-2.0.a" \
    "${openssl_build}/libcrypto.a" \
    -o "${ldid_root}/ldid"

  [[ -x "${ldid_root}/ldid" ]] || die "ldid was not built"
}

build_zip() {
  local key=""
  local cc_command=""
  local patch_name=""
  local patch_marker="${zip_build}/.altivecchain-patches-applied"

  key="zip=${ZIP_VERSION};debian=${ZIP_DEBIAN_REVISION};sdk=${sdk_dir};target=${target_triple};cc=${cc}:$(compiler_version "$cc");large-file-support=on"
  prepare_component "$zip_root" "$key"

  if [[ ! -f "$patch_marker" ]]; then
    safe_remove_component "$zip_build"
    mkdir -p "$zip_build"
    cp -a "${zip_source}/." "$zip_build/"

    printf 'Applying Debian revision %s patches to Info-ZIP %s\n' \
      "$ZIP_DEBIAN_REVISION" "$ZIP_VERSION"
    while read -r patch_name _; do
      [[ -n "$patch_name" && "$patch_name" != \#* ]] || continue
      patch -d "$zip_build" -p1 --forward \
        < "${zip_build}/debian/patches/${patch_name}"
    done < "${zip_build}/debian/patches/series"
    : > "$patch_marker"
  fi

  cc_command="${cc} --target=${target_triple} -isysroot ${sdk_dir} -B${cctools_bin} ${repo_prefix_map_flags}"

  printf 'Building Info-ZIP %s (Debian revision %s patches)\n' \
    "$ZIP_VERSION" "$ZIP_DEBIAN_REVISION"
  make -C "$zip_build" -f unix/Makefile -j"$jobs" zip \
    CC="$cc_command" \
    BIND="$cc_command" \
    CFLAGS="-I. -DUNIX -DLARGE_FILE_SUPPORT -O2 -miphoneos-version-min=${deployment_target} -DHAVE_DIRENT_H -DHAVE_TERMIOS_H" \
    LFLAGS1="-miphoneos-version-min=${deployment_target}" \
    LFLAGS2=""

  [[ -x "${zip_build}/zip" ]] || die "zip was not built"
}

build_unzip() {
  local key=""
  local cc_command=""
  local patch_name=""
  local patch_marker="${unzip_build}/.altivecchain-patches-applied"

  key="unzip=${UNZIP_VERSION};debian=${UNZIP_DEBIAN_REVISION};sdk=${sdk_dir};target=${target_triple};cc=${cc}:$(compiler_version "$cc");large-file=on;unicode=on;bzip2=off"
  prepare_component "$unzip_root" "$key"

  if [[ ! -f "$patch_marker" ]]; then
    safe_remove_component "$unzip_build"
    mkdir -p "$unzip_build"
    cp -a "${unzip_source}/." "$unzip_build/"

    printf 'Applying Debian revision %s patches to Info-ZIP UnZip %s\n' \
      "$UNZIP_DEBIAN_REVISION" "$UNZIP_VERSION"
    while read -r patch_name _; do
      [[ -n "$patch_name" && "$patch_name" != \#* ]] || continue
      patch -d "$unzip_build" -p1 --forward \
        < "${unzip_build}/debian/patches/${patch_name}"
    done < "${unzip_build}/debian/patches/series"
    : > "$patch_marker"
  fi

  cc_command="${cc} --target=${target_triple} -isysroot ${sdk_dir} -B${cctools_bin} ${repo_prefix_map_flags}"

  printf 'Building Info-ZIP UnZip %s (Debian revision %s patches)\n' \
    "$UNZIP_VERSION" "$UNZIP_DEBIAN_REVISION"
  make -C "$unzip_build" -f unix/Makefile -j"$jobs" unzip \
    CC="$cc_command" \
    LD="$cc_command" \
    CF="-I. -DUNIX -O2 -miphoneos-version-min=${deployment_target} -DACORN_FTYPE_NFS -DWILD_STOP_AT_DIR -DLARGE_FILE_SUPPORT -DUNICODE_SUPPORT -DUNICODE_WCHAR -DUTF8_MAYBE_NATIVE -DNO_LCHMOD -DDATE_FORMAT=DF_YMD -DIZ_HAVE_UXUIDGID -DNOMEMCPY -DNO_WORKING_ISPRINT" \
    LFLAGS1="-miphoneos-version-min=${deployment_target}" \
    LF2=""

  [[ -x "${unzip_build}/unzip" ]] || die "unzip was not built"
}

build_zlib() {
  local key=""
  local cc_command=""

  key="zlib=${ZLIB_VERSION};sdk=${sdk_dir};target=${target_triple};cc=${cc}:$(compiler_version "$cc")"
  prepare_component "$zlib_root" "$key"
  mkdir -p "$zlib_build" "$zlib_stage"

  cc_command="${cc} --target=${target_triple} -isysroot ${sdk_dir} -B${cctools_bin} ${repo_prefix_map_flags}"

  if [[ ! -f "${zlib_build}/Makefile" ]]; then
    printf 'Configuring zlib %s\n' "$ZLIB_VERSION"
    (
      cd "$zlib_build"
      CC="$cc_command" \
      AR="$macho_ar" \
      RANLIB="$macho_ranlib" \
      CFLAGS="-O2 -miphoneos-version-min=${deployment_target}" \
      LDFLAGS="-miphoneos-version-min=${deployment_target} -isysroot ${sdk_dir} -B${cctools_bin}" \
      "${zlib_source}/configure" \
        --prefix="$install_prefix" \
        --static
    )
  fi

  printf 'Building zlib %s\n' "$ZLIB_VERSION"
  make -C "$zlib_build" -j"$jobs"
  make -C "$zlib_build" DESTDIR="$zlib_stage" install

  [[ -f "${zlib_stage}/${prefix_rel}/lib/libz.a" ]] ||
    die "static zlib was not staged"
}

build_curl() {
  local key=""
  local cc_command=""
  local openssl_prefix="${openssl_stage}/${prefix_rel}"
  local zlib_prefix="${zlib_stage}/${prefix_rel}"

  build_zlib
  build_openssl

  key="curl=${CURL_VERSION};openssl=${OPENSSL_VERSION};zlib=${ZLIB_VERSION};ca=${CA_BUNDLE_DATE};sdk=${sdk_dir};target=${target_triple};cc=${cc}:$(compiler_version "$cc");protocols=file,http,https;profile=minimal-v2"
  prepare_component "$curl_root" "$key"
  mkdir -p "$curl_build" "$curl_stage"

  cc_command="${cc} --target=${target_triple} -isysroot ${sdk_dir} -B${cctools_bin} ${repo_prefix_map_flags}"

  if [[ ! -f "${curl_build}/Makefile" ]]; then
    printf 'Configuring curl %s with static OpenSSL %s\n' \
      "$CURL_VERSION" "$OPENSSL_VERSION"
    (
      cd "$curl_build"
      CC="$cc_command" \
      AR="$macho_ar" \
      RANLIB="$macho_ranlib" \
      NM="$macho_nm" \
      STRIP="$macho_strip" \
      CPPFLAGS="-I${openssl_prefix}/include -I${zlib_prefix}/include" \
      CFLAGS="-O2 -miphoneos-version-min=${deployment_target}" \
      LDFLAGS="-miphoneos-version-min=${deployment_target} -isysroot ${sdk_dir} -B${cctools_bin} -L${zlib_prefix}/lib" \
      PKG_CONFIG=/bin/false \
      "${curl_source}/configure" \
        --build="$build_triple" \
        --host="$autoconf_host" \
        --prefix="$install_prefix" \
        --disable-shared \
        --enable-static \
        --disable-docs \
        --disable-threaded-resolver \
        --disable-dict \
        --disable-ftp \
        --disable-gopher \
        --disable-imap \
        --disable-ipfs \
        --disable-ldap \
        --disable-ldaps \
        --disable-mqtt \
        --disable-pop3 \
        --disable-rtsp \
        --disable-smb \
        --disable-smtp \
        --disable-telnet \
        --disable-tftp \
        --disable-websockets \
        --without-brotli \
        --without-gssapi \
        --without-libgsasl \
        --without-libidn2 \
        --without-libpsl \
        --without-libssh2 \
        --without-nghttp2 \
        --without-nghttp3 \
        --without-ngtcp2 \
        --without-quiche \
        --without-zstd \
        --with-openssl="$openssl_prefix" \
        --with-zlib="$zlib_prefix" \
        --with-ca-bundle="${install_prefix}/etc/ssl/certs/cacert.pem" \
        --without-ca-path
    )
  fi

  printf 'Building curl %s\n' "$CURL_VERSION"
  make -C "$curl_build" -j"$jobs"
  make -C "$curl_build" DESTDIR="$curl_stage" install

  [[ -x "${curl_stage}/${prefix_rel}/bin/curl" ]] ||
    die "curl executable was not staged"
  [[ -f "${curl_stage}/${prefix_rel}/lib/libcurl.a" ]] ||
    die "static libcurl was not staged"
}

build_git() {
  local key=""
  local cc_command=""
  local curl_prefix="${curl_stage}/${prefix_rel}"
  local curl_prefix_rel=""
  local openssl_build_rel=""
  local zlib_prefix="${zlib_stage}/${prefix_rel}"
  local zlib_prefix_rel=""
  local -a git_make_args=()

  build_curl

  key="git=${GIT_VERSION};curl=${CURL_VERSION};curl-profile=minimal-v2;openssl=${OPENSSL_VERSION};zlib=${ZLIB_VERSION};sdk=${sdk_dir};target=${target_triple};cc=${cc}:$(compiler_version "$cc");rust=off;expat=off;fsmonitor=off;zlib-link=private-static"
  prepare_component "$git_root" "$key"

  if [[ ! -f "${git_build}/Makefile" ]]; then
    mkdir -p "$git_build"
    cp -a "${git_source}/." "$git_build/"
  fi
  mkdir -p "$git_stage"

  curl_prefix_rel="$(realpath --relative-to="$git_build" "$curl_prefix")"
  openssl_build_rel="$(realpath --relative-to="$git_build" "$openssl_build")"
  zlib_prefix_rel="$(realpath --relative-to="$git_build" "$zlib_prefix")"
  cc_command="${cc} --target=${target_triple} -isysroot ${sdk_dir} -B${cctools_bin} ${repo_prefix_map_flags}"
  git_make_args=(
    "CC=${cc_command}"
    "AR=${macho_ar}"
    "RANLIB=${macho_ranlib}"
    "NM=${macho_nm}"
    "STRIP=${macho_strip}"
    "CFLAGS=-O2 -miphoneos-version-min=${deployment_target} -I${zlib_prefix_rel}/include"
    "LDFLAGS=-miphoneos-version-min=${deployment_target} -isysroot ${sdk_dir} -B${cctools_bin}"
    "BASIC_LDFLAGS="
    "prefix=${install_prefix}"
    "SHELL_PATH=/bin/sh"
    "uname_S=Darwin"
    "uname_M=armv7"
    "uname_R=13.0.0"
    "NO_RUST=YesPlease"
    "NO_EXPAT=YesPlease"
    "NO_GETTEXT=YesPlease"
    "NO_PERL=YesPlease"
    "NO_PYTHON=YesPlease"
    "NO_TCLTK=YesPlease"
    "NO_PCRE=YesPlease"
    "NO_INSTALL_HARDLINKS=YesPlease"
    "FSMONITOR_DAEMON_BACKEND="
    "FSMONITOR_OS_SETTINGS="
    "ZLIB_PATH=${zlib_prefix_rel}"
    "CURL_CFLAGS=-I${curl_prefix_rel}/include"
    "CURL_LDFLAGS=${curl_prefix_rel}/lib/libcurl.a ${openssl_build_rel}/libssl.a ${openssl_build_rel}/libcrypto.a ${zlib_prefix_rel}/lib/libz.a"
  )

  printf 'Building Git %s with HTTPS and system SSH transports\n' "$GIT_VERSION"
  make -C "$git_build" -j"$jobs" "${git_make_args[@]}" all
  make -C "$git_build" "${git_make_args[@]}" DESTDIR="$git_stage" install

  [[ -x "${git_stage}/${prefix_rel}/bin/git" ]] ||
    die "Git executable was not staged"
  [[ -x "${git_stage}/${prefix_rel}/libexec/git-core/git-remote-http" ]] ||
    die "Git HTTP transport was not staged"
  [[ -d "${git_stage}/${prefix_rel}/share/git-core/templates" ]] ||
    die "Git templates were not staged"
}

build_libpng() {
  local key=""
  local cc_command=""
  local zlib_prefix="${zlib_stage}/${prefix_rel}"

  build_zlib

  key="libpng=${LIBPNG_VERSION};zlib=${ZLIB_VERSION};sdk=${sdk_dir};target=${target_triple};cc=${cc}:$(compiler_version "$cc")"
  prepare_component "$libpng_root" "$key"
  mkdir -p "$libpng_build" "$libpng_stage"

  cc_command="${cc} --target=${target_triple} -isysroot ${sdk_dir} -B${cctools_bin} ${repo_prefix_map_flags}"

  if [[ ! -f "${libpng_build}/Makefile" ]]; then
    printf 'Configuring libpng %s\n' "$LIBPNG_VERSION"
    (
      cd "$libpng_build"
      CC="$cc_command" \
      AR="$macho_ar" \
      RANLIB="$macho_ranlib" \
      NM="$macho_nm" \
      STRIP="$macho_strip" \
      CPPFLAGS="-I${zlib_prefix}/include" \
      CFLAGS="-O2 -miphoneos-version-min=${deployment_target}" \
      LDFLAGS="-miphoneos-version-min=${deployment_target} -isysroot ${sdk_dir} -B${cctools_bin} -L${zlib_prefix}/lib" \
      ZLIB_CFLAGS="-I${zlib_prefix}/include" \
      ZLIB_LIBS="${zlib_prefix}/lib/libz.a" \
      PKG_CONFIG=/bin/false \
      "${libpng_source}/configure" \
        --build="$build_triple" \
        --host="$autoconf_host" \
        --prefix="$install_prefix" \
        --disable-shared \
        --enable-static \
        --disable-tools \
        --disable-tests
    )
  fi

  printf 'Building libpng %s\n' "$LIBPNG_VERSION"
  make -C "$libpng_build" -j"$jobs"
  make -C "$libpng_build" DESTDIR="$libpng_stage" install

  [[ -f "${libpng_stage}/${prefix_rel}/lib/libpng16.a" ]] ||
    die "static libpng was not staged"
}

build_libjpeg() {
  local key=""

  key="libjpeg-turbo=${LIBJPEG_TURBO_VERSION};sdk=${sdk_dir};target=${target_triple};cc=${cc}:$(compiler_version "$cc");processor=armv7;abi-size=32-preseeded;simd=off"
  prepare_component "$libjpeg_root" "$key"
  mkdir -p "$libjpeg_stage"

  if [[ ! -f "${libjpeg_build}/CMakeCache.txt" ]]; then
    printf 'Configuring libjpeg-turbo %s\n' "$LIBJPEG_TURBO_VERSION"
    cmake \
      -S "$libjpeg_source" \
      -B "$libjpeg_build" \
      -G "Unix Makefiles" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_SYSTEM_NAME=iOS \
      -DCMAKE_SYSTEM_PROCESSOR=armv7 \
      -DCMAKE_OSX_SYSROOT="$sdk_dir" \
      -DCMAKE_OSX_ARCHITECTURES=armv7 \
      -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
      -DCMAKE_C_COMPILER="$cc" \
      -DCMAKE_C_COMPILER_TARGET="$target_triple" \
      -DCMAKE_C_FLAGS="-B${cctools_bin} ${repo_prefix_map_flags}" \
      -DCMAKE_AR="$macho_ar" \
      -DCMAKE_RANLIB="$macho_ranlib" \
      -DCMAKE_INSTALL_PREFIX="$install_prefix" \
      -DSIZE_T=4 \
      -DUNSIGNED_LONG=4 \
      -DHAVE_SIZE_T=TRUE \
      -DHAVE_UNSIGNED_LONG=TRUE \
      -DENABLE_SHARED=OFF \
      -DENABLE_STATIC=ON \
      -DWITH_SIMD=OFF \
      -DWITH_TURBOJPEG=OFF \
      -DWITH_TOOLS=OFF \
      -DWITH_TESTS=OFF
  fi

  printf 'Building libjpeg-turbo %s\n' "$LIBJPEG_TURBO_VERSION"
  cmake --build "$libjpeg_build" --parallel "$jobs"
  DESTDIR="$libjpeg_stage" cmake --install "$libjpeg_build"

  [[ -f "${libjpeg_stage}/${prefix_rel}/lib/libjpeg.a" ]] ||
    die "static libjpeg-turbo was not staged"
}

build_imagemagick() {
  local key=""
  local cc_command=""
  local cxx_command=""
  local jpeg_prefix="${libjpeg_stage}/${prefix_rel}"
  local png_prefix="${libpng_stage}/${prefix_rel}"
  local zlib_prefix="${zlib_stage}/${prefix_rel}"
  local dependency_sysroot="${imagemagick_root}/dependency-sysroot"
  local dependency_prefix="${dependency_sysroot}/${prefix_rel}"
  local config_dir=""
  local configure_xml=""
  local patch_sha=""

  build_libpng
  build_libjpeg

  patch_sha="$(sha256sum "$imagemagick_patch" | awk '{print $1}')"
  key="imagemagick=${IMAGEMAGICK_VERSION};patch=${patch_sha};libpng=${LIBPNG_VERSION};libjpeg=${LIBJPEG_TURBO_VERSION};zlib=${ZLIB_VERSION};sdk=${sdk_dir};target=${target_triple};cc=${cc}:$(compiler_version "$cc");q=8;hdri=off;threads=off;pkg-config=sysroot-v1;packaging=cli-v1"
  prepare_component "$imagemagick_root" "$key"

  if [[ ! -f "${imagemagick_build_source}/configure" ]]; then
    mkdir -p "$imagemagick_build_source"
    cp -a "${imagemagick_source}/." "$imagemagick_build_source/"
    patch -d "$imagemagick_build_source" -p1 --forward < "$imagemagick_patch"
  fi
  mkdir -p \
    "$imagemagick_build" \
    "$imagemagick_stage" \
    "${dependency_prefix}/include" \
    "${dependency_prefix}/lib/pkgconfig"

  # Give pkg-config one coherent cross-compilation sysroot. The staged .pc
  # files retain their final on-phone prefix, while PKG_CONFIG_SYSROOT_DIR
  # redirects configure's compile and link checks to these private libraries.
  cp -a "${zlib_prefix}/include/." "${dependency_prefix}/include/"
  cp -a "${png_prefix}/include/." "${dependency_prefix}/include/"
  cp -a "${jpeg_prefix}/include/." "${dependency_prefix}/include/"
  install -m 0644 "${zlib_prefix}/lib/libz.a" "${dependency_prefix}/lib/libz.a"
  install -m 0644 "${png_prefix}/lib/libpng16.a" "${dependency_prefix}/lib/libpng16.a"
  install -m 0644 "${jpeg_prefix}/lib/libjpeg.a" "${dependency_prefix}/lib/libjpeg.a"
  cp -a "${zlib_prefix}/lib/pkgconfig/." "${dependency_prefix}/lib/pkgconfig/"
  cp -a "${png_prefix}/lib/pkgconfig/." "${dependency_prefix}/lib/pkgconfig/"
  cp -a "${jpeg_prefix}/lib/pkgconfig/." "${dependency_prefix}/lib/pkgconfig/"

  cc_command="${cc} --target=${target_triple} -isysroot ${sdk_dir} -B${cctools_bin} ${repo_prefix_map_flags}"
  cxx_command="${cxx} --target=${target_triple} -isysroot ${sdk_dir} -B${cctools_bin} -stdlib=libc++ ${repo_prefix_map_flags}"

  if [[ ! -f "${imagemagick_build}/Makefile" ]]; then
    printf 'Configuring ImageMagick %s Q8 with PNG and JPEG\n' \
      "$IMAGEMAGICK_VERSION"
    (
      cd "$imagemagick_build"
      CC="$cc_command" \
      CXX="$cxx_command" \
      AR="$macho_ar" \
      RANLIB="$macho_ranlib" \
      NM="$macho_nm" \
      STRIP="$macho_strip" \
      CFLAGS="-O2 -miphoneos-version-min=${deployment_target}" \
      CXXFLAGS="-O2 -miphoneos-version-min=${deployment_target} -stdlib=libc++" \
      CPPFLAGS="-I${dependency_prefix}/include" \
      LDFLAGS="-miphoneos-version-min=${deployment_target} -isysroot ${sdk_dir} -B${cctools_bin} -L${dependency_prefix}/lib" \
      PKG_CONFIG="$pkg_config" \
      PKG_CONFIG_LIBDIR="${dependency_prefix}/lib/pkgconfig" \
      PKG_CONFIG_SYSROOT_DIR="$dependency_sysroot" \
      "${imagemagick_build_source}/configure" \
        --build="$build_triple" \
        --host="$autoconf_host" \
        --prefix="$install_prefix" \
        --disable-shared \
        --enable-static \
        --enable-legacy-support \
        --disable-docs \
        --disable-openmp \
        --disable-opencl \
        --disable-hdri \
        --without-modules \
        --without-magick-plus-plus \
        --without-bzlib \
        --without-zip \
        --without-zstd \
        --without-djvu \
        --without-fontconfig \
        --without-freetype \
        --without-heic \
        --without-jbig \
        --with-jpeg=yes \
        --without-jxl \
        --without-lcms \
        --without-openjp2 \
        --without-lqr \
        --without-lzma \
        --without-openexr \
        --without-pango \
        --with-png=yes \
        --without-raw \
        --without-rsvg \
        --without-tiff \
        --without-uhdr \
        --without-webp \
        --without-wmf \
        --without-xml \
        --without-threads \
        --without-x \
        --with-utilities \
        --with-quantum-depth=8 \
        --with-security-policy=limited
    )
  fi

  printf 'Building ImageMagick %s\n' "$IMAGEMAGICK_VERSION"
  make -C "$imagemagick_build" -j"$jobs"
  make -C "$imagemagick_build" DESTDIR="$imagemagick_stage" install

  config_dir="${imagemagick_stage}/${prefix_rel}/etc/ImageMagick-7"
  configure_xml="${imagemagick_stage}/${prefix_rel}/lib/ImageMagick-${IMAGEMAGICK_BASE_VERSION}/config-Q8/configure.xml"
  [[ -x "${imagemagick_stage}/${prefix_rel}/bin/magick" ]] ||
    die "ImageMagick executable was not staged"
  [[ -d "$config_dir" ]] || die "ImageMagick configuration was not staged"
  [[ -f "$configure_xml" ]] ||
    die "ImageMagick runtime configuration was not staged"

  # This is a CLI-only package: it deliberately omits ImageMagick headers,
  # libraries, and pkg-config files. Remove the unusable development helpers
  # and build-only fields instead of exposing container paths on the phone.
  rm -f -- \
    "${imagemagick_stage}/${prefix_rel}/bin/MagickCore-config" \
    "${imagemagick_stage}/${prefix_rel}/bin/MagickWand-config"
  sed -i -E \
    '/<configure name="(CC|CFLAGS|CONFIGURE|CPPFLAGS|CXX|CXXFLAGS|DEFS|DISTCHECK_CONFIG_FLAGS|INCLUDE_PATH|LDFLAGS|LIBS|PCFLAGS)" /d' \
    "$configure_xml"

  install -m 0644 "$imagemagick_policy" "${config_dir}/policy.xml"
  install -m 0644 "$imagemagick_delegates" "${config_dir}/delegates.xml"
}

build_gnu_make() {
  local key=""
  local cc_command=""
  local patch_sha=""

  patch_sha="$(sha256sum "$gnu_make_patch" | awk '{print $1}')"
  key="make=${GNU_MAKE_VERSION};patch=${patch_sha};sdk=${sdk_dir};target=${target_triple};cc=${cc}:$(compiler_version "$cc");load=off;nls=off;year2038=off"
  prepare_component "$gnu_make_root" "$key"
  if [[ ! -f "${gnu_make_build_source}/configure" ]]; then
    mkdir -p "$gnu_make_build_source"
    cp -a "${gnu_make_source}/." "$gnu_make_build_source/"
    patch -d "$gnu_make_build_source" -p1 --forward < "$gnu_make_patch"
  fi
  mkdir -p "$gnu_make_build" "$gnu_make_stage"

  cc_command="${cc} --target=${target_triple} -isysroot ${sdk_dir} -B${cctools_bin} ${repo_prefix_map_flags}"

  if [[ ! -f "${gnu_make_build}/Makefile" ]]; then
    printf 'Configuring GNU Make %s\n' "$GNU_MAKE_VERSION"
    (
      cd "$gnu_make_build"
      CC="$cc_command" \
      AR="$macho_ar" \
      RANLIB="$macho_ranlib" \
      NM="$macho_nm" \
      STRIP="$macho_strip" \
      CFLAGS="-O2 -miphoneos-version-min=${deployment_target}" \
      LDFLAGS="-miphoneos-version-min=${deployment_target} -isysroot ${sdk_dir} -B${cctools_bin}" \
      "${gnu_make_build_source}/configure" \
        --build="$build_triple" \
        --host="$autoconf_host" \
        --prefix="$install_prefix" \
        --disable-dependency-tracking \
        --disable-load \
        --disable-nls \
        --disable-rpath \
        --disable-year2038 \
        --without-guile
    )
  fi

  printf 'Building GNU Make %s\n' "$GNU_MAKE_VERSION"
  make -C "$gnu_make_build" -j"$jobs"
  make -C "$gnu_make_build" DESTDIR="$gnu_make_stage" install

  [[ -x "${gnu_make_stage}/${prefix_rel}/bin/make" ]] ||
    die "GNU Make was not staged"
}

build_file() {
  local key=""
  local cc_command=""
  local native_file=""

  key="file=${FILE_VERSION};sdk=${sdk_dir};target=${target_triple};cc=${cc}:$(compiler_version "$cc");static=on;compression-libs=off"
  prepare_component "$file_root" "$key"
  mkdir -p "$file_native_build" "$file_target_build" "$file_stage"

  if [[ ! -f "${file_native_build}/Makefile" ]]; then
    printf 'Configuring native file/libmagic %s bootstrap\n' "$FILE_VERSION"
    (
      cd "$file_native_build"
      "${file_source}/configure" \
        --prefix="${file_root}/native-prefix" \
        --disable-shared \
        --enable-static \
        --disable-bzlib \
        --disable-libseccomp \
        --disable-lzlib \
        --disable-xzlib \
        --disable-zlib \
        --disable-zstdlib
    )
  fi
  printf 'Building native file/libmagic %s bootstrap\n' "$FILE_VERSION"
  make -C "$file_native_build" -j"$jobs"
  native_file="${file_native_build}/src/file"
  [[ -x "$native_file" ]] || die "native file bootstrap was not built"

  cc_command="${cc} --target=${target_triple} -isysroot ${sdk_dir} -B${cctools_bin} ${repo_prefix_map_flags}"

  if [[ ! -f "${file_target_build}/Makefile" ]]; then
    printf 'Configuring file/libmagic %s for ARMv7 iOS\n' "$FILE_VERSION"
    (
      cd "$file_target_build"
      CC="$cc_command" \
      AR="$macho_ar" \
      RANLIB="$macho_ranlib" \
      NM="$macho_nm" \
      STRIP="$macho_strip" \
      CFLAGS="-O2 -miphoneos-version-min=${deployment_target}" \
      LDFLAGS="-miphoneos-version-min=${deployment_target} -isysroot ${sdk_dir} -B${cctools_bin}" \
      "${file_source}/configure" \
        --build="$build_triple" \
        --host="$autoconf_host" \
        --prefix="$install_prefix" \
        --disable-shared \
        --enable-static \
        --disable-bzlib \
        --disable-libseccomp \
        --disable-lzlib \
        --disable-xzlib \
        --disable-zlib \
        --disable-zstdlib
    )
  fi

  printf 'Building file/libmagic %s\n' "$FILE_VERSION"
  make -C "$file_target_build" -j"$jobs" FILE_COMPILE="$native_file"
  make -C "$file_target_build" DESTDIR="$file_stage" \
    FILE_COMPILE="$native_file" install

  [[ -x "${file_stage}/${prefix_rel}/bin/file" ]] ||
    die "file was not staged"
  [[ -f "${file_stage}/${prefix_rel}/lib/libmagic.a" ]] ||
    die "static libmagic was not staged"
  [[ -f "${file_stage}/${prefix_rel}/include/magic.h" ]] ||
    die "libmagic header was not staged"
  [[ -f "${file_stage}/${prefix_rel}/share/misc/magic.mgc" ]] ||
    die "compiled libmagic database was not staged"
}

build_awk() {
  local key=""

  key="awk=${AWK_VERSION};commit=${AWK_COMMIT};sdk=${sdk_dir};target=${target_triple};cc=${cc}:$(compiler_version "$cc");bison=$(bison --version | sed -n '1p')"
  prepare_component "$awk_root" "$key"

  if [[ ! -f "${awk_build}/main.c" ]]; then
    mkdir -p "$awk_build"
    cp -a "${awk_source}/." "$awk_build/"
  fi

  if [[ ! -f "${awk_build}/awkgram.tab.c" ||
        ! -f "${awk_build}/awkgram.tab.h" ]]; then
    printf 'Generating One True Awk parser tables\n'
    (
      cd "$awk_build"
      bison -d awkgram.y
    )
  fi
  if [[ ! -f "${awk_build}/proctab.c" ]]; then
    printf 'Generating One True Awk procedure table\n'
    "$cc" -O2 "${awk_build}/maketab.c" -o "${awk_build}/maketab"
    "${awk_build}/maketab" "${awk_build}/awkgram.tab.h" \
      > "${awk_build}/proctab.c"
  fi

  printf 'Building One True Awk %s\n' "$AWK_VERSION"
  "$cc" \
    --target="$target_triple" \
    -isysroot "$sdk_dir" \
    "-B${cctools_bin}" \
    -O2 \
    "-ffile-prefix-map=${repo_root}=." \
    "-fdebug-prefix-map=${repo_root}=." \
    "-fmacro-prefix-map=${repo_root}=." \
    "-miphoneos-version-min=${deployment_target}" \
    -I"$awk_build" \
    "${awk_build}/awkgram.tab.c" \
    "${awk_build}/b.c" \
    "${awk_build}/main.c" \
    "${awk_build}/parse.c" \
    "${awk_build}/proctab.c" \
    "${awk_build}/tran.c" \
    "${awk_build}/lib.c" \
    "${awk_build}/run.c" \
    "${awk_build}/lex.c" \
    -lm \
    -o "${awk_root}/awk"

  [[ -x "${awk_root}/awk" ]] || die "awk was not built"
}

build_patch() {
  local key=""
  local cc_command=""

  key="patch=${PATCH_VERSION};ios6-at-compat=v2;sdk=${sdk_dir};target=${target_triple};cc=${cc}:$(compiler_version "$cc");xattr=off;nls=off;year2038=off"
  prepare_component "$patch_root" "$key"
  mkdir -p "$patch_build" "$patch_stage"

  cc_command="${cc} --target=${target_triple} -isysroot ${sdk_dir} -B${cctools_bin} ${repo_prefix_map_flags}"

  if [[ ! -f "${patch_build}/Makefile" ]]; then
    printf 'Configuring GNU patch %s\n' "$PATCH_VERSION"
    (
      cd "$patch_build"
      CC="$cc_command" \
      AR="$macho_ar" \
      RANLIB="$macho_ranlib" \
      NM="$macho_nm" \
      STRIP="$macho_strip" \
      CFLAGS="-O2 -miphoneos-version-min=${deployment_target}" \
      LDFLAGS="-miphoneos-version-min=${deployment_target} -isysroot ${sdk_dir} -B${cctools_bin}" \
      ac_cv_func_faccessat=no \
      ac_cv_func_fchmodat=no \
      ac_cv_func_fchownat=no \
      ac_cv_func_fdopendir=no \
      ac_cv_func_fstatat=no \
      ac_cv_func_mkdirat=no \
      ac_cv_func_openat=no \
      ac_cv_func_readlinkat=no \
      ac_cv_func_renameat=no \
      ac_cv_func_symlinkat=no \
      ac_cv_func_unlinkat=no \
      "${patch_source}/configure" \
        --build="$build_triple" \
        --host="$autoconf_host" \
        --prefix="$install_prefix" \
        --disable-dependency-tracking \
        --disable-nls \
        --disable-rpath \
        --disable-xattr \
        --disable-year2038
    )
  fi

  printf 'Building GNU patch %s\n' "$PATCH_VERSION"
  make -C "$patch_build" -j"$jobs"
  make -C "$patch_build" DESTDIR="$patch_stage" install

  [[ -x "${patch_stage}/${prefix_rel}/bin/patch" ]] ||
    die "GNU patch was not staged"
}

build_jq() {
  local key=""
  local cc_command=""
  local patch_sha=""

  patch_sha="$(sha256sum "$jq_patch" | awk '{print $1}')"
  key="jq=${JQ_VERSION};patch=${patch_sha};sdk=${sdk_dir};target=${target_triple};cc=${cc}:$(compiler_version "$cc");oniguruma=builtin-static;docs=off"
  prepare_component "$jq_root" "$key"
  mkdir -p "$jq_build" "$jq_stage"

  cc_command="${cc} --target=${target_triple} -isysroot ${sdk_dir} -B${cctools_bin} ${repo_prefix_map_flags}"

  if [[ ! -f "${jq_build}/Makefile" ]]; then
    printf 'Configuring jq %s with static Oniguruma\n' "$JQ_VERSION"
    (
      cd "$jq_build"
      CC="$cc_command" \
      AR="$macho_ar" \
      RANLIB="$macho_ranlib" \
      NM="$macho_nm" \
      STRIP="$macho_strip" \
      CFLAGS="-O2 -miphoneos-version-min=${deployment_target}" \
      LDFLAGS="-miphoneos-version-min=${deployment_target} -isysroot ${sdk_dir} -B${cctools_bin}" \
      "${jq_source}/configure" \
        --build="$build_triple" \
        --host="$autoconf_host" \
        --prefix="$install_prefix" \
        --disable-dependency-tracking \
        --disable-docs \
        --disable-maintainer-mode \
        --disable-shared \
        --enable-static \
        --with-oniguruma=builtin
    )
  fi

  printf 'Building jq %s\n' "$JQ_VERSION"
  make -C "$jq_build" -j"$jobs"
  make -C "$jq_build" DESTDIR="$jq_stage" install

  [[ -x "${jq_stage}/${prefix_rel}/bin/jq" ]] ||
    die "jq was not staged"
}

build_xz() {
  local key=""
  local cc_command=""
  local xz_bin_dir=""

  key="xz=${XZ_VERSION};sdk=${sdk_dir};target=${target_triple};cc=${cc}:$(compiler_version "$cc");threads=off;sandbox=off;year2038=off;static=on"
  prepare_component "$xz_root" "$key"
  mkdir -p "$xz_build" "$xz_stage"

  cc_command="${cc} --target=${target_triple} -isysroot ${sdk_dir} -B${cctools_bin} ${repo_prefix_map_flags}"

  if [[ ! -f "${xz_build}/Makefile" ]]; then
    printf 'Configuring XZ Utils %s\n' "$XZ_VERSION"
    (
      cd "$xz_build"
      CC="$cc_command" \
      AR="$macho_ar" \
      RANLIB="$macho_ranlib" \
      NM="$macho_nm" \
      STRIP="$macho_strip" \
      CFLAGS="-O2 -miphoneos-version-min=${deployment_target}" \
      LDFLAGS="-miphoneos-version-min=${deployment_target} -isysroot ${sdk_dir} -B${cctools_bin}" \
      "${xz_source}/configure" \
        --build="$build_triple" \
        --host="$autoconf_host" \
        --prefix="$install_prefix" \
        --disable-assembler \
        --disable-dependency-tracking \
        --disable-doc \
        --disable-lzma-links \
        --disable-lzmadec \
        --disable-lzmainfo \
        --disable-nls \
        --disable-rpath \
        --disable-scripts \
        --disable-shared \
        --disable-xzdec \
        --disable-year2038 \
        --enable-sandbox=no \
        --enable-static \
        --enable-threads=no
    )
  fi

  printf 'Building XZ Utils %s\n' "$XZ_VERSION"
  make -C "$xz_build" -j"$jobs"
  make -C "$xz_build" DESTDIR="$xz_stage" install

  xz_bin_dir="${xz_stage}/${prefix_rel}/bin"
  [[ -x "${xz_bin_dir}/xz" ]] || die "xz was not staged"
  ln -sfn xz "${xz_bin_dir}/unxz"
  ln -sfn xz "${xz_bin_dir}/xzcat"
}

build_sqlite() {
  local key=""
  local -a sqlite_flags=()

  key="sqlite=${SQLITE_VERSION};amalgamation=${SQLITE_AMALGAMATION_VERSION};sdk=${sdk_dir};target=${target_triple};cc=${cc}:$(compiler_version "$cc");threadsafe=on;load-extension=off"
  prepare_component "$sqlite_root" "$key"
  mkdir -p "$sqlite_build"

  sqlite_flags=(
    --target="$target_triple"
    -isysroot "$sdk_dir"
    "-B${cctools_bin}"
    -O2
    "-ffile-prefix-map=${repo_root}=."
    "-fdebug-prefix-map=${repo_root}=."
    "-fmacro-prefix-map=${repo_root}=."
    "-miphoneos-version-min=${deployment_target}"
    -DSQLITE_THREADSAFE=1
    -DSQLITE_OMIT_LOAD_EXTENSION=1
    -DHAVE_USLEEP=1
    -DHAVE_GETHOSTUUID=0
  )

  printf 'Building SQLite %s CLI and static library\n' "$SQLITE_VERSION"
  "$cc" "${sqlite_flags[@]}" \
    -fPIC \
    -c "${sqlite_source}/sqlite3.c" \
    -o "${sqlite_build}/sqlite3.o"
  "$macho_ar" rc "${sqlite_build}/libsqlite3.a" \
    "${sqlite_build}/sqlite3.o"
  "$macho_ranlib" "${sqlite_build}/libsqlite3.a"
  "$cc" "${sqlite_flags[@]}" \
    "${sqlite_source}/shell.c" \
    "${sqlite_build}/libsqlite3.a" \
    -lm \
    -o "${sqlite_build}/sqlite3"

  [[ -x "${sqlite_build}/sqlite3" ]] ||
    die "SQLite CLI was not built"
  [[ -f "${sqlite_build}/libsqlite3.a" ]] ||
    die "static SQLite library was not built"
}

build_extra_tools() {
  build_zlib
  run_extra_tools stage
}

write_build_information() {
  local doc_dir="$1"
  local compiler_version=""

  compiler_version="$(compiler_version "$cc")"

  {
    printf 'Altivec Toolchain (armv7) core tools\n'
    printf 'Target: %s\n' "$target_triple"
    printf 'Minimum iOS: %s\n' "$deployment_target"
    printf 'SDK: %s\n' "$sdk_name"
    printf 'Compiler: %s\n' "$compiler_version"
    printf 'Install prefix: %s\n' "$install_prefix"
    printf 'cctools: %s (%s)\n' "$CCTOOLS_VERSION" "$CCTOOLS_COMMIT"
    printf 'ld64: %s\n' "$LD64_VERSION"
    printf 'ldid: %s (%s)\n' "$LDID_VERSION" "$LDID_COMMIT"
    printf 'libplist: %s\n' "$LIBPLIST_VERSION"
    printf 'OpenSSL: %s (CLI plus private static libssl/libcrypto; no threads/modules/assembly)\n' \
      "$OPENSSL_VERSION"
    printf 'zip: %s (Debian revision %s patches; altered ARMv7 iOS port)\n' \
      "$ZIP_VERSION" "$ZIP_DEBIAN_REVISION"
    printf 'unzip: %s (Debian revision %s patches; Unicode/Zip64; no bzip2)\n' \
      "$UNZIP_VERSION" "$UNZIP_DEBIAN_REVISION"
    printf 'zlib: %s (private static dependency)\n' "$ZLIB_VERSION"
    printf 'curl: %s (file/http/https; static OpenSSL; CA bundle %s)\n' \
      "$CURL_VERSION" "$CA_BUNDLE_DATE"
    printf 'Git: %s (system SSH; static curl HTTPS; no Rust/Perl/Python/Tcl/Expat)\n' \
      "$GIT_VERSION"
    printf 'libpng: %s (private static dependency)\n' "$LIBPNG_VERSION"
    printf 'libjpeg-turbo: %s (private static dependency; SIMD disabled)\n' \
      "$LIBJPEG_TURBO_VERSION"
    printf 'ImageMagick: %s (Q8; PNG/JPEG; no HDRI/threads/external delegates)\n' \
      "$IMAGEMAGICK_VERSION"
    printf 'GNU Make: %s (loadable objects/Guile/NLS disabled)\n' \
      "$GNU_MAKE_VERSION"
    printf 'file/libmagic: %s (static CLI/library; compression helpers disabled)\n' \
      "$FILE_VERSION"
    printf 'awk: %s (One True Awk commit %s)\n' "$AWK_VERSION" "$AWK_COMMIT"
    printf 'GNU patch: %s (xattr/NLS disabled)\n' "$PATCH_VERSION"
    printf 'jq: %s (static bundled Oniguruma)\n' "$JQ_VERSION"
    printf 'XZ Utils: %s (static single-threaded xz/unxz/xzcat)\n' "$XZ_VERSION"
    printf 'SQLite: %s (CLI/static library; load extensions disabled)\n' \
      "$SQLITE_VERSION"
    printf 'CMake: container-only build dependency; not installed in this payload\n'
    printf 'TAPI: disabled\n'
    printf 'LTO: disabled\n'
    printf 'XAR: disabled\n'
  } > "${doc_dir}/BUILD-INFO.txt"

  {
    printf '%s  %s\n' "$CCTOOLS_ARCHIVE_SHA256" \
      "https://github.com/tpoechtrager/cctools-port/archive/${CCTOOLS_COMMIT}.zip"
    printf '%s  %s\n' "$LDID_ARCHIVE_SHA256" \
      "https://github.com/ProcursusTeam/ldid/archive/${LDID_COMMIT}.zip"
    printf '%s  %s\n' "$LIBPLIST_ARCHIVE_SHA256" \
      "https://github.com/libimobiledevice/libplist/releases/download/${LIBPLIST_VERSION}/libplist-${LIBPLIST_VERSION}.tar.bz2"
    printf '%s  %s\n' "$OPENSSL_ARCHIVE_SHA256" \
      "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
    printf '%s  %s\n' "$ZIP_ARCHIVE_SHA256" \
      "https://deb.debian.org/debian/pool/main/z/zip/zip_${ZIP_VERSION}.orig.tar.gz"
    printf '%s  %s\n' "$ZIP_DEBIAN_ARCHIVE_SHA256" \
      "https://deb.debian.org/debian/pool/main/z/zip/zip_${ZIP_VERSION}-${ZIP_DEBIAN_REVISION}.debian.tar.xz"
    printf '%s  %s\n' "$UNZIP_ARCHIVE_SHA256" \
      "https://deb.debian.org/debian/pool/main/u/unzip/unzip_${UNZIP_VERSION}.orig.tar.gz"
    printf '%s  %s\n' "$UNZIP_DEBIAN_ARCHIVE_SHA256" \
      "https://deb.debian.org/debian/pool/main/u/unzip/unzip_${UNZIP_VERSION}-${UNZIP_DEBIAN_REVISION}.debian.tar.xz"
    printf '%s  %s\n' "$ZLIB_ARCHIVE_SHA256" \
      "https://zlib.net/zlib-${ZLIB_VERSION}.tar.xz"
    printf '%s  %s\n' "$CURL_ARCHIVE_SHA256" \
      "https://curl.se/download/curl-${CURL_VERSION}.tar.xz"
    printf '%s  %s\n' "$CA_BUNDLE_SHA256" \
      "https://curl.se/ca/cacert-${CA_BUNDLE_DATE}.pem"
    printf '%s  %s\n' "$GIT_ARCHIVE_SHA256" \
      "https://www.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.xz"
    printf '%s  %s\n' "$LIBPNG_ARCHIVE_SHA256" \
      "https://download.sourceforge.net/libpng/libpng-${LIBPNG_VERSION}.tar.xz"
    printf '%s  %s\n' "$LIBJPEG_TURBO_ARCHIVE_SHA256" \
      "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/${LIBJPEG_TURBO_VERSION}/libjpeg-turbo-${LIBJPEG_TURBO_VERSION}.tar.gz"
    printf '%s  %s\n' "$IMAGEMAGICK_ARCHIVE_SHA256" \
      "https://github.com/ImageMagick/ImageMagick/archive/refs/tags/${IMAGEMAGICK_VERSION}.tar.gz"
    printf '%s  %s\n' "$GNU_MAKE_ARCHIVE_SHA256" \
      "https://ftp.gnu.org/gnu/make/make-${GNU_MAKE_VERSION}.tar.gz"
    printf '%s  %s\n' "$FILE_ARCHIVE_SHA256" \
      "https://astron.com/pub/file/file-${FILE_VERSION}.tar.gz"
    printf '%s  %s\n' "$AWK_ARCHIVE_SHA256" \
      "https://github.com/onetrueawk/awk/archive/refs/tags/${AWK_VERSION}.tar.gz"
    printf '%s  %s\n' "$PATCH_ARCHIVE_SHA256" \
      "https://ftp.gnu.org/gnu/patch/patch-${PATCH_VERSION}.tar.xz"
    printf '%s  %s\n' "$JQ_ARCHIVE_SHA256" \
      "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-${JQ_VERSION}.tar.gz"
    printf '%s  %s\n' "$XZ_ARCHIVE_SHA256" \
      "https://github.com/tukaani-project/xz/releases/download/v${XZ_VERSION}/xz-${XZ_VERSION}.tar.xz"
    printf '%s  %s\n' "$SQLITE_ARCHIVE_SHA256" \
      "https://www.sqlite.org/${SQLITE_YEAR}/sqlite-amalgamation-${SQLITE_AMALGAMATION_VERSION}.zip"
  } > "${doc_dir}/SOURCE-MANIFEST.txt"
}

verify_payload() {
  local binary=""
  local dependency=""
  local dependency_path=""
  local deployment_major="${deployment_target%%.*}"
  local executable_count="0"
  local script_count="0"
  local bin_dir="${payload_dir}/${prefix_rel}/bin"
  local libexec_dir="${payload_dir}/${prefix_rel}/libexec"
  local imported_symbols=""
  local load_commands=""
  local file_description=""
  local forbidden_path=""
  local payload_path=""
  local symlink_target=""
  local unsupported_symbol=""
  local imagemagick_configure="${payload_dir}/${prefix_rel}/lib/ImageMagick-${IMAGEMAGICK_BASE_VERSION}/config-Q8/configure.xml"

  [[ -d "${payload_dir}/${prefix_rel}" &&
    ! -L "${payload_dir}/${prefix_rel}" ]] ||
    die "payload install prefix is missing or is a symlink: ${install_prefix}"
  for forbidden_path in \
    "${payload_dir}/usr/local/altivec" \
    "${payload_dir}/usr/local/altivecchain" \
    "${payload_dir}/private/var/altivec"; do
    [[ ! -e "$forbidden_path" && ! -L "$forbidden_path" ]] ||
      die "forbidden compatibility path leaked into payload: ${forbidden_path}"
  done

  for expected in \
    ld ar as nm otool lipo strip install_name_tool ldid plistutil zip unzip \
    curl git magick convert identify mogrify make file awk patch jq xz unxz \
    xzcat sqlite3 openssl \
    vi less clear reset ps pgrep pkill htop watch diff cmp diff3 find xargs \
    grep sed tar gzip bzip2 which killall ifconfig ping nc hostname logger man \
    tree realpath hexdump wc xxd; do
    [[ -x "${bin_dir}/${expected}" ]] ||
      die "staged tool is missing: ${bin_dir}/${expected}"
  done
  for excluded in netstat plutil tput time script renice; do
    [[ ! -e "${bin_dir}/${excluded}" && ! -L "${bin_dir}/${excluded}" ]] ||
      die "unapproved or deferred tool leaked into payload: ${bin_dir}/${excluded}"
  done
  [[ -d "${payload_dir}/${prefix_rel}/share/terminfo" ]] ||
    die "staged terminal database is missing"
  [[ -f "${payload_dir}/${prefix_rel}/share/misc/magic.mgc" ]] ||
    die "staged libmagic database is missing"
  [[ -f "${payload_dir}/${prefix_rel}/include/magic.h" ]] ||
    die "staged libmagic header is missing"
  [[ -f "${payload_dir}/${prefix_rel}/lib/libmagic.a" ]] ||
    die "staged static libmagic library is missing"
  [[ -f "${payload_dir}/${prefix_rel}/include/sqlite3.h" ]] ||
    die "staged SQLite header is missing"
  [[ -f "${payload_dir}/${prefix_rel}/include/sqlite3ext.h" ]] ||
    die "staged SQLite extension header is missing"
  [[ -f "${payload_dir}/${prefix_rel}/lib/libsqlite3.a" ]] ||
    die "staged static SQLite library is missing"
  [[ ! -e "${bin_dir}/cmake" ]] ||
    die "CMake must remain container-only"
  [[ -x "${libexec_dir}/git-core/git-remote-http" ]] ||
    die "staged Git HTTP transport is missing"
  [[ -f "${payload_dir}/${prefix_rel}/etc/ssl/certs/cacert.pem" ]] ||
    die "staged CA certificate bundle is missing"
  [[ -f "${payload_dir}/${prefix_rel}/etc/ImageMagick-7/policy.xml" ]] ||
    die "staged ImageMagick security policy is missing"
  [[ -f "$imagemagick_configure" ]] ||
    die "staged ImageMagick runtime configuration is missing"
  [[ ! -e "${bin_dir}/MagickCore-config" ]] ||
    die "CLI-only payload must not include MagickCore-config"
  [[ ! -e "${bin_dir}/MagickWand-config" ]] ||
    die "CLI-only payload must not include MagickWand-config"
  if grep -Eq \
      '(build-release/Intermediates|/osxcross/|/usr/bin/clang(\+\+)?-[0-9]+|dependency-sysroot)' \
      "$imagemagick_configure"; then
    die "ImageMagick runtime configuration contains build-host paths"
  fi
  [[ -f "${payload_dir}/${prefix_rel}/share/ImageMagick-7/locale.xml" ]] ||
    die "staged ImageMagick locale data is missing"
  [[ -d "${payload_dir}/${prefix_rel}/share/git-core/templates" ]] ||
    die "staged Git templates are missing"

  while IFS= read -r -d '' payload_path; do
    if LC_ALL=C grep -aFq -- "${repo_root}/" "$payload_path"; then
      die "staged file embeds the repository's absolute path: ${payload_path}"
    fi
    if strings "$payload_path" | grep -Eq \
        '(^|[[:space:]"=:,])(-{1,2}[[:alnum:]_-]+=?){0,1}/[^[:space:]]*build-release/Intermediates/'; then
      die "staged file embeds an absolute container build path: ${payload_path}"
    fi
    if LC_ALL=C grep -aFq -- "/usr/local/altivec" "$payload_path"; then
      die "staged file embeds the obsolete /usr/local prefix: ${payload_path}"
    fi
    if LC_ALL=C grep -aFq -- "/private/var/altivec" "$payload_path"; then
      die "staged file embeds /private/var directly instead of /var: ${payload_path}"
    fi
  done < <(find "$payload_dir" -type f -print0)

  while IFS= read -r -d '' payload_path; do
    symlink_target="$(readlink "$payload_path")"
    [[ "$symlink_target" != /* ]] ||
      die "payload contains an absolute symlink: ${payload_path} -> ${symlink_target}"
  done < <(find "$payload_dir" -type l -print0)

  while IFS= read -r -d '' binary; do
    file_description="$(file "$binary")"
    if [[ "$file_description" != *"Mach-O armv7 executable"* ]]; then
      if [[ "$file_description" == *"shell script"* ]]; then
        ((script_count += 1))
        continue
      fi
      die "staged executable has an unexpected format: ${binary}"
    fi
    ((executable_count += 1))

    load_commands="$("$macho_otool" -l "$binary")"
    awk -v expected_version="$deployment_target" -v expected_sdk="$sdk_version" '
      $1 == "cmd" && $2 == "LC_VERSION_MIN_IPHONEOS" {
        in_version_command = 1
        next
      }
      in_version_command && $1 == "version" {
        if ($2 == expected_version) {
          found_version = 1
        }
        next
      }
      in_version_command && $1 == "sdk" {
        if ($2 == expected_sdk) {
          found_sdk = 1
        }
        in_version_command = 0
      }
      END {
        exit(found_version && found_sdk ? 0 : 1)
      }
    ' <<< "$load_commands" ||
      die "wrong deployment target or SDK in ${binary}"
    grep -q 'LC_CODE_SIGNATURE' <<< "$load_commands" ||
      die "staged executable is not pseudo-signed: ${binary}"

    if ((10#$deployment_major < 8)); then
      imported_symbols="$("$macho_otool" -Iv "$binary")"
      if ((10#$deployment_major < 7)); then
        unsupported_symbol="$(
          awk '$NF == "___exp10" { print $NF; exit }' \
            <<< "$imported_symbols"
        )"
        [[ -z "$unsupported_symbol" ]] ||
          die "${binary} imports ${unsupported_symbol}, which requires iOS 7.0"
      fi

      unsupported_symbol="$(
        awk '
          $NF ~ /^_(faccessat|fchmodat|fchownat|fdopendir|fstatat|linkat|mkdirat|openat|readlinkat|renameat|symlinkat|unlinkat)$/ {
            print $NF
            exit
          }
        ' <<< "$imported_symbols"
      )"
      [[ -z "$unsupported_symbol" ]] ||
        die "${binary} imports ${unsupported_symbol}, which requires iOS 8.0"
    fi

    while IFS= read -r dependency; do
      dependency_path="$(printf '%s\n' "$dependency" |
        sed -E 's/^[[:space:]]*([^[:space:]]+).*/\1/')"
      case "$dependency_path" in
        /usr/lib/libSystem.B.dylib|\
        /usr/lib/libc++.1.dylib|\
        /usr/lib/libc++abi.dylib|\
        /usr/lib/libobjc.A.dylib|\
        /usr/lib/libiconv.2.dylib|\
        /System/Library/Frameworks/IOKit.framework/Versions/A/IOKit|\
        /System/Library/Frameworks/CoreFoundation.framework/CoreFoundation)
          ;;
        *)
          die "unexpected runtime dependency in ${binary}: ${dependency_path}"
          ;;
      esac
    done < <("$macho_otool" -L "$binary" | tail -n +2)
  done < <(find "$bin_dir" "$libexec_dir" -type f -perm /111 -print0)

  ((executable_count > 0)) || die "no staged executables were found"
  printf 'Verified %s signed ARMv7 executables and %s shell scripts for iOS %s with SDK %s.\n' \
    "$executable_count" "$script_count" "$deployment_target" "$sdk_version"
}

assemble_payload() {
  local bin_dir=""
  local doc_dir=""
  local binary=""
  local prefixed=""
  local short_name=""
  local checksums_tmp=""

  safe_remove_component "$package_root"
  mkdir -p "$payload_dir"
  cp -a "${cctools_stage}/." "$payload_dir/"
  cp -a "${git_stage}/." "$payload_dir/"
  cp -a "${extra_stage}/." "$payload_dir/"

  bin_dir="${payload_dir}/${prefix_rel}/bin"
  doc_dir="${payload_dir}/${prefix_rel}/share/doc/altivec-toolchain"
  mkdir -p "$bin_dir" "$doc_dir"

  install -m 0755 "${ldid_root}/ldid" "${bin_dir}/ldid"
  ln -s ldid "${bin_dir}/ldid2"
  install -m 0755 "${libplist_build}/tools/plistutil" "${bin_dir}/plistutil"
  install -m 0755 "${zip_build}/zip" "${bin_dir}/zip"
  install -m 0755 "${unzip_build}/unzip" "${bin_dir}/unzip"
  install -m 0755 "${curl_stage}/${prefix_rel}/bin/curl" "${bin_dir}/curl"
  cp -a "${imagemagick_stage}/${prefix_rel}/bin/." "$bin_dir/"
  install -m 0755 "${gnu_make_stage}/${prefix_rel}/bin/make" \
    "${bin_dir}/make"
  install -m 0755 "${file_stage}/${prefix_rel}/bin/file" \
    "${bin_dir}/file"
  install -m 0755 "${awk_root}/awk" "${bin_dir}/awk"
  install -m 0755 "${patch_stage}/${prefix_rel}/bin/patch" \
    "${bin_dir}/patch"
  install -m 0755 "${jq_stage}/${prefix_rel}/bin/jq" "${bin_dir}/jq"
  install -m 0755 "${xz_stage}/${prefix_rel}/bin/xz" "${bin_dir}/xz"
  ln -s xz "${bin_dir}/unxz"
  ln -s xz "${bin_dir}/xzcat"
  install -m 0755 "${sqlite_build}/sqlite3" "${bin_dir}/sqlite3"
  install -m 0755 "${openssl_stage}/${prefix_rel}/bin/openssl" \
    "${bin_dir}/openssl"

  mkdir -p \
    "${payload_dir}/${prefix_rel}/etc/ssl/certs" \
    "${payload_dir}/${prefix_rel}/etc/ImageMagick-7" \
    "${payload_dir}/${prefix_rel}/include" \
    "${payload_dir}/${prefix_rel}/lib" \
    "${payload_dir}/${prefix_rel}/lib/ImageMagick-${IMAGEMAGICK_BASE_VERSION}/config-Q8" \
    "${payload_dir}/${prefix_rel}/share/ImageMagick-7" \
    "${payload_dir}/${prefix_rel}/share/misc"
  install -m 0644 "$ca_bundle" \
    "${payload_dir}/${prefix_rel}/etc/ssl/certs/cacert.pem"
  cp -a "${imagemagick_stage}/${prefix_rel}/etc/ImageMagick-7/." \
    "${payload_dir}/${prefix_rel}/etc/ImageMagick-7/"
  cp -a \
    "${imagemagick_stage}/${prefix_rel}/lib/ImageMagick-${IMAGEMAGICK_BASE_VERSION}/config-Q8/." \
    "${payload_dir}/${prefix_rel}/lib/ImageMagick-${IMAGEMAGICK_BASE_VERSION}/config-Q8/"
  cp -a "${imagemagick_stage}/${prefix_rel}/share/ImageMagick-7/." \
    "${payload_dir}/${prefix_rel}/share/ImageMagick-7/"
  install -m 0644 "${file_stage}/${prefix_rel}/include/magic.h" \
    "${payload_dir}/${prefix_rel}/include/magic.h"
  install -m 0644 "${file_stage}/${prefix_rel}/lib/libmagic.a" \
    "${payload_dir}/${prefix_rel}/lib/libmagic.a"
  install -m 0644 "${file_stage}/${prefix_rel}/share/misc/magic.mgc" \
    "${payload_dir}/${prefix_rel}/share/misc/magic.mgc"
  install -m 0644 "${sqlite_source}/sqlite3.h" \
    "${payload_dir}/${prefix_rel}/include/sqlite3.h"
  install -m 0644 "${sqlite_source}/sqlite3ext.h" \
    "${payload_dir}/${prefix_rel}/include/sqlite3ext.h"
  install -m 0644 "${sqlite_build}/libsqlite3.a" \
    "${payload_dir}/${prefix_rel}/lib/libsqlite3.a"

  mkdir -p \
    "${payload_dir}/${prefix_rel}/share/man/man1" \
    "${payload_dir}/${prefix_rel}/share/man/man3" \
    "${payload_dir}/${prefix_rel}/share/man/man4"
  install -m 0644 "${ldid_source}/docs/ldid.1" \
    "${payload_dir}/${prefix_rel}/share/man/man1/ldid.1"
  install -m 0644 "${zip_build}/man/zip.1" \
    "${payload_dir}/${prefix_rel}/share/man/man1/zip.1"
  install -m 0644 "${unzip_build}/man/unzip.1" \
    "${payload_dir}/${prefix_rel}/share/man/man1/unzip.1"
  install -m 0644 "${gnu_make_source}/doc/make.1" \
    "${payload_dir}/${prefix_rel}/share/man/man1/make.1"
  install -m 0644 "${file_stage}/${prefix_rel}/share/man/man1/file.1" \
    "${payload_dir}/${prefix_rel}/share/man/man1/file.1"
  install -m 0644 "${file_stage}/${prefix_rel}/share/man/man3/libmagic.3" \
    "${payload_dir}/${prefix_rel}/share/man/man3/libmagic.3"
  install -m 0644 "${file_stage}/${prefix_rel}/share/man/man4/magic.4" \
    "${payload_dir}/${prefix_rel}/share/man/man4/magic.4"
  install -m 0644 "${awk_source}/awk.1" \
    "${payload_dir}/${prefix_rel}/share/man/man1/awk.1"
  install -m 0644 "${patch_source}/patch.man" \
    "${payload_dir}/${prefix_rel}/share/man/man1/patch.1"
  install -m 0644 "${jq_source}/jq.1" \
    "${payload_dir}/${prefix_rel}/share/man/man1/jq.1"
  install -m 0644 "${xz_source}/src/xz/xz.1" \
    "${payload_dir}/${prefix_rel}/share/man/man1/xz.1"
  ln -s xz.1 "${payload_dir}/${prefix_rel}/share/man/man1/unxz.1"
  ln -s xz.1 "${payload_dir}/${prefix_rel}/share/man/man1/xzcat.1"
  "$extra_man_indexer" "${payload_dir}/${prefix_rel}/share/man"

  install -m 0644 "${cctools_source}/cctools/APPLE_LICENSE" \
    "${doc_dir}/cctools-APPLE_LICENSE"
  install -m 0644 "${ldid_source}/COPYING" "${doc_dir}/ldid-COPYING"
  install -m 0644 "${libplist_source}/COPYING" "${doc_dir}/libplist-COPYING"
  install -m 0644 "${libplist_source}/COPYING.LESSER" \
    "${doc_dir}/libplist-COPYING.LESSER"
  install -m 0644 "${openssl_source}/LICENSE.txt" "${doc_dir}/openssl-LICENSE.txt"
  install -m 0644 "${zip_build}/LICENSE" "${doc_dir}/zip-LICENSE"
  install -m 0644 "${zip_build}/debian/copyright" \
    "${doc_dir}/zip-DEBIAN-copyright"
  install -m 0644 "${unzip_build}/LICENSE" "${doc_dir}/unzip-LICENSE"
  install -m 0644 "${unzip_build}/debian/copyright" \
    "${doc_dir}/unzip-DEBIAN-copyright"
  install -m 0644 "${zlib_source}/README" "${doc_dir}/zlib-README"
  install -m 0644 "${curl_source}/COPYING" "${doc_dir}/curl-COPYING"
  install -m 0644 "${git_source}/COPYING" "${doc_dir}/git-COPYING"
  install -m 0644 "${libpng_source}/LICENSE" "${doc_dir}/libpng-LICENSE"
  install -m 0644 "${libjpeg_source}/LICENSE.md" \
    "${doc_dir}/libjpeg-turbo-LICENSE.md"
  install -m 0644 "${imagemagick_source}/LICENSE" \
    "${doc_dir}/ImageMagick-LICENSE"
  install -m 0644 "${gnu_make_source}/COPYING" \
    "${doc_dir}/make-COPYING"
  install -m 0644 "${file_source}/COPYING" \
    "${doc_dir}/file-COPYING"
  install -m 0644 "${awk_source}/LICENSE" \
    "${doc_dir}/awk-LICENSE"
  install -m 0644 "${patch_source}/COPYING" \
    "${doc_dir}/patch-COPYING"
  install -m 0644 "${jq_source}/COPYING" \
    "${doc_dir}/jq-COPYING"
  install -m 0644 "${jq_source}/vendor/oniguruma/COPYING" \
    "${doc_dir}/oniguruma-COPYING"
  install -m 0644 "${xz_source}/COPYING" \
    "${doc_dir}/xz-COPYING"
  sed -n '1,35p' "${sqlite_source}/sqlite3.h" \
    > "${doc_dir}/sqlite-PUBLIC-DOMAIN.txt"
  write_build_information "$doc_dir"

  while IFS= read -r -d '' prefixed; do
    short_name="${prefixed##*/}"
    short_name="${short_name#"${CCTOOLS_PROGRAM_PREFIX}"}"
    if [[ ! -e "${bin_dir}/${short_name}" ]]; then
      ln -s "${prefixed##*/}" "${bin_dir}/${short_name}"
    fi
  done < <(find "$bin_dir" -maxdepth 1 -type f \
    -name "${CCTOOLS_PROGRAM_PREFIX}*" -print0)

  while IFS= read -r -d '' binary; do
    if [[ "$(file "$binary")" != *"Mach-O armv7 executable"* ]]; then
      continue
    fi
    "$macho_strip" -x "$binary"
    "$ldid_signer" -S "$binary"
  done < <(find \
    "$bin_dir" \
    "${payload_dir}/${prefix_rel}/libexec" \
    -type f -perm /111 -print0)

  verify_payload

  checksums_tmp="${work_dir}/payload-SHA256SUMS"
  (
    cd "$payload_dir"
    find . -type f -print0 |
      sort -z |
      xargs -0 sha256sum
  ) > "$checksums_tmp"
  mv -- "$checksums_tmp" "${doc_dir}/SHA256SUMS"
}

stage_payload() {
  build_cctools
  build_ldid
  build_zip
  build_unzip
  build_git
  build_imagemagick
  build_gnu_make
  build_file
  build_awk
  build_patch
  build_jq
  build_xz
  build_sqlite
  build_extra_tools

  assemble_payload
}

package_payload() {
  local temporary_archive=""

  stage_payload
  mkdir -p "$artifact_dir"
  temporary_archive="${package_archive}.tmp.$$"
  tar -czf "$temporary_archive" -C "$package_root" "$package_name"
  mv -f -- "$temporary_archive" "$package_archive"
  printf 'Core tools archive: %s\n' "$package_archive"
}

package_payload_from_cache() {
  local temporary_archive=""

  validate_cached_components
  assemble_payload
  mkdir -p "$artifact_dir"
  temporary_archive="${package_archive}.tmp.$$"
  tar -czf "$temporary_archive" -C "$package_root" "$package_name"
  mv -f -- "$temporary_archive" "$package_archive"
  printf 'Core tools archive (cached component stages): %s\n' "$package_archive"
}

prepare_sources

case "$action" in
  source)
    printf 'Pinned source archives are available under %s\n' "$archives_dir"
    printf 'Extracted source trees are available under %s\n' "$sources_dir"
    ;;
  cctools)
    build_cctools
    ;;
  libplist)
    build_libplist
    ;;
  openssl)
    build_openssl
    ;;
  ldid)
    build_ldid
    ;;
  zip)
    build_zip
    ;;
  unzip)
    build_unzip
    ;;
  zlib)
    build_zlib
    ;;
  curl)
    build_curl
    ;;
  git)
    build_git
    ;;
  libpng)
    build_libpng
    ;;
  libjpeg)
    build_libjpeg
    ;;
  imagemagick)
    build_imagemagick
    ;;
  make)
    build_gnu_make
    ;;
  file)
    build_file
    ;;
  awk)
    build_awk
    ;;
  patch)
    build_patch
    ;;
  jq)
    build_jq
    ;;
  xz)
    build_xz
    ;;
  sqlite)
    build_sqlite
    ;;
  extra)
    build_extra_tools
    ;;
  stage)
    stage_payload
    printf 'Staged payload: %s\n' "$payload_dir"
    ;;
  verify)
    stage_payload
    ;;
  package)
    package_payload
    ;;
  package-from-cache)
    package_payload_from_cache
    ;;
esac
