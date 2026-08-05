#!/usr/bin/env bash

set -euo pipefail

# This file is both the local SSH launcher and the remote test program.  Keeping
# the tests self-contained means the phone does not retain a copy of the script.
if [[ "${ALTIVEC_DEVICE_TOOLS_SMOKE_REMOTE:-0}" != "1" ]]; then
  if (($# > 1)); then
    printf 'Usage: %s [ssh-host]\n' "$(basename "$0")" >&2
    exit 2
  fi

  readonly device_host="${1:-koolphone5}"
  exec ssh -o BatchMode=yes -o ConnectTimeout=10 "$device_host" \
    'ALTIVEC_DEVICE_TOOLS_SMOKE_REMOTE=1 bash -l -c "$(cat)"' < "$0"
fi

unset ALTIVEC_DEVICE_TOOLS_SMOKE_REMOTE

readonly install_prefix="${ALTIVEC_INSTALL_PREFIX:-/var/altivec}"
readonly bin_dir="${install_prefix}/bin"
readonly smoke_dir="/var/tmp/altivec-device-tools-smoke.$$"
readonly cctools_prefix="${bin_dir}/arm-apple-darwin11-"
readonly expected_regular_count=87
readonly expected_alias_count=59
readonly expected_entry_count=146

# Keep the command and its test together so every regular executable in the
# public bin directory has exactly one test below.  The order is intentional:
# clang and ld create Mach-O fixtures consumed by the remaining cctools tests.
readonly regular_tests="
clang-15:test_clang_15
arm-apple-darwin11-ld:test_cctools_ld
arm-apple-darwin11-ObjectDump:test_cctools_objectdump
arm-apple-darwin11-ar:test_cctools_ar
arm-apple-darwin11-as:test_cctools_as
arm-apple-darwin11-bitcode_strip:test_cctools_bitcode_strip
arm-apple-darwin11-check_dylib:test_cctools_check_dylib
arm-apple-darwin11-checksyms:test_cctools_checksyms
arm-apple-darwin11-cmpdylib:test_cctools_cmpdylib
arm-apple-darwin11-codesign_allocate:test_cctools_codesign_allocate
arm-apple-darwin11-ctf_insert:test_cctools_ctf_insert
arm-apple-darwin11-dyldinfo:test_cctools_dyldinfo
arm-apple-darwin11-indr:test_cctools_indr
arm-apple-darwin11-inout:test_cctools_inout
arm-apple-darwin11-install_name_tool:test_cctools_install_name_tool
arm-apple-darwin11-libtool:test_cctools_libtool
arm-apple-darwin11-lipo:test_cctools_lipo
arm-apple-darwin11-machocheck:test_cctools_machocheck
arm-apple-darwin11-makerelocs:test_cctools_makerelocs
arm-apple-darwin11-mtoc:test_cctools_mtoc
arm-apple-darwin11-mtor:test_cctools_mtor
arm-apple-darwin11-nm:test_cctools_nm
arm-apple-darwin11-nmedit:test_cctools_nmedit
arm-apple-darwin11-otool:test_cctools_otool
arm-apple-darwin11-pagestuff:test_cctools_pagestuff
arm-apple-darwin11-ranlib:test_cctools_ranlib
arm-apple-darwin11-redo_prebinding:test_cctools_redo_prebinding
arm-apple-darwin11-seg_addr_table:test_cctools_seg_addr_table
arm-apple-darwin11-seg_hack:test_cctools_seg_hack
arm-apple-darwin11-segedit:test_cctools_segedit
arm-apple-darwin11-size:test_cctools_size
arm-apple-darwin11-strings:test_cctools_strings
arm-apple-darwin11-strip:test_cctools_strip
arm-apple-darwin11-unwinddump:test_cctools_unwinddump
arm-apple-darwin11-vtool:test_cctools_vtool
altivec-app:test_altivec_app
altivec-lib:test_altivec_lib
altivec-sdk:test_altivec_sdk
awk:test_awk
bzip2:test_bzip2
clear:test_clear
cmp:test_cmp
curl:test_curl
diff:test_diff
diff3:test_diff3
file:test_file
find:test_find
git:test_git
git-cvsserver:test_git_cvsserver
git-shell:test_git_shell
grep:test_grep
gzip:test_gzip
hexdump:test_hexdump
hostname:test_hostname
htop:test_htop
ifconfig:test_ifconfig
jq:test_jq
killall:test_killall
ldid:test_ldid
less:test_less
logger:test_logger
magick:test_magick
make:test_make
man:test_man
nc:test_nc
openssl:test_openssl
patch:test_patch
ping:test_ping
pkill:test_pkill
plistutil:test_plistutil
ps:test_ps
realpath:test_realpath
reset:test_reset
scalar:test_scalar
sed:test_sed
sqlite3:test_sqlite3
tar:test_tar
tree:test_tree
zip:test_zip
unzip:test_unzip
vi:test_vi
watch:test_watch
wc:test_wc
which:test_which
xargs:test_xargs
xxd:test_xxd
xz:test_xz
"

# Alias tests validate both the link target and the behavior that depends on
# argv[0] (for example pgrep, xzcat, and ImageMagick's compatibility names).
readonly alias_pairs="
ObjectDump:arm-apple-darwin11-ObjectDump
animate:magick
ar:arm-apple-darwin11-ar
as:arm-apple-darwin11-as
bitcode_strip:arm-apple-darwin11-bitcode_strip
c++:clang-15
cc:clang-15
check_dylib:arm-apple-darwin11-check_dylib
checksyms:arm-apple-darwin11-checksyms
clang++-15:clang-15
clang++:clang-15
clang-cpp:clang-15
clang:clang-15
cmpdylib:arm-apple-darwin11-cmpdylib
codesign_allocate:arm-apple-darwin11-codesign_allocate
compare:magick
composite:magick
conjure:magick
convert:magick
ctf_insert:arm-apple-darwin11-ctf_insert
display:magick
dyldinfo:arm-apple-darwin11-dyldinfo
git-receive-pack:git
git-upload-archive:git
git-upload-pack:git
identify:magick
import:magick
indr:arm-apple-darwin11-indr
inout:arm-apple-darwin11-inout
install_name_tool:arm-apple-darwin11-install_name_tool
ld:arm-apple-darwin11-ld
ldid2:ldid
libtool:arm-apple-darwin11-libtool
lipo:arm-apple-darwin11-lipo
machocheck:arm-apple-darwin11-machocheck
magick-script:magick
makerelocs:arm-apple-darwin11-makerelocs
mogrify:magick
montage:magick
mtoc:arm-apple-darwin11-mtoc
mtor:arm-apple-darwin11-mtor
nm:arm-apple-darwin11-nm
nmedit:arm-apple-darwin11-nmedit
otool:arm-apple-darwin11-otool
pagestuff:arm-apple-darwin11-pagestuff
pgrep:pkill
ranlib:arm-apple-darwin11-ranlib
redo_prebinding:arm-apple-darwin11-redo_prebinding
seg_addr_table:arm-apple-darwin11-seg_addr_table
seg_hack:arm-apple-darwin11-seg_hack
segedit:arm-apple-darwin11-segedit
size:arm-apple-darwin11-size
stream:magick
strings:arm-apple-darwin11-strings
strip:arm-apple-darwin11-strip
unwinddump:arm-apple-darwin11-unwinddump
unxz:xz
vtool:arm-apple-darwin11-vtool
xzcat:xz
"
readonly excluded_tools="
netstat
plutil
tput
time
script
renice
"

cleanup() {
  case "$smoke_dir" in
    /var/tmp/altivec-device-tools-smoke.*)
      if [[ -d "$smoke_dir" && ! -L "$smoke_dir" ]]; then
        /bin/rm -r "$smoke_dir"
      fi
      ;;
  esac
}
trap cleanup EXIT

[[ -d "$bin_dir" ]] || {
  printf 'error: Altivec Toolchain is not installed at %s\n' \
    "$install_prefix" >&2
  exit 1
}

case "${PATH-}" in
  "$bin_dir"|"$bin_dir":*) ;;
  *)
    printf 'error: login profile did not prepend %s to PATH: %s\n' \
      "$bin_dir" "${PATH-<unset>}" >&2
    exit 1
    ;;
esac

regular_count=0
alias_count=0
inventory_failed=0

for test_spec in $regular_tests; do
  tool="${test_spec%%:*}"
  resolved_path="$(command -v "$tool" 2>/dev/null || true)"
  regular_count=$((regular_count + 1))
  if [[ ! -f "${bin_dir}/${tool}" || ! -x "${bin_dir}/${tool}" ||
      -L "${bin_dir}/${tool}" ]]; then
    printf 'error: regular tool is missing, not executable, or a link: %s\n' \
      "${bin_dir}/${tool}" >&2
    inventory_failed=1
  fi
  if [[ "$resolved_path" != "${bin_dir}/${tool}" ]]; then
    printf 'error: login PATH resolves %s as %s, expected %s\n' \
      "$tool" "${resolved_path:-<not found>}" "${bin_dir}/${tool}" >&2
    inventory_failed=1
  fi
done

for alias_spec in $alias_pairs; do
  alias_name="${alias_spec%%:*}"
  alias_target="${alias_spec#*:}"
  resolved_path="$(command -v "$alias_name" 2>/dev/null || true)"
  alias_count=$((alias_count + 1))
  if [[ ! -L "${bin_dir}/${alias_name}" ||
      ! "${bin_dir}/${alias_name}" -ef "${bin_dir}/${alias_target}" ]]; then
    printf 'error: alias does not resolve to its packaged target: %s -> %s\n' \
      "$alias_name" "$alias_target" >&2
    inventory_failed=1
  fi
  if [[ "$resolved_path" != "${bin_dir}/${alias_name}" ]]; then
    printf 'error: login PATH resolves %s as %s, expected %s\n' \
      "$alias_name" "${resolved_path:-<not found>}" \
      "${bin_dir}/${alias_name}" >&2
    inventory_failed=1
  fi
done

if [[ "$regular_count" -ne "$expected_regular_count" ||
    "$alias_count" -ne "$expected_alias_count" ]]; then
  printf 'error: verifier inventory has regular=%s aliases=%s; expected %s and %s\n' \
    "$regular_count" "$alias_count" \
    "$expected_regular_count" "$expected_alias_count" >&2
  inventory_failed=1
fi

actual_count=0
for installed_path in "$bin_dir"/*; do
  [[ -e "$installed_path" || -L "$installed_path" ]] || continue
  installed_name="${installed_path##*/}"
  listed=0
  for test_spec in $regular_tests; do
    [[ "${test_spec%%:*}" == "$installed_name" ]] && listed=1
  done
  for alias_spec in $alias_pairs; do
    [[ "${alias_spec%%:*}" == "$installed_name" ]] && listed=1
  done
  if [[ "$listed" -ne 1 ]]; then
    printf 'error: installed public command lacks a smoke test: %s\n' \
      "$installed_name" >&2
    inventory_failed=1
  fi
  actual_count=$((actual_count + 1))
done

if [[ "$actual_count" -ne "$expected_entry_count" ]]; then
  printf 'error: installed bin has %s entries; expected %s\n' \
    "$actual_count" "$expected_entry_count" >&2
  inventory_failed=1
fi

for tool in $excluded_tools; do
  [[ ! -e "${bin_dir}/${tool}" && ! -L "${bin_dir}/${tool}" ]] || {
    printf 'error: deferred or excluded tool is installed: %s\n' \
      "${bin_dir}/${tool}" >&2
    inventory_failed=1
  }
done
[[ "$inventory_failed" -eq 0 ]] || exit 1

umask 077
/bin/mkdir "$smoke_dir"
cd "$smoke_dir"

passed=0
skipped=0
failed=0

run_test() {
  local label="$1"
  local rc=0
  shift

  if "$@" >"${smoke_dir}/${label}.stdout" \
      2>"${smoke_dir}/${label}.stderr"; then
    printf 'PASS %s\n' "$label"
    passed=$((passed + 1))
    return 0
  else
    rc=$?
  fi

  if [[ "$rc" -eq 77 ]]; then
    printf 'SKIP %s' "$label"
    if [[ -s "${smoke_dir}/${label}.stderr" ]]; then
      printf ' (%s)' "$(/bin/cat "${smoke_dir}/${label}.stderr")"
    fi
    printf '\n'
    skipped=$((skipped + 1))
    return 0
  fi

  printf 'FAIL %s (exit %s)\n' "$label" "$rc" >&2
  if [[ -s "${smoke_dir}/${label}.stdout" ]]; then
    printf '%s\n' '--- stdout ---' >&2
    /bin/cat "${smoke_dir}/${label}.stdout" >&2
  fi
  if [[ -s "${smoke_dir}/${label}.stderr" ]]; then
    printf '%s\n' '--- stderr ---' >&2
    /bin/cat "${smoke_dir}/${label}.stderr" >&2
  fi
  failed=$((failed + 1))
  return 0
}

expect_usage_failure() {
  local output_file="$1"
  local output=""
  local rc=0
  shift

  "$@" >"$output_file" 2>&1 || rc=$?
  output="$(/bin/cat "$output_file")"
  [[ "$rc" -ne 0 && "$rc" -ne 126 && "$rc" -ne 127 &&
    "$rc" -ne 134 && "$rc" -ne 139 ]]
  [[ "$output" == *Usage:* || "$output" == *usage:* ]]
}

assert_no_newer_ios_imports() {
  local command_name="$1"
  local unavailable_before="$2"
  local symbol=""
  local imported_symbol=""
  local unsupported_symbols=""
  shift 2

  for symbol in "$@"; do
    # shellcheck disable=SC2016
    imported_symbol="$(
      "${cctools_prefix}otool" -Iv "${bin_dir}/${command_name}" |
        "$bin_dir/awk" -v expected="$symbol" \
          '$NF == expected { print $NF; exit }'
    )"
    if [[ -n "$imported_symbol" ]]; then
      unsupported_symbols+="${unsupported_symbols:+$'\n'}${imported_symbol}"
    fi
  done

  if [[ -n "$unsupported_symbols" ]]; then
    printf 'error: %s imports APIs unavailable before iOS %s:\n%s\n' \
      "$command_name" "$unavailable_before" "$unsupported_symbols" >&2
    return 1
  fi
}

test_clang_15() {
  printf '%s\n' \
    'const char smoke_marker[] = "altivec-smoke-marker";' \
    'int probe(void) { return 7; }' \
    'int main(void) { return probe(); }' > main.c
  printf 'void altivec_system_stub(void) {}\n' > system-stub.c
  printf '%s\n' \
    '.text' \
    '.globl _asm_probe' \
    '_asm_probe:' \
    '  bx lr' > probe.s
  printf 'extern "C" int cpp_probe(void) { return 9; }\n' > probe.cpp

  "$bin_dir/clang-15" --target=armv7-apple-ios4.3 \
    -c main.c -o main.o
  "$bin_dir/clang-15" --target=armv7-apple-ios4.3 \
    -c system-stub.c -o system-stub.o
  "$bin_dir/clang-15" --target=armv7-apple-ios4.3 \
    -c probe.cpp -o probe-cpp.o
  "$bin_dir/clang-15" --target=armv7-apple-ios4.3 \
    -fembed-bitcode -c main.c -o bitcode.o
  [[ -s main.o && -s system-stub.o && -s probe-cpp.o && -s bitcode.o ]]
}

test_cctools_ld() {
  local tool="${cctools_prefix}ld"
  local armv7_load_commands=""

  NO_LDID=1 "$tool" -r -arch armv7 -o combined.o main.o
  "$tool" -arch armv7 -dylib -iphoneos_version_min 4.3 \
    -install_name /usr/lib/libSystem.B.dylib \
    -o libSystem.dylib system-stub.o
  "$tool" -arch armv7 -iphoneos_version_min 4.3 -e _main \
    -L. -lSystem -o smoke-executable main.o
  "$tool" -arch armv7 -dylib -iphoneos_version_min 4.3 \
    -seg1addr 0x10000 -install_name @rpath/libprobe.dylib \
    -L. -lSystem -o libprobe.dylib system-stub.o
  NO_LDID=1 "$tool" -arch armv7 -preload -seg1addr 0x200 \
    -e _main -o preload main.o
  [[ -s combined.o && -s libSystem.dylib && -s smoke-executable &&
    -s libprobe.dylib && -s preload ]]

  armv7_load_commands="$("${cctools_prefix}otool" -l smoke-executable)"
  "$bin_dir/awk" '
    $1 == "cmd" && $2 == "LC_VERSION_MIN_IPHONEOS" {
      in_version_command = 1
      next
    }
    in_version_command && $1 == "version" && $2 == "4.3" {
      found_version = 1
    }
    END { exit(found_version ? 0 : 1) }
  ' <<< "$armv7_load_commands"
  [[ "$armv7_load_commands" == *LC_UNIXTHREAD* &&
    "$armv7_load_commands" != *LC_MAIN* ]]
}

test_cctools_objectdump() {
  "${cctools_prefix}ObjectDump" main.o > objectdump.output
  [[ -s objectdump.output ]]
}

test_cctools_ar() {
  local output=""
  "${cctools_prefix}ar" rcs cctools.a main.o
  output="$("${cctools_prefix}ar" t cctools.a)"
  [[ "$output" == *main.o* ]]
}

test_cctools_as() {
  "${cctools_prefix}as" -arch armv7 -o assembled.o probe.s
  [[ -s assembled.o ]]
}

test_cctools_bitcode_strip() {
  NO_LDID=1 "${cctools_prefix}bitcode_strip" \
    bitcode.o -r -o stripped-bitcode.o
  [[ -s stripped-bitcode.o ]]
}

test_cctools_check_dylib() {
  printf '10000 probe-entry\n' > dylib-addresses.txt
  "${cctools_prefix}check_dylib" libprobe.dylib \
    -install_name @rpath/libprobe.dylib \
    -seg_addr_table dylib-addresses.txt \
    -seg_addr_table_filename probe-entry
}

test_cctools_checksyms() {
  "${cctools_prefix}checksyms" smoke-executable
}

test_cctools_cmpdylib() {
  "${cctools_prefix}cmpdylib" libprobe.dylib libprobe.dylib
}

test_cctools_codesign_allocate() {
  "${cctools_prefix}codesign_allocate" \
    -i smoke-executable -a armv7 4096 -o allocated-executable
  [[ -s allocated-executable ]]
}

test_cctools_ctf_insert() {
  # A valid CTF payload is produced by Apple's unavailable ctfconvert tool.
  # Exercise this tool's parser safely; malformed CTF input can crash old
  # upstream versions and would not be a useful device smoke test.
  expect_usage_failure ctf-insert.usage "${cctools_prefix}ctf_insert"
}

test_cctools_dyldinfo() {
  "${cctools_prefix}dyldinfo" -export libprobe.dylib > dyldinfo.output
  [[ -s dyldinfo.output ]]
}

test_cctools_indr() {
  printf 'freshalias\n' > indr.names
  "${cctools_prefix}indr" -n indr.names main.o indr.o
  [[ -s indr.o ]]
}

test_cctools_inout() {
  "${cctools_prefix}inout" main.o -o inout.o
  [[ -s inout.o ]]
}

test_cctools_install_name_tool() {
  /bin/cp libprobe.dylib install-name.dylib
  "${cctools_prefix}install_name_tool" \
    -id @rpath/libchanged.dylib install-name.dylib
  "${cctools_prefix}otool" -D install-name.dylib > install-name.output
  [[ "$(/bin/cat install-name.output)" == *@rpath/libchanged.dylib* ]]
}

test_cctools_libtool() {
  "${cctools_prefix}libtool" -static -o libtool.a main.o
  [[ -s libtool.a ]]
}

test_cctools_lipo() {
  local output=""
  output="$("${cctools_prefix}lipo" -info smoke-executable)"
  [[ "$output" == *armv7* ]]
}

test_cctools_machocheck() {
  "${cctools_prefix}machocheck" smoke-executable
}

test_cctools_makerelocs() {
  "${cctools_prefix}makerelocs" preload makerelocs.bin
}

test_cctools_mtoc() {
  "${cctools_prefix}mtoc" preload preload.pe
  [[ -s preload.pe ]]
}

test_cctools_mtor() {
  "${cctools_prefix}mtor" -output mtor.o preload
  [[ -s mtor.o ]]
}

test_cctools_nm() {
  local output=""
  output="$("${cctools_prefix}nm" main.o)"
  [[ "$output" == *_main* && "$output" == *_probe* ]]
}

test_cctools_nmedit() {
  printf '%s\n' _main _probe > exported-symbols.txt
  "${cctools_prefix}nmedit" \
    -s exported-symbols.txt -o nmedit.o main.o
  [[ -s nmedit.o ]]
}

test_cctools_otool() {
  local output=""
  output="$("${cctools_prefix}otool" -hv smoke-executable)"
  [[ -n "$output" ]]
}

test_cctools_pagestuff() {
  "${cctools_prefix}pagestuff" smoke-executable -a > pagestuff.output
  [[ -s pagestuff.output ]]
}

test_cctools_ranlib() {
  "${cctools_prefix}ranlib" cctools.a
  [[ -s cctools.a ]]
}

test_cctools_redo_prebinding() {
  # Modern iOS binaries are not prebound.  The usage path verifies that this
  # legacy utility loads and rejects incomplete arguments without crashing.
  expect_usage_failure redo-prebinding.usage \
    "${cctools_prefix}redo_prebinding"
}

test_cctools_seg_addr_table() {
  # Real relayout requires a complete system-wide segment address table.
  expect_usage_failure seg-addr-table.usage \
    "${cctools_prefix}seg_addr_table"
}

test_cctools_seg_hack() {
  "${cctools_prefix}seg_hack" NEWSEG preload -o seg-hack.preload
  [[ -s seg-hack.preload ]]
}

test_cctools_segedit() {
  "${cctools_prefix}segedit" smoke-executable \
    -extract __TEXT __text extracted-text.bin
  [[ -s extracted-text.bin ]]
}

test_cctools_size() {
  local output=""
  output="$("${cctools_prefix}size" smoke-executable)"
  [[ -n "$output" ]]
}

test_cctools_strings() {
  local output=""
  output="$("${cctools_prefix}strings" main.o)"
  [[ "$output" == *altivec-smoke-marker* ]]
}

test_cctools_strip() {
  /bin/cp smoke-executable stripped-executable
  "${cctools_prefix}strip" -x stripped-executable
  [[ -s stripped-executable ]]
}

test_cctools_unwinddump() {
  "${cctools_prefix}unwinddump" smoke-executable > unwinddump.output
  [[ -e unwinddump.output ]]
}

test_cctools_vtool() {
  "${cctools_prefix}vtool" -show-build smoke-executable > vtool.output
  [[ -s vtool.output ]]
}

test_altivec_app() {
  "$bin_dir/altivec-app" --help > altivec-app.help
  [[ "$(/bin/cat altivec-app.help)" == *"altivec-app new"* ]]

  "$bin_dir/altivec-app" new \
    --name ToolSmoke \
    --display-name 'Tool Smoke' \
    --bundle-id com.altivecintelligence.tool-smoke \
    --destination app-template
  [[ -f app-template/Makefile ]]
  [[ -f app-template/source/iOS/Info.plist ]]
  [[ -f app-template/source/iOS/Resources/Default.png ]]
  [[ -f app-template/source/shared/Resources/en.lproj/Localizable.strings ]]
  [[ -x app-template/tools/generate-launch-images.sh ]]
  "$bin_dir/grep" -Fq \
    '<string>com.altivecintelligence.tool-smoke</string>' \
    app-template/source/iOS/Info.plist

  /bin/cp app-template/source/iOS/Resources/Default.png launch-master.png
  ALTIVEC_MAGICK="$bin_dir/magick" \
    app-template/tools/generate-launch-images.sh \
      --master launch-master.png --force
  [[ "$("$bin_dir/magick" identify -format '%wx%h' \
    app-template/source/iOS/Resources/Default-iOS12-896h@3x.png)" == \
    "1242x2688" ]]
}

test_altivec_sdk() {
  local output=""
  local sdk_count=""
  local sdk_84_targets=""

  output="$("$bin_dir/altivec-sdk" list)"
  [[ "$output" == *"Device: "* ]]
  [[ "$output" == *"Clang targets: "* ]]

  # shellcheck disable=SC2016
  sdk_count="$(printf '%s\n' "$output" |
    "$bin_dir/awk" '$1 ~ /^[0-9]+[.][0-9]+$/ { count++ } END { print count }')"
  # shellcheck disable=SC2016
  sdk_84_targets="$(printf '%s\n' "$output" |
    "$bin_dir/awk" '$1 == "8.4" { print $5 }')"

  [[ "$sdk_count" == "6" ]]
  [[ "$sdk_84_targets" == *armv7* ]]
  [[ "$output" == *"13.2"* ]]
  "$bin_dir/altivec-sdk" --help > altivec-sdk.help
  [[ "$(/bin/cat altivec-sdk.help)" == *"altivec-sdk install <version>"* ]]
}

test_altivec_lib() {
  local output=""

  output="$("$bin_dir/altivec-lib" list)"
  [[ "$output" == *"VERSION"* ]]
  [[ "$output" == *"STATUS"* ]]
  [[ "$output" == *"CURRENT"* ]]
  "$bin_dir/altivec-lib" --help > altivec-lib.help
  [[ "$(/bin/cat altivec-lib.help)" == \
    *"altivec-lib install <version>"* ]]
  [[ "$(/bin/cat altivec-lib.help)" == *"altivec-lib update"* ]]
}

test_awk() {
  # shellcheck disable=SC2016
  [[ "$(printf 'alpha 3\nbeta 7\n' |
    "$bin_dir/awk" '$1 == "beta" { print $2 }')" == "7" ]]
}

test_curl() {
  printf 'curl-data\n' > curl.txt
  [[ "$("$bin_dir/curl" --fail --silent --show-error \
    "file://${smoke_dir}/curl.txt")" == "curl-data" ]]
}

test_file() {
  local output=""
  output="$("$bin_dir/file" main.o)"
  [[ "$output" == *Mach-O* && "$output" == *armv7* ]]
}

test_git() {
  "$bin_dir/git" init --quiet git-repo
  "$bin_dir/git" -C git-repo config user.name 'Altivec smoke test'
  "$bin_dir/git" -C git-repo config user.email smoke@example.invalid
  printf 'tracked\n' > git-repo/tracked.txt
  "$bin_dir/git" -C git-repo add tracked.txt
  "$bin_dir/git" -C git-repo commit --quiet -m smoke
  "$bin_dir/git" -C git-repo rev-parse --verify HEAD > git-head
  [[ -s git-head && -z "$("$bin_dir/git" -C git-repo status --porcelain)" ]]
}

test_git_cvsserver() {
  local output=""
  local rc=0

  output="$("$bin_dir/git-cvsserver" --version 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] && return 0
  if [[ "$output" == *NO_PERL=YesPlease* ]]; then
    printf '%s' 'built with NO_PERL=YesPlease; CVS server is unavailable' >&2
    return 77
  fi
  printf '%s\n' "$output" >&2
  return 1
}

test_git_shell() {
  "$bin_dir/git-shell" \
    -c "git-upload-pack '${smoke_dir}/git-repo/.git'" \
    </dev/null > git-shell.protocol
  [[ -s git-shell.protocol ]]
}

test_jq() {
  assert_no_newer_ios_imports jq 7 ___exp10 || return 1
  [[ "$(printf '{"answer":42}\n' |
    "$bin_dir/jq" -r '.answer')" == "42" ]] || return 1
  "$bin_dir/jq" -n -e '2 | exp10 == 100' >/dev/null
}

test_ldid() {
  /bin/cp smoke-executable ldid-executable
  "$bin_dir/ldid" -S ldid-executable
  "$bin_dir/ldid" -e ldid-executable > ldid-entitlements.plist
  [[ -s ldid-executable ]]
}

test_magick() {
  local dimensions=""

  "$bin_dir/magick" -size 32x24 xc:red source.png
  "$bin_dir/magick" source.png -resize '8x6!' resized.png
  dimensions="$("$bin_dir/magick" identify -format '%m %wx%h' resized.png)"
  [[ "$dimensions" == "PNG 8x6" ]]

  "$bin_dir/magick" -list configure > magick-configure.output
  if "$bin_dir/grep" -E \
      '(build-release/Intermediates|/osxcross/|/usr/bin/clang(\+\+)?-[0-9]+|dependency-sysroot)' \
      magick-configure.output; then
    return 1
  fi
  [[ ! -e "$bin_dir/MagickCore-config" &&
    ! -e "$bin_dir/MagickWand-config" ]]
}

test_make() {
  # shellcheck disable=SC2016
  printf '%s\n' \
    'value := made' \
    'all:' \
    '	@echo $(value) > make.output' > Smoke.mk
  "$bin_dir/make" --no-print-directory -f Smoke.mk
  [[ "$(/bin/cat make.output)" == "made" ]]
}

test_patch() {
  assert_no_newer_ios_imports patch 8 _fdopendir _mkdirat || return 1

  printf 'old\n' > patch-target.txt
  printf '%s\n' \
    '--- patch-target.txt' \
    '+++ patch-target.txt' \
    '@@ -1 +1 @@' \
    '-old' \
    '+new' > change.patch
  "$bin_dir/patch" --quiet patch-target.txt change.patch || return 1
  [[ "$(/bin/cat patch-target.txt)" == "new" ]] || return 1

  /bin/mkdir -p patch-numbered/nested patch-prefix
  (
    cd patch-numbered
    printf 'old\n' > nested/file.txt
    printf '%s\n' \
      '--- nested/file.txt' \
      '+++ nested/file.txt' \
      '@@ -1 +1 @@' \
      '-old' \
      '+new' > change.patch
    "$bin_dir/patch" --quiet --backup --version-control=numbered \
      nested/file.txt change.patch || exit 1
    [[ "$(/bin/cat nested/file.txt)" == "new" &&
      "$(/bin/cat nested/file.txt.~1~)" == "old" ]]
  ) || return 1
  (
    cd patch-prefix
    printf 'old\n' > file.txt
    printf '%s\n' \
      '--- file.txt' \
      '+++ file.txt' \
      '@@ -1 +1 @@' \
      '-old' \
      '+new' > change.patch
    "$bin_dir/patch" --quiet --backup --prefix=backups/ \
      file.txt change.patch || exit 1
    [[ "$(/bin/cat file.txt)" == "new" &&
      "$(/bin/cat backups/file.txt)" == "old" ]]
  ) || return 1
}

test_plistutil() {
  printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"' \
    '  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0"><dict><key>Probe</key><string>ok</string></dict></plist>' \
    > probe.plist
  "$bin_dir/plistutil" -i probe.plist -o probe.binary -f bin
  "$bin_dir/plistutil" -i probe.binary -o probe-roundtrip.plist -f xml
  [[ "$(/bin/cat probe-roundtrip.plist)" == *'<string>ok</string>'* ]]
}

test_scalar() {
  local output=""
  output="$("$bin_dir/scalar" version 2>&1)"
  [[ "$output" == "git version "* ]]
}

test_sqlite3() {
  local output=""
  "$bin_dir/sqlite3" smoke.sqlite \
    'CREATE TABLE probe(value TEXT); INSERT INTO probe VALUES ("sqlite-ok");'
  output="$("$bin_dir/sqlite3" smoke.sqlite 'SELECT value FROM probe;')"
  [[ "$output" == "sqlite-ok" ]]
}

test_unzip() {
  /bin/mkdir unzip-output
  "$bin_dir/unzip" -q archive.zip -d unzip-output
  [[ "$(/bin/cat unzip-output/file.txt)" == "zip-data" ]]
}

test_xz() {
  printf 'xz-data\n' > xz.txt
  "$bin_dir/xz" -c xz.txt > xz.txt.xz
  "$bin_dir/xz" -dc xz.txt.xz > xz.output
  [[ "$(/bin/cat xz.output)" == "xz-data" ]]
}

test_zip() {
  /bin/mkdir zip-input
  printf 'zip-data\n' > zip-input/file.txt
  (
    cd zip-input
    "$bin_dir/zip" -q ../archive.zip file.txt
  )
  [[ -s archive.zip ]]
}

test_vi() {
  printf 'old\n' > vi.txt
  "$bin_dir/vi" -Nu NONE -i NONE -n -es vi.txt <<'VIM'
%s/old/new/
wq
VIM
  [[ "$(/bin/cat vi.txt)" == "new" ]]
}

test_less() {
  printf 'less-data\n' > less.txt
  [[ "$("$bin_dir/less" -F -X less.txt)" == "less-data" ]]
}

test_clear() {
  TERM=xterm "$bin_dir/clear" > clear.sequence
  [[ -s clear.sequence ]]
}

test_reset() {
  "$bin_dir/reset" -V
}

test_ps() {
  local output=""
  output="$("$bin_dir/ps" -ax)"
  [[ "$output" == *launchd* ]]
}

test_pgrep() {
  local output=""
  output="$("$bin_dir/pgrep" -a -S -l launchd)"
  [[ "$output" == *launchd* ]]
}

test_pkill() {
  local rc=0
  "$bin_dir/pkill" -0 altivec-tool-test-name-never-running \
    >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 1 ]]
}

test_htop() {
  "$bin_dir/htop" --version
}

test_watch() {
  "$bin_dir/watch" --version
}

test_wc() {
  local byte_count=""
  local line_count=""
  local output=""
  local trailing=""
  local word_count=""
  output="$(printf 'alpha beta\ngamma\n' | "$bin_dir/wc")"
  read -r line_count word_count byte_count trailing <<< "$output"
  [[ "$line_count" == "2" && "$word_count" == "3" &&
    "$byte_count" == "17" && -z "$trailing" ]]
}

test_diff() {
  local rc=0
  printf 'alpha\n' > diff.a
  printf 'beta\n' > diff.b
  "$bin_dir/diff" diff.a diff.b > diff.output || rc=$?
  [[ "$rc" -eq 1 && -s diff.output ]]
}

test_cmp() {
  printf 'same\n' > cmp.a
  /bin/cp cmp.a cmp.b
  "$bin_dir/cmp" cmp.a cmp.b
}

test_diff3() {
  printf 'same\n' > diff3.a
  /bin/cp diff3.a diff3.b
  /bin/cp diff3.a diff3.c
  "$bin_dir/diff3" diff3.a diff3.b diff3.c
}

test_find() {
  local output=""
  /bin/mkdir -p find-root/inner
  : > find-root/inner/needle
  output="$("$bin_dir/find" "$smoke_dir/find-root" \
    -type f -name needle -print)"
  [[ "$output" == "$smoke_dir/find-root/inner/needle" ]]
}

test_xargs() {
  printf 'alpha\nbeta\n' |
    "$bin_dir/xargs" -n 1 /bin/echo > xargs.output
  [[ "$(/bin/cat xargs.output)" == $'alpha\nbeta' ]]
}

test_grep() {
  [[ "$(printf 'alpha\nbeta\n' | "$bin_dir/grep" '^beta$')" == "beta" ]]
}

test_sed() {
  [[ "$(printf 'old\n' | "$bin_dir/sed" 's/old/new/')" == "new" ]]
}

test_tar() {
  assert_no_newer_ios_imports tar 8 _linkat _mkdirat || return 1

  # Match SDK installation: extracting a gzip archive must create a directory
  # hierarchy.  This exercises tar's mkdirat fallback on pre-iOS 8 runtimes.
  /bin/mkdir -p tar-input/iPhoneOS8.4.sdk/usr/include tar-output
  printf 'tar-data\n' > tar-input/iPhoneOS8.4.sdk/usr/include/probe.h
  "$bin_dir/tar" -czf sdk.tar.gz -C tar-input iPhoneOS8.4.sdk
  "$bin_dir/tar" --no-same-owner --no-same-permissions \
    -xzf sdk.tar.gz -C tar-output
  [[ "$(/bin/cat \
    tar-output/iPhoneOS8.4.sdk/usr/include/probe.h)" == "tar-data" ]]
}

test_gzip() {
  printf 'gzip-data\n' > gzip.txt
  "$bin_dir/gzip" -c gzip.txt > gzip.gz
  "$bin_dir/gzip" -dc gzip.gz > gzip.output
  [[ "$(/bin/cat gzip.output)" == "gzip-data" ]]
}

test_bzip2() {
  printf 'bzip-data\n' > bzip.txt
  "$bin_dir/bzip2" -c bzip.txt > bzip.bz2
  "$bin_dir/bzip2" -dc bzip.bz2 > bzip.output
  [[ "$(/bin/cat bzip.output)" == "bzip-data" ]]
}

test_which() {
  [[ "$("$bin_dir/which" find)" == "$bin_dir/find" ]]
}

test_killall() {
  "$bin_dir/killall" -l
}

test_openssl() {
  local digest=""
  local version=""
  version="$("$bin_dir/openssl" version)"
  [[ "$version" == "OpenSSL "* ]]
  digest="$(printf 'abc' | "$bin_dir/openssl" dgst -sha256)"
  digest="${digest##*= }"
  [[ "$digest" == \
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" ]]
}

test_ifconfig() {
  local output=""
  output="$("$bin_dir/ifconfig" lo0)"
  [[ "$output" == *127.0.0.1* ]]
}

test_ping() {
  "$bin_dir/ping" -c 1 127.0.0.1
}

test_nc() {
  "$bin_dir/nc" -z -w 2 127.0.0.1 22
}

test_hostname() {
  [[ -n "$("$bin_dir/hostname")" ]]
}

test_logger() {
  local rc=0
  # An invalid option exercises argument handling without writing to syslog.
  "$bin_dir/logger" -Z >/dev/null 2>&1 || rc=$?
  [[ "$rc" -ne 0 ]]
}

test_man() {
  local output=""
  output="$(MANPAGER=/bin/cat PAGER=/bin/cat "$bin_dir/man" tree)"
  [[ "$output" == *directory* || "$output" == *DIRECTORY* ]]
}

test_tree() {
  local output=""
  /bin/mkdir -p tree-root/inner
  : > tree-root/inner/needle
  output="$("$bin_dir/tree" tree-root)"
  [[ "$output" == *needle* ]]
}

test_realpath() {
  local output=""
  /bin/mkdir -p realpath-root/inner
  : > realpath-root/inner/needle
  output="$("$bin_dir/realpath" \
    realpath-root/inner/../inner/needle)"
  [[ -f "$output" && "${output##*/}" == "needle" ]]
}

test_hexdump() {
  [[ "$(printf 'hi' |
    "$bin_dir/hexdump" -v -e '1/1 "%02x"')" == "6869" ]]
}

test_xxd() {
  [[ "$(printf 'hi' | "$bin_dir/xxd" -p)" == "6869" ]]
}

test_public_alias() {
  local alias_name="$1"
  local alias_target="$2"
  local alias_path="${bin_dir}/${alias_name}"
  local output=""
  local rc=0

  [[ -L "$alias_path" && -x "$alias_path" &&
    "$alias_path" -ef "${bin_dir}/${alias_target}" ]]

  case "$alias_name" in
    cc|clang)
      "$alias_path" --target=armv7-apple-ios6.0 \
        -c main.c -o "alias-${alias_name}.o"
      [[ -s "alias-${alias_name}.o" ]]
      ;;
    c++|clang++|clang++-15)
      "$alias_path" --target=armv7-apple-ios6.0 \
        -c probe.cpp -o "alias-${alias_name}.o"
      [[ -s "alias-${alias_name}.o" ]]
      ;;
    clang-cpp)
      output="$(printf '#define ALTIVEC_ALIAS_VALUE 17\nALTIVEC_ALIAS_VALUE\n' |
        "$alias_path" --target=armv7-apple-ios6.0 -E -P -x c -)"
      [[ "$output" == *17* ]]
      ;;
    git-receive-pack)
      "$bin_dir/git" init --quiet --bare receive.git
      "$bin_dir/git" -C git-repo push --quiet \
        "$smoke_dir/receive.git" HEAD:refs/heads/smoke
      "$bin_dir/git" --git-dir=receive.git \
        rev-parse --verify refs/heads/smoke > receive-head
      [[ -s receive-head ]]
      ;;
    git-upload-archive)
      "$bin_dir/git" archive --remote="$smoke_dir/git-repo/.git" \
        --format=tar HEAD > upload-archive.tar
      [[ -s upload-archive.tar ]]
      ;;
    git-upload-pack)
      "$bin_dir/git" clone --quiet --no-local \
        "$smoke_dir/git-repo/.git" upload-clone
      [[ -f upload-clone/tracked.txt ]]
      ;;
    animate|compare|composite|conjure|convert|display|identify|import|\
      magick-script|mogrify|montage|stream)
      # The X11-facing compatibility names cannot open a display on iOS, but
      # they must still dispatch through ImageMagick and parse their options.
      output="$("$alias_path" -version 2>&1)" || rc=$?
      [[ "$rc" -eq 0 || "$rc" -eq 1 ]]
      [[ "$output" == *ImageMagick* ]]
      ;;
    ldid2)
      "$alias_path" -h
      ;;
    pgrep)
      test_pgrep
      ;;
    unxz)
      /bin/cp xz.txt.xz unxz-smoke.xz
      "$alias_path" unxz-smoke.xz
      [[ "$(/bin/cat unxz-smoke)" == "xz-data" ]]
      ;;
    xzcat)
      [[ "$("$alias_path" xz.txt.xz)" == "xz-data" ]]
      ;;
  esac
}

printf 'LOGIN_PROFILE path_prefix=%s\n' "${PATH%%:*}"
printf 'INVENTORY regular=%s aliases=%s entries=%s\n' \
  "$regular_count" "$alias_count" "$actual_count"

for test_spec in $regular_tests; do
  tool="${test_spec%%:*}"
  test_function="${test_spec#*:}"
  run_test "$tool" "$test_function"
done

for alias_spec in $alias_pairs; do
  alias_name="${alias_spec%%:*}"
  alias_target="${alias_spec#*:}"
  run_test "$alias_name" test_public_alias "$alias_name" "$alias_target"
done

covered=$((passed + skipped + failed))
printf 'RESULT entries=%s passed=%s skipped=%s failed=%s\n' \
  "$covered" "$passed" "$skipped" "$failed"
[[ "$covered" -eq "$expected_entry_count" && "$failed" -eq 0 ]] || exit 1
printf '%s\n' 'Altivec packaged-tools device smoke test passed.'
