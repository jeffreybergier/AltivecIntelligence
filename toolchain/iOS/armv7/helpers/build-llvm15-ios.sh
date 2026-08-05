#!/usr/bin/env bash
#
# Reproduce the LLVM/Clang 15.0.6 armv7 iOS 6 cross-build. Downloaded archives,
# extracted sources, generated files, logs, and artifacts live under explicitly
# supplied directories. In-repository paths are rejected unless the caller
# explicitly selects build-release/Intermediates.
#
# Usage:
#   helpers/build-llvm15-ios.sh \
#       <source|native|configure|build|package|package-from-cache> \
#       --work-dir <path> [options]
#
# The actions are cumulative. For example, "build" prepares the source, builds
# native TableGen tools, configures the armv7 tree, and builds clang. Re-running
# an action resumes the existing CMake builds.

set -euo pipefail

llvm_version="15.0.6"
# Commit referenced by the signed llvmorg-15.0.6 release tag.
source_commit="088f33605d8a61ff519c580a71b1dd57d16a03f8"
source_archive="llvm-project-${source_commit}.zip"
source_url="https://github.com/llvm/llvm-project/archive/${source_commit}.zip"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
patch_file="${script_dir}/llvm15-ios-clonefile.patch"
arclite_archive_source="${script_dir}/../payload/lib/arc/libarclite_iphoneos.a"
arclite_archive_sha256="f019ba9bf87bb7a47cfd063542d9e6ed81efe76472c869ad509230aafef18bf8"
arclite_deployment_target="4.3"

action=""
work_dir_input=""
archives_dir_input=""
sources_dir_input=""
sdk_dir="/osxcross/target/SDK/iPhoneOS8.4.sdk"
cctools_bin="/osxcross/target/bin"
deployment_target="6.0"
jobs="2"
generator_choice="auto"
host_cc_input=""
host_cxx_input=""
llvm_ar_input=""
llvm_ranlib_input=""
llvm_nm_input=""
llvm_strip_input=""
ldid_input=""
sign_artifact="true"
allow_in_repo_work_dir="false"

usage() {
    printf '%s\n' \
        "Usage:" \
        "  helpers/build-llvm15-ios.sh \\" \
        "    <source|native|configure|build|package|package-from-cache> \\" \
        "    --work-dir <path> [options]" \
        "" \
        "Options:" \
        "  --work-dir <path>          Required generated-build workspace." \
        "  --archives-dir <path>      Downloaded source archives." \
        "  --sources-dir <path>       Extracted source trees." \
        "  --sdk <path>               iPhoneOS SDK (default: ${sdk_dir})." \
        "  --cctools-bin <path>       Directory containing the Apple ld." \
        "  --deployment-target <ver>  iOS target (default: ${deployment_target})." \
        "  --jobs <count>             Parallel build jobs (default: ${jobs})." \
        "  --generator <auto|ninja|make>" \
        "                              CMake generator (default: auto)." \
        "  --host-cc <path>           Native bootstrap C compiler." \
        "  --host-cxx <path>          Native bootstrap C++ compiler." \
        "  --llvm-ar <path>           LLVM ar implementation." \
        "  --llvm-ranlib <path>       LLVM ranlib implementation." \
        "  --llvm-nm <path>           LLVM nm implementation." \
        "  --llvm-strip <path>        LLVM strip implementation." \
        "  --ldid <path>              ldid used to pseudo-sign the package copy." \
        "  --no-sign                  Do not pseudo-sign the package copy." \
        "  --allow-in-repo-work-dir   Permit paths under build-release/Intermediates." \
        "  -h, --help                 Show this help."
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_value() {
    local option_name="$1"
    local option_value="${2:-}"
    [[ -n "$option_value" ]] || die "${option_name} requires a value"
}

resolve_tool() {
    local candidate=""
    local resolved=""

    for candidate in "$@"; do
        [[ -n "$candidate" ]] || continue
        if [[ "$candidate" == */* ]]; then
            if [[ -x "$candidate" ]]; then
                resolved="$(cd "$(dirname "$candidate")" && pwd -P)/$(basename "$candidate")"
                printf '%s\n' "$resolved"
                return 0
            fi
        elif resolved="$(command -v "$candidate" 2>/dev/null)"; then
            printf '%s\n' "$resolved"
            return 0
        fi
    done
    return 1
}

resolve_requested_tool() {
    local requested="$1"
    shift

    if [[ -n "$requested" ]]; then
        resolve_tool "$requested"
    else
        resolve_tool "$@"
    fi
}

run_logged() {
    local log_file="$1"
    shift

    mkdir -p "$(dirname "$log_file")"
    "$@" 2>&1 | tee "$log_file"
}

cmake_generator_args=()

select_generator() {
    local build_dir="$1"
    local selected=""

    cmake_generator_args=()
    if [[ -f "${build_dir}/CMakeCache.txt" ]]; then
        return
    fi

    case "$generator_choice" in
        auto)
            if command -v ninja >/dev/null 2>&1; then
                selected="Ninja"
            else
                selected="Unix Makefiles"
            fi
            ;;
        ninja)
            command -v ninja >/dev/null 2>&1 ||
                die "the Ninja generator was requested but ninja is unavailable"
            selected="Ninja"
            ;;
        make)
            selected="Unix Makefiles"
            ;;
        *)
            die "unsupported generator: ${generator_choice}"
            ;;
    esac
    cmake_generator_args=(-G "$selected")
}

if [[ $# -eq 0 ]]; then
    usage
    exit 2
fi

case "$1" in
    source|native|configure|build|package|package-from-cache)
        action="$1"
        shift
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        die "unknown action: $1"
        ;;
esac

while [[ $# -gt 0 ]]; do
    case "$1" in
        --work-dir)
            require_value "$1" "${2:-}"
            work_dir_input="$2"
            shift 2
            ;;
        --archives-dir)
            require_value "$1" "${2:-}"
            archives_dir_input="$2"
            shift 2
            ;;
        --sources-dir)
            require_value "$1" "${2:-}"
            sources_dir_input="$2"
            shift 2
            ;;
        --sdk)
            require_value "$1" "${2:-}"
            sdk_dir="$2"
            shift 2
            ;;
        --cctools-bin)
            require_value "$1" "${2:-}"
            cctools_bin="$2"
            shift 2
            ;;
        --deployment-target)
            require_value "$1" "${2:-}"
            deployment_target="$2"
            shift 2
            ;;
        --jobs)
            require_value "$1" "${2:-}"
            jobs="$2"
            shift 2
            ;;
        --generator)
            require_value "$1" "${2:-}"
            generator_choice="$2"
            shift 2
            ;;
        --host-cc)
            require_value "$1" "${2:-}"
            host_cc_input="$2"
            shift 2
            ;;
        --host-cxx)
            require_value "$1" "${2:-}"
            host_cxx_input="$2"
            shift 2
            ;;
        --llvm-ar)
            require_value "$1" "${2:-}"
            llvm_ar_input="$2"
            shift 2
            ;;
        --llvm-ranlib)
            require_value "$1" "${2:-}"
            llvm_ranlib_input="$2"
            shift 2
            ;;
        --llvm-nm)
            require_value "$1" "${2:-}"
            llvm_nm_input="$2"
            shift 2
            ;;
        --llvm-strip)
            require_value "$1" "${2:-}"
            llvm_strip_input="$2"
            shift 2
            ;;
        --ldid)
            require_value "$1" "${2:-}"
            ldid_input="$2"
            shift 2
            ;;
        --no-sign)
            sign_artifact="false"
            shift
            ;;
        --allow-in-repo-work-dir)
            allow_in_repo_work_dir="true"
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

[[ -n "$work_dir_input" ]] || die "--work-dir is required"
[[ "$work_dir_input" != "/" ]] || die "--work-dir must not be /"
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive integer"
[[ "$deployment_target" =~ ^[0-9]+([.][0-9]+)*$ ]] ||
    die "--deployment-target must be numeric"
[[ "$cctools_bin" != *[[:space:]]* ]] ||
    die "--cctools-bin cannot contain whitespace because it is used with -B"

command -v realpath >/dev/null 2>&1 || die "GNU realpath is required"
realpath -m / >/dev/null 2>&1 || die "realpath must support GNU's -m option"
repo_root="$(cd "${script_dir}/.." && pwd -P)"
repo_prefix_map_flags="-ffile-prefix-map=${repo_root}=. -fdebug-prefix-map=${repo_root}=. -fmacro-prefix-map=${repo_root}=."
work_dir="$(realpath -m "$work_dir_input")"
in_repo_work_root="${repo_root}/build-release/Intermediates"
case "$work_dir" in
    "$repo_root")
        die "--work-dir must not be the repository root"
        ;;
    "$repo_root"/*)
        [[ "$allow_in_repo_work_dir" == "true" ]] ||
            die "--work-dir must be outside the repository"
        case "$work_dir" in
            "$in_repo_work_root"|"$in_repo_work_root"/*)
                ;;
            *)
                die "--allow-in-repo-work-dir only permits ${in_repo_work_root}"
                ;;
        esac
        ;;
esac
mkdir -p "$work_dir"
work_dir="$(cd "$work_dir" && pwd -P)"
if [[ -n "$archives_dir_input" ]]; then
    archives_dir="$(realpath -m "$archives_dir_input")"
else
    archives_dir="${work_dir}/Archives"
fi
if [[ -n "$sources_dir_input" ]]; then
    sources_dir="$(realpath -m "$sources_dir_input")"
else
    sources_dir="${work_dir}/sources"
fi
for generated_dir in "$archives_dir" "$sources_dir"; do
    [[ "$generated_dir" != "/" ]] || die "generated directories must not be /"
    case "$generated_dir" in
        "$repo_root"|"$repo_root"/*)
            [[ "$allow_in_repo_work_dir" == "true" ]] ||
                die "generated directories must be outside the repository"
            case "$generated_dir" in
                "$in_repo_work_root"|"$in_repo_work_root"/*)
                    ;;
                *)
                    die "--allow-in-repo-work-dir only permits ${in_repo_work_root}"
                    ;;
            esac
            ;;
    esac
done
[[ "$archives_dir" != "$sources_dir" ]] ||
    die "archive and extracted-source directories must differ"
mkdir -p "$archives_dir" "$sources_dir"
archives_dir="$(cd "$archives_dir" && pwd -P)"
sources_dir="$(cd "$sources_dir" && pwd -P)"
archive_path="${archives_dir}/${source_archive}"
source_dir="${sources_dir}/llvm-project-${source_commit}"
native_build_dir="${work_dir}/build-native"
deployment_tag="${deployment_target%.0}"
deployment_tag="${deployment_tag//./_}"
target_build_dir="${work_dir}/build-ios-armv7-ios${deployment_tag}"
logs_dir="${work_dir}/logs"
triple="armv7-apple-ios${deployment_target}"
build_root_stamp="${work_dir}/.altivec-toolchain-build-root"
build_root_identity="llvm-build-schema=2;repo-root=${repo_root};work-dir=${work_dir};sources-dir=${sources_dir}"

prepare_build_cache() {
    local current=""
    local build_dir=""

    if [[ -f "$build_root_stamp" ]]; then
        current="$(<"$build_root_stamp")"
    fi
    [[ "$current" == "$build_root_identity" ]] && return 0

    # CMake build trees are not relocatable. Keep package-from-cache usable,
    # but start resumable native/target builds fresh after a mount-path change.
    for build_dir in "$native_build_dir" "$target_build_dir"; do
        case "$build_dir" in
            "${work_dir}/build-native"|"${work_dir}/build-ios-armv7-"*)
                if [[ -e "$build_dir" || -L "$build_dir" ]]; then
                    rm -rf -- "$build_dir"
                fi
                ;;
            *)
                die "refusing to replace unsafe LLVM build directory: ${build_dir}"
                ;;
        esac
    done
    printf '%s\n' "$build_root_identity" > "$build_root_stamp"
}

prepare_source() {
    local download_path="${archive_path}.part"

    command -v curl >/dev/null 2>&1 || die "curl is required"
    command -v unzip >/dev/null 2>&1 || die "unzip is required"
    command -v patch >/dev/null 2>&1 || die "patch is required"
    [[ -f "$patch_file" ]] || die "missing source patch: ${patch_file}"

    if [[ ! -f "$archive_path" ]]; then
        printf 'Downloading LLVM %s source to %s\n' "$llvm_version" "$archive_path"
        curl --fail --location --retry 3 --progress-bar \
            --output "$download_path" "$source_url"
        mv "$download_path" "$archive_path"
    fi

    unzip -tq "$archive_path" >/dev/null ||
        die "source ZIP failed its CRC integrity check: ${archive_path}"

    if [[ ! -d "$source_dir" ]]; then
        [[ ! -e "$source_dir" ]] ||
            die "stale extraction path exists: ${source_dir}"
        printf 'Extracting LLVM source under %s\n' "$sources_dir"
        unzip -q "$archive_path" -d "$sources_dir"
    fi

    if patch -d "$source_dir" -p1 -s -f -N -F 0 --dry-run \
        < "$patch_file" >/dev/null 2>&1; then
        printf 'Applying old-iOS clonefile guard\n'
        patch -d "$source_dir" -p1 -s -f -N -F 0 < "$patch_file"
    elif patch -d "$source_dir" -p1 -s -f -R -F 0 --dry-run \
        < "$patch_file" >/dev/null 2>&1; then
        printf 'Old-iOS clonefile guard is already applied\n'
    else
        die "LLVM source does not match the recorded clonefile patch"
    fi
}

ensure_native_tools() {
    local host_cc=""
    local host_cxx=""
    local cmake_args=()
    local native_linker_args=()

    command -v cmake >/dev/null 2>&1 || die "cmake is required"
    host_cc="$(resolve_requested_tool "$host_cc_input" /usr/bin/clang clang)" ||
        die "a native Clang C compiler is required"
    host_cxx="$(resolve_requested_tool "$host_cxx_input" /usr/bin/clang++ clang++)" ||
        die "a native Clang C++ compiler is required"
    if command -v ld.lld >/dev/null 2>&1; then
        native_linker_args=(-DLLVM_USE_LINKER=lld)
    fi

    select_generator "$native_build_dir"
    cmake_args=(
        cmake
        -S "${source_dir}/llvm"
        -B "$native_build_dir"
        "${cmake_generator_args[@]}"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_C_COMPILER="$host_cc"
        -DCMAKE_CXX_COMPILER="$host_cxx"
        "${native_linker_args[@]}"
        -DLLVM_ENABLE_PROJECTS=clang
        -DLLVM_TARGETS_TO_BUILD=ARM
        -DLLVM_INCLUDE_TESTS=OFF
        -DCLANG_INCLUDE_TESTS=OFF
        -DLLVM_INCLUDE_EXAMPLES=OFF
        -DLLVM_INCLUDE_BENCHMARKS=OFF
        -DLLVM_INCLUDE_DOCS=OFF
        -DLLVM_ENABLE_BINDINGS=OFF
        -DLLVM_ENABLE_TERMINFO=OFF
        -DLLVM_ENABLE_ZLIB=OFF
        -DLLVM_ENABLE_ZSTD=OFF
        -DLLVM_ENABLE_LIBXML2=OFF
    )
    run_logged "${logs_dir}/configure-native.log" "${cmake_args[@]}"
    run_logged "${logs_dir}/build-native-tablegen.log" \
        cmake --build "$native_build_dir" \
        --target llvm-tblgen clang-tblgen \
        --parallel "$jobs"

    [[ -x "${native_build_dir}/bin/llvm-tblgen" ]] ||
        die "native llvm-tblgen was not built"
    [[ -x "${native_build_dir}/bin/clang-tblgen" ]] ||
        die "native clang-tblgen was not built"
}

configure_armv7() {
    local host_cc=""
    local host_cxx=""
    local llvm_ar=""
    local llvm_ranlib=""
    local llvm_nm=""
    local linker_search_flag=""
    local cxx_flags=""
    local cmake_args=()

    [[ -d "$sdk_dir" ]] || die "iPhoneOS SDK not found: ${sdk_dir}"
    [[ -d "$cctools_bin" ]] || die "cctools directory not found: ${cctools_bin}"
    [[ -x "${cctools_bin}/ld" ]] || die "Apple linker not found: ${cctools_bin}/ld"

    host_cc="$(resolve_requested_tool "$host_cc_input" /usr/bin/clang clang)" ||
        die "a Clang C compiler with Apple target support is required"
    host_cxx="$(resolve_requested_tool "$host_cxx_input" /usr/bin/clang++ clang++)" ||
        die "a Clang C++ compiler with Apple target support is required"
    llvm_ar="$(resolve_requested_tool "$llvm_ar_input" /usr/bin/llvm-ar-14 llvm-ar llvm-ar-14)" ||
        die "llvm-ar is required"
    llvm_ranlib="$(resolve_requested_tool "$llvm_ranlib_input" /usr/bin/llvm-ranlib-14 llvm-ranlib llvm-ranlib-14)" ||
        die "llvm-ranlib is required"
    llvm_nm="$(resolve_requested_tool "$llvm_nm_input" /usr/bin/llvm-nm-14 llvm-nm llvm-nm-14)" ||
        die "llvm-nm is required"

    linker_search_flag="-B${cctools_bin}"
    cxx_flags="${linker_search_flag} -stdlib=libc++ -DLLVM_USE_RW_MUTEX_IMPL ${repo_prefix_map_flags}"

    select_generator "$target_build_dir"
    cmake_args=(
        cmake
        -S "${source_dir}/llvm"
        -B "$target_build_dir"
        "${cmake_generator_args[@]}"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_SYSTEM_NAME=Darwin
        -DCMAKE_SYSTEM_PROCESSOR=armv7
        -DCMAKE_OSX_SYSROOT="$sdk_dir"
        -DCMAKE_OSX_ARCHITECTURES=armv7
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target"
        -DCMAKE_C_COMPILER="$host_cc"
        -DCMAKE_CXX_COMPILER="$host_cxx"
        -DCMAKE_C_COMPILER_TARGET="$triple"
        -DCMAKE_CXX_COMPILER_TARGET="$triple"
        -DCMAKE_C_FLAGS="${linker_search_flag} ${repo_prefix_map_flags}"
        -DCMAKE_CXX_FLAGS="$cxx_flags"
        -DCMAKE_EXE_LINKER_FLAGS="$linker_search_flag"
        -DCMAKE_SHARED_LINKER_FLAGS="$linker_search_flag"
        -DCMAKE_MODULE_LINKER_FLAGS="$linker_search_flag"
        -DCMAKE_AR="$llvm_ar"
        -DCMAKE_RANLIB="$llvm_ranlib"
        -DCMAKE_NM="$llvm_nm"
        -DLLVM_ENABLE_PROJECTS=clang
        -DLLVM_TARGETS_TO_BUILD=ARM
        -DLLVM_DEFAULT_TARGET_TRIPLE="$triple"
        -DLLVM_HOST_TRIPLE="$triple"
        -DLLVM_TABLEGEN="${native_build_dir}/bin/llvm-tblgen"
        -DCLANG_TABLEGEN="${native_build_dir}/bin/clang-tblgen"
        -DLLVM_BUILD_TOOLS=ON
        -DCLANG_BUILD_TOOLS=ON
        -DLLVM_BUILD_UTILS=OFF
        -DLLVM_INCLUDE_TESTS=OFF
        -DCLANG_INCLUDE_TESTS=OFF
        -DLLVM_INCLUDE_EXAMPLES=OFF
        -DLLVM_INCLUDE_BENCHMARKS=OFF
        -DLLVM_INCLUDE_DOCS=OFF
        -DLLVM_ENABLE_BINDINGS=OFF
        -DLLVM_ENABLE_FFI=OFF
        -DLLVM_ENABLE_LIBEDIT=OFF
        -DLLVM_ENABLE_LIBXML2=OFF
        -DLLVM_ENABLE_TERMINFO=OFF
        -DLLVM_ENABLE_ZLIB=OFF
        -DLLVM_ENABLE_ZSTD=OFF
        -DLLVM_ENABLE_THREADS=OFF
        -DLLVM_ENABLE_EH=OFF
        -DLLVM_ENABLE_RTTI=OFF
        -DLLVM_APPEND_VC_REV=OFF
        -DBUILD_SHARED_LIBS=OFF
    )
    run_logged "${logs_dir}/configure-ios-armv7.log" "${cmake_args[@]}"
}

build_armv7() {
    run_logged "${logs_dir}/build-ios-armv7-clang.log" \
        cmake --build "$target_build_dir" \
        --target clang \
        --parallel "$jobs"

    [[ -x "${target_build_dir}/bin/clang-15" ]] ||
        die "the armv7 clang executable was not built"
}

package_armv7() {
    local -a driver_aliases=(
        clang
        clang++
        clang++-15
        clang-cpp
        cc
        c++
    )
    local driver_name=""
    local arclite_actual_sha256=""
    local arclite_metadata=""
    local arclite_symbols=""
    local lipo_tool=""
    local llvm_nm=""
    local llvm_strip=""
    local ldid_tool=""
    local package_name="clang-${llvm_version}-armv7-apple-ios${deployment_target}"
    local stage_parent="${work_dir}/stage"
    local stage_dir="${stage_parent}/${package_name}"
    local artifact_dir="${work_dir}/artifacts"
    local artifact_path="${artifact_dir}/${package_name}.tar.gz"
    local packaged_clang="${stage_dir}/bin/clang-15"
    local resource_source="${target_build_dir}/lib/clang/${llvm_version}/include"
    local arclite_archive="${stage_dir}/lib/arc/libarclite_iphoneos.a"

    lipo_tool="$(resolve_tool "${cctools_bin}/lipo" lipo)" ||
        die "lipo is required to verify Apple's ARCLite archive"
    llvm_nm="$(resolve_requested_tool "$llvm_nm_input" /usr/bin/llvm-nm-14 llvm-nm llvm-nm-14)" ||
        die "llvm-nm is required to verify ARCLite"
    llvm_strip="$(resolve_requested_tool "$llvm_strip_input" /usr/bin/llvm-strip-14 llvm-strip llvm-strip-14)" ||
        die "an LLVM strip implementation with Mach-O support is required"
    command -v sha256sum >/dev/null 2>&1 ||
        die "sha256sum is required to verify Apple's ARCLite archive"
    command -v strings >/dev/null 2>&1 ||
        die "strings is required to verify Apple's ARCLite archive"
    [[ -f "$arclite_archive_source" ]] ||
        die "Apple ARCLite archive is missing: ${arclite_archive_source}"
    arclite_actual_sha256="$(sha256sum "$arclite_archive_source" | awk '{print $1}')"
    [[ "$arclite_actual_sha256" == "$arclite_archive_sha256" ]] ||
        die "unexpected Apple ARCLite archive SHA-256: ${arclite_actual_sha256}"
    "$lipo_tool" "$arclite_archive_source" -verify_arch armv7 ||
        die "Apple ARCLite archive has no armv7 slice"
    arclite_metadata="$(strings "$arclite_archive_source")"
    grep -Fq -- '-miphoneos-version-min=4.3' <<< "$arclite_metadata" ||
        die "Apple ARCLite armv7 metadata does not declare iOS 4.3"
    arclite_symbols="$("$llvm_nm" "$arclite_archive_source")"
    grep -Fq "_OBJC_METACLASS_\$___ARCLite__" <<< "$arclite_symbols" ||
        die "Apple ARCLite archive has no __ARCLite__ implementation"
    if grep -Eq '[[:space:]]_objc_loadClassref$' <<< "$arclite_symbols"; then
        die "Apple ARCLite archive requires objc_loadClassref from a newer SDK"
    fi
    [[ -d "$resource_source" ]] ||
        die "Clang resource headers were not built: ${resource_source}"

    case "$stage_dir" in
        "${work_dir}"/stage/*)
            ;;
        *)
            die "refusing to replace unsafe stage path: ${stage_dir}"
            ;;
    esac
    if [[ -e "$stage_dir" || -L "$stage_dir" ]]; then
        rm -rf -- "$stage_dir"
    fi

    mkdir -p \
        "${stage_dir}/bin" \
        "${stage_dir}/lib/arc" \
        "${stage_dir}/lib/clang/${llvm_version}" \
        "${stage_dir}/share/doc/clang-${llvm_version}"

    install -m 0644 "$arclite_archive_source" "$arclite_archive"

    install -m 0755 "${target_build_dir}/bin/clang-15" "$packaged_clang"
    "$llvm_strip" --strip-all "$packaged_clang"
    if LC_ALL=C grep -aFq -- "${repo_root}/" "$packaged_clang" ||
        strings "$packaged_clang" | grep -Eq \
          '(^|[[:space:]"=:,])(-{1,2}[[:alnum:]_-]+=?){0,1}/[^[:space:]]*build-release/Intermediates/'; then
        die "packaged clang embeds an absolute container build path"
    fi
    cp -R "$resource_source" "${stage_dir}/lib/clang/${llvm_version}/include"
    install -m 0644 "${source_dir}/llvm/LICENSE.TXT" \
        "${stage_dir}/share/doc/clang-${llvm_version}/LICENSE.TXT"

    if [[ "$sign_artifact" == "true" ]]; then
        if ldid_tool="$(resolve_requested_tool "$ldid_input" ldid)"; then
            "$ldid_tool" -S "$packaged_clang"
        else
            printf '%s\n' \
                "warning: ldid is unavailable; the staged clang is not pseudo-signed" >&2
        fi
    fi
    for driver_name in "${driver_aliases[@]}"; do
        ln -s clang-15 "${stage_dir}/bin/${driver_name}"
    done

    {
        printf 'LLVM version: %s\n' "$llvm_version"
        printf 'Source commit: %s\n' "$source_commit"
        printf 'Target triple: %s\n' "$triple"
        printf 'Minimum iOS: %s\n' "$deployment_target"
        printf 'SDK: %s\n' "${sdk_dir##*/}"
        printf 'LLVM targets: ARM\n'
        printf 'Threads: disabled\n'
        printf 'Source patch: %s\n' "$(basename "$patch_file")"
        printf 'ARC back-deployment runtime: Apple Xcode 6.4 %s\n' \
            "$(basename "$arclite_archive_source")"
        printf 'ARC back-deployment runtime SHA-256: %s\n' \
            "$arclite_archive_sha256"
        printf 'ARC back-deployment minimum iOS: %s\n' "$arclite_deployment_target"
    } > "${stage_dir}/BUILD-INFO.txt"

    mkdir -p "$artifact_dir"
    tar -czf "$artifact_path" -C "$stage_parent" "$package_name"
    printf 'Staged toolchain: %s\n' "$stage_dir"
    printf 'Archive: %s (%s bytes)\n' \
        "$artifact_path" "$(wc -c < "$artifact_path" | tr -d '[:space:]')"
}

prepare_source

case "$action" in
    native|configure|build|package)
        prepare_build_cache
        ;;
esac

case "$action" in
    source)
        ;;
    native)
        ensure_native_tools
        ;;
    configure)
        ensure_native_tools
        configure_armv7
        ;;
    build)
        ensure_native_tools
        configure_armv7
        build_armv7
        ;;
    package)
        ensure_native_tools
        configure_armv7
        build_armv7
        package_armv7
        ;;
    package-from-cache)
        [[ -x "${target_build_dir}/bin/clang-15" ]] ||
            die "cached armv7 clang is missing; run the package action first"
        package_armv7
        ;;
esac

printf 'Completed action "%s" in %s\n' "$action" "$work_dir"
