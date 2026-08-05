#!/usr/bin/env bash

set -euo pipefail

sdk_dir="/osxcross/target/SDK/iPhoneOS8.4.sdk"
cctools_bin="/osxcross/target/bin"
cc="/usr/bin/clang-14"
cxx="/usr/bin/clang++-14"
ldid_signer="ldid"
fakeroot_tool="fakeroot"
dpkg_deb_tool="dpkg-deb"

usage() {
  printf '%s\n' \
    "Usage: $(basename "$0") [options]" \
    "" \
    "Options:" \
    "  --sdk <path>          iPhoneOS SDK directory." \
    "  --cctools-bin <path>  Directory containing the Mach-O tools." \
    "  --cc <path>           Host C compiler." \
    "  --cxx <path>          Host C++ compiler." \
    "  --ldid <tool>         ldid executable or command name." \
    "  --fakeroot <tool>     fakeroot executable or command name." \
    "  --dpkg-deb <tool>     dpkg-deb executable or command name." \
    "  -h, --help            Show this help."
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
    --sdk)
      require_value "$@"
      sdk_dir="$2"
      shift 2
      ;;
    --cctools-bin)
      require_value "$@"
      cctools_bin="$2"
      shift 2
      ;;
    --cc)
      require_value "$@"
      cc="$2"
      shift 2
      ;;
    --cxx)
      require_value "$@"
      cxx="$2"
      shift 2
      ;;
    --ldid)
      require_value "$@"
      ldid_signer="$2"
      shift 2
      ;;
    --fakeroot)
      require_value "$@"
      fakeroot_tool="$2"
      shift 2
      ;;
    --dpkg-deb)
      require_value "$@"
      dpkg_deb_tool="$2"
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

for tool in bash bison cmake curl unzip tar patch make perl pkg-config \
  sha256sum realpath file strings "$ldid_signer" "$fakeroot_tool" "$dpkg_deb_tool"; do
  command -v "$tool" >/dev/null 2>&1 ||
    die "required tool not found: ${tool}"
done

[[ -x "$cc" ]] || die "C compiler not found: ${cc}"
[[ -x "$cxx" ]] || die "C++ compiler not found: ${cxx}"
[[ -d "$sdk_dir" ]] || die "iPhoneOS SDK not found: ${sdk_dir}"

for tool in ar ranlib nm strip otool; do
  macho_tool="${cctools_bin}/x86_64-apple-darwin9-${tool}"
  [[ -x "$macho_tool" ]] || die "Mach-O tool not found: ${macho_tool}"
done

printf '%s\n' "Core-tools build prerequisites are available."
