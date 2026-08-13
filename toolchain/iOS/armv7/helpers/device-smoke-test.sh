#!/usr/bin/env bash

set -euo pipefail

if [[ "${ALTIVEC_DEVICE_SMOKE_REMOTE:-0}" != "1" ]]; then
  if (($# > 1)); then
    printf 'Usage: %s [ssh-host]\n' "$(basename "$0")" >&2
    exit 2
  fi

  readonly device_host="${1:-koolphone5}"
  exec ssh -o BatchMode=yes "$device_host" \
    'ALTIVEC_DEVICE_SMOKE_REMOTE=1 bash -l -c "$(cat)"' < "$0"
fi

unset ALTIVEC_DEVICE_SMOKE_REMOTE

readonly smoke_dir="/var/tmp/altivec-toolchain-smoke.$$"

cleanup() {
  case "$smoke_dir" in
    /var/tmp/altivec-toolchain-smoke.*)
      if [[ -d "$smoke_dir" && ! -L "$smoke_dir" ]]; then
        rm -r "$smoke_dir"
      fi
      ;;
  esac
}
trap cleanup EXIT

umask 077
mkdir "$smoke_dir"
cd "$smoke_dir"

printf '%s\n' 'Resolved installed tools:'
for tool in clang ld magick convert identify mogrify otool; do
  resolved="$(which "$tool")"
  case "$resolved" in
    /var/altivec/bin/*)
      printf '  %-8s %s\n' "$tool" "$resolved"
      ;;
    *)
      printf 'error: %s resolved outside /var/altivec: %s\n' \
        "$tool" "$resolved" >&2
      exit 1
      ;;
  esac
done

printf 'int main(void) { return 0; }\n' > main.c
printf 'void altivec_system_stub(void) {}\n' > system-stub.c
clang --target=armv7-apple-ios5.0 -c main.c -o main.o
clang --target=armv7-apple-ios5.0 -c system-stub.c -o system-stub.o

# MH_OBJECT files cannot carry an embedded signature. NO_LDID disables only
# cctools-port's post-link signing hook; the linker still parses every object.
NO_LDID=1 ld -r -arch armv7 -o combined.o main.o

# iOS keeps libSystem in the dyld shared cache rather than as a linkable file.
# A minimal test dylib lets the smoke executable satisfy ld64's libSystem rule.
ld -arch armv7 -dylib -iphoneos_version_min 5.0 \
  -install_name /usr/lib/libSystem.B.dylib \
  -o libSystem.dylib system-stub.o
ld -arch armv7 -iphoneos_version_min 5.0 -e _main \
  -L. -lSystem -o smoke-executable main.o
ld -arch armv7 -dylib -iphoneos_version_min 5.0 \
  -install_name @rpath/libsmoke.dylib \
  -L. -lSystem -o libsmoke.dylib system-stub.o
clang --target=armv7-apple-ios5.0 -nostdlib -Wl,-e,_main \
  main.o -L. -lSystem -o clang-smoke-executable

file main.o combined.o smoke-executable clang-smoke-executable libsmoke.dylib

load_commands="$(otool -l smoke-executable)"
if ! awk '
    $1 == "cmd" && $2 == "LC_VERSION_MIN_IPHONEOS" {
      in_version_command = 1
      next
    }
    in_version_command && $1 == "version" && $2 == "5.0" {
      found_version = 1
    }
    END { exit(found_version ? 0 : 1) }
  ' <<< "$load_commands"; then
  printf '%s\n' 'error: linker did not preserve the iOS 5.0 target' >&2
  exit 1
fi
[[ "$load_commands" == *LC_UNIXTHREAD* && "$load_commands" != *LC_MAIN* ]] || {
  printf '%s\n' 'error: linker did not use the pre-iOS-6 entry-point path' >&2
  exit 1
}

magick -size 32x24 xc:red source.png
identify -format 'PNG %m %wx%h\n' source.png
convert source.png -quality 82 output.jpg
identify -format 'JPEG %m %wx%h\n' output.jpg
mogrify -resize '16x12!' output.jpg
identify -format 'RESIZED-JPEG %m %wx%h\n' output.jpg
magick output.jpg -resize '8x6!' resized.png
identify -format 'CONVERTED-PNG %m %wx%h\n' resized.png

magick -list configure > configure.out
if grep -E \
    '(build-release/Intermediates|/osxcross/|/usr/bin/clang(\+\+)?-[0-9]+|dependency-sysroot)' \
    configure.out; then
  printf '%s\n' 'error: ImageMagick exposes build-host paths' >&2
  exit 1
fi
[[ ! -e /var/altivec/bin/MagickCore-config ]] ||
  { printf '%s\n' 'error: MagickCore-config should not be installed' >&2; exit 1; }
[[ ! -e /var/altivec/bin/MagickWand-config ]] ||
  { printf '%s\n' 'error: MagickWand-config should not be installed' >&2; exit 1; }

printf '%s\n' 'Altivec Toolchain device smoke test passed.'
