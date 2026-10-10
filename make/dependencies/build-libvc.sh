#!/bin/bash
# Generate the upstream lexer/parser on the host, then build static C libraries.
set -euo pipefail
mode="$1"
deps="$2"
toolchain="${3:-/osxcross/legacy/target}"
support="$(cd "$(dirname "$0")" && pwd)"
src="$deps/libvc-source"
archive="$deps/libvc-013.tar.gz"
mkdir -p "$deps"
if [ "$mode" = prepare ] || [ "$mode" = prepare-archive ]; then
  if [ "$mode" = prepare ]; then
    checkout="${ALTIVEC_DEPENDENCY_SOURCE:?Set ALTIVEC_DEPENDENCY_SOURCE}"
    test -f "$checkout/src/vc.c"
    tar -czf "$archive.tmp" --exclude=./.git \
      --transform='s,^\.,libvc-013,' -C "$checkout" .
    mv "$archive.tmp" "$archive"
  fi
  rm -rf "$src"
  mkdir -p "$src"
  tar -xzf "$archive" -C "$src" --strip-components=1
  patch --batch --forward -d "$src" -p1 < "$support/libvc-parser.patch"
  # Match src/Makefile.am: AM_YFLAGS=-d and AM_LFLAGS=-i.
  bison -d -o "$src/src/vc_parse.c" "$src/src/vc_parse.y"
  flex -i -o "$src/src/vc_scan.c" "$src/src/vc_scan.l"
  touch "$deps/libvc-source.stamp"
  exit
fi
out="$deps/libvc-$mode"
mkdir -p "$out"
flags=(-std=c99 -O2 -D_POSIX_C_SOURCE=200809L -include "$support/libvc-portability.h"
       -I"$src/src")
case "$mode" in
  host) compiler="${HOST_CC:-cc}"; archiver=ar; ranlib=ranlib ;;
  ppc|i386)
    if [ "$mode" = ppc ]; then compiler="$toolchain/bin/oppc32-gcc"
    else compiler="$toolchain/bin/o32-gcc"; fi
    archiver="$toolchain/bin/i386-apple-darwin9-ar"
    ranlib="$toolchain/bin/i386-apple-darwin9-ranlib"
    flags+=(-arch "$mode" -isysroot "${ALTIVEC_DEPENDENCY_SDK:-$toolchain/SDK/MacOSX10.5.sdk}"
            -mmacosx-version-min=${ALTIVEC_DEPENDENCY_MIN:-10.4} -fno-stack-protector -D_DARWIN_C_SOURCE)
    ;;
  ios-armv7|ios-arm64)
    arch="${mode#ios-}"; minimum=5.0; [ "$arch" != arm64 ] || minimum=7.0
    compiler=/usr/bin/clang; archiver="$toolchain/bin/ar"; ranlib="$toolchain/bin/ranlib"
    flags+=(-target "$arch-apple-ios${ALTIVEC_DEPENDENCY_MIN:-$minimum}" -isysroot "${ALTIVEC_DEPENDENCY_SDK:-$toolchain/SDK/iPhoneOS8.4.sdk}" -D_DARWIN_C_SOURCE)
    ;;
  x86_64|arm64)
    compiler=$(compgen -G "$toolchain/bin/$mode-apple-darwin*-clang" | head -1)
    minimum=10.9; [ "$mode" != arm64 ] || minimum=11.0
    archiver="$toolchain/bin/ar"; ranlib="$toolchain/bin/ranlib"
    flags+=(-target "$mode-apple-macos${ALTIVEC_DEPENDENCY_MIN:-$minimum}" -isysroot "${ALTIVEC_DEPENDENCY_SDK:-$toolchain/SDK/MacOSX11.3.sdk}" -D_DARWIN_C_SOURCE)
    ;;
  *) exit 1 ;;
esac
compiler="${ALTIVEC_DEPENDENCY_CC:-$compiler}"
for name in vc vc_parse vc_scan; do
  "$compiler" "${flags[@]}" -c "$src/src/$name.c" -o "$out/$name.o"
done
"$compiler" "${flags[@]}" -c "$support/libvc-portability.c" -o "$out/portability.o"
rm -f "$out/libvc.a"
"$archiver" rcs "$out/libvc.a" "$out/vc.o" "$out/vc_parse.o" \
  "$out/vc_scan.o" "$out/portability.o"
"$ranlib" "$out/libvc.a"
