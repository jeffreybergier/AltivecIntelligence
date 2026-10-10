#!/bin/bash
# Patch build copies only; leave the pinned submodule untouched.
set -euo pipefail
mode="$1"
deps="$2"
toolchain="${3:-/osxcross/legacy/target}"
target="${4:-ical}"
case "$target" in ical|icalvcal) ;; *) exit 1 ;; esac
version=3.0.20
archive="$deps/libical-$version.tar.gz"
src="$deps/libical-$version"
mkdir -p "$deps"
if [ "$mode" = prepare ] || [ "$mode" = prepare-archive ]; then
  if [ "$mode" = prepare ]; then
    checkout="${ALTIVEC_DEPENDENCY_SOURCE:?Set ALTIVEC_DEPENDENCY_SOURCE}"
    if [ ! -f "$checkout/CMakeLists.txt" ]; then
      echo 'libical is missing. Run: git submodule update --init --recursive' >&2
      exit 1
    fi
    tar -czf "$archive.tmp" --exclude=./.git \
      --transform="s,^\.,libical-$version," -C "$checkout" .
    mv "$archive.tmp" "$archive"
  fi
  # Recreate the build copy so removed upstream files cannot survive a checkout.
  rm -rf "$src"
  tar -xzf "$archive" -C "$deps"
  patch --batch --forward -d "$src" -p1 < "$(dirname "$0")/libical-legacy.patch"
  python3 - "$src" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
p = root / 'CMakeLists.txt'
p.write_text(p.read_text().replace('-Wtype-limits', '').replace('-Wno-deprecated', ''))
for p in list((root / 'src/libical').glob('*.c')) + list((root / 'src/libicalvcal').glob('*.c')):
    p.write_text(''.join(line for line in p.read_text().splitlines(True)
                       if not line.lstrip().startswith('#pragma GCC diagnostic')))
PY
  touch "$deps/libical-source.stamp"
  exit
fi
out="$deps/libical-$mode"
args=(-DSTATIC_ONLY=ON -DWITH_CXX_BINDINGS=OFF -DICAL_GLIB=OFF
      -DICAL_BUILD_DOCS=OFF -DLIBICAL_BUILD_TESTING=OFF
      -DCMAKE_DISABLE_FIND_PACKAGE_ICU=TRUE
      -DCMAKE_DISABLE_FIND_PACKAGE_BerkeleyDB=TRUE
      -DUSE_BUILTIN_TZDATA=ON -DCMAKE_BUILD_TYPE=Release)
if [ "$mode" = ios-armv7 ] || [ "$mode" = ios-arm64 ]; then
  arch="${mode#ios-}"; minimum=5.0; [ "$arch" != arm64 ] || minimum=7.0
  args+=(-DCMAKE_SYSTEM_NAME=Generic "-DCMAKE_SYSTEM_PROCESSOR=$arch"
         -DCMAKE_C_COMPILER=/usr/bin/clang
         "-DCMAKE_AR=$toolchain/bin/ar" "-DCMAKE_RANLIB=$toolchain/bin/ranlib"
         "-DCMAKE_C_FLAGS=-target $arch-apple-ios${ALTIVEC_DEPENDENCY_MIN:-$minimum} -isysroot ${ALTIVEC_DEPENDENCY_SDK:-$toolchain/SDK/iPhoneOS8.4.sdk} -B$toolchain/bin -std=c99")
elif [ "$mode" = x86_64 ] || [ "$mode" = arm64 ]; then
  compiler=$(compgen -G "$toolchain/bin/$mode-apple-darwin*-clang" | head -1)
  minimum=10.9; [ "$mode" != arm64 ] || minimum=11.0
  args+=(-DCMAKE_SYSTEM_NAME=Darwin "-DCMAKE_SYSTEM_PROCESSOR=$mode"
         "-DCMAKE_C_COMPILER=$compiler" "-DCMAKE_AR=$toolchain/bin/ar"
         "-DCMAKE_RANLIB=$toolchain/bin/ranlib"
         "-DCMAKE_OSX_SYSROOT=${ALTIVEC_DEPENDENCY_SDK:-$toolchain/SDK/MacOSX11.3.sdk}"
         "-DCMAKE_OSX_ARCHITECTURES=$mode" "-DCMAKE_OSX_DEPLOYMENT_TARGET=${ALTIVEC_DEPENDENCY_MIN:-$minimum}"
         "-DCMAKE_C_FLAGS=-std=c99" "-DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=/usr/bin/ld64.lld")
elif [ "$mode" != host ]; then
  case "$mode" in
    ppc) compiler="$toolchain/bin/oppc32-gcc"; processor=powerpc ;;
    i386) compiler="$toolchain/bin/o32-gcc"; processor=i386 ;;
    *) exit 1 ;;
  esac
  args+=(-DCMAKE_SYSTEM_NAME=Darwin "-DCMAKE_SYSTEM_PROCESSOR=$processor"
         "-DCMAKE_C_COMPILER=$compiler"
         "-DCMAKE_AR=$toolchain/bin/i386-apple-darwin9-ar"
         "-DCMAKE_RANLIB=$toolchain/bin/i386-apple-darwin9-ranlib"
         "-DCMAKE_OSX_SYSROOT=${ALTIVEC_DEPENDENCY_SDK:-$toolchain/SDK/MacOSX10.5.sdk}"
         "-DCMAKE_OSX_ARCHITECTURES=$mode" "-DCMAKE_OSX_DEPLOYMENT_TARGET=${ALTIVEC_DEPENDENCY_MIN:-10.4}"
         # GCC 4.2 misreports optimized assertions and constant branches as
         # unreachable. Keep -Wall/-Wextra and modern unreachable checks.
         -DHAVE_GCC_UNREACHABLE_CODE=FALSE
         '-DCMAKE_C_FLAGS=-std=c99 -fno-stack-protector')
fi
if [ -n "${ALTIVEC_DEPENDENCY_CC:-}" ]; then args+=("-DCMAKE_C_COMPILER=$ALTIVEC_DEPENDENCY_CC"); fi
if ! cmake -S "$src" -B "$out" "${args[@]}" > "$deps/libical-$mode-configure.log" 2>&1; then
  cat "$deps/libical-$mode-configure.log"; exit 1
fi
if ! (unset MAKEFLAGS MFLAGS; cmake --build "$out" --target "$target" --parallel 4) > "$deps/libical-$mode-build.log" 2>&1; then
  cat "$deps/libical-$mode-build.log"; exit 1
fi
# Some CMake versions cache the host's archive rule while identifying this old
# compiler. Repack with cctools so ld64 receives BSD, not GNU, archive members.
if [ "$mode" = ppc ] || [ "$mode" = i386 ]; then
  libraries=(ical)
  if [ "$target" = icalvcal ]; then libraries+=(icalvcal); fi
  for library in "${libraries[@]}"; do
    rm -f "$out/lib/lib$library-legacy.a"
    "$toolchain/bin/i386-apple-darwin9-ar" rcs "$out/lib/lib$library-legacy.a" "$out"/src/lib"$library"/CMakeFiles/"$library".dir/*.o
    "$toolchain/bin/i386-apple-darwin9-ranlib" "$out/lib/lib$library-legacy.a"
    mv "$out/lib/lib$library-legacy.a" "$out/lib/lib$library.a"
  done
fi
