#!/usr/bin/env bash

# All Docker-build work which requires Apple SDK input belongs in this script.
# The Containerfile invokes it once with the three archives mounted read-only
# under /altivec-sdk. The script removes every installed SDK before returning,
# so its single filesystem snapshot contains only toolchains and build outputs.

set -euo pipefail

readonly repo_root="${ALTIVEC_ROOT:-/altivec}"
readonly legacy_root="${ALTIVEC_LEGACY_SOURCE_ROOT:-/osxcross/legacy}"
readonly legacy_target="${ALTIVEC_LEGACY_TOOLCHAIN:-/osxcross/legacy/target}"
readonly modern_source="${ALTIVEC_MODERN_SOURCE_ROOT:-/osxcross/modern-source}"
readonly modern_target="${ALTIVEC_MODERN_TOOLCHAIN:-/osxcross/modern}"
readonly build_input="${ALTIVEC_SDK_BUILD_INPUT:-/build-sdk-dependent}"
readonly osxcross_legacy_commit=af8300c6b3e099c91970a8d2d0f3bffe703f2421
readonly osxcross_modern_commit=27d21e4977c9751d01199c7a226a6faf494c3dd9
readonly jobs="${JOBS:-$(nproc)}"
readonly fixture="$build_input/fixtures/toolchain-smoke.c"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

section() {
  printf '\n--- %s ---\n' "$1"
}

run_logged() {
  local label="$1"
  local log_file
  local status
  shift
  log_file="$(mktemp /tmp/altivec-build.XXXXXX.log)"
  printf ' > detailed log: %s\n' "$log_file"
  set +e
  (set -e; "$@") > "$log_file" 2>&1
  status=$?
  set -e
  if (( status == 0 )); then
    tail -n 20 "$log_file"
    rm -f -- "$log_file"
  else
    printf 'error: %s failed; final log follows\n' "$label" >&2
    tail -n 240 "$log_file" >&2
    return 1
  fi
}

archive_path() {
  local filename="$1"
  local directory

  if [[ -n "${ALTIVEC_SDK_ARCHIVE_DIR:-}" ]]; then
    [[ -f "$ALTIVEC_SDK_ARCHIVE_DIR/$filename" ]] ||
      die "SDK archive not found: ${ALTIVEC_SDK_ARCHIVE_DIR}/${filename}"
    printf '%s\n' "$ALTIVEC_SDK_ARCHIVE_DIR/$filename"
    return
  fi
  for directory in /altivec-sdk "$repo_root/.altivec-sdk"; do
    if [[ -f "$directory/$filename" ]]; then
      printf '%s\n' "$directory/$filename"
      return
    fi
  done
  die "SDK archive not found: ${filename}"
}

checkout_osxcross() {
  local destination="$1"
  local commit="$2"
  local temporary

  temporary="$(mktemp -d /tmp/altivec-osxcross.XXXXXX)"
  git -C "$temporary" init --quiet source
  git -C "$temporary/source" remote add origin \
    https://github.com/tpoechtrager/osxcross.git
  git -C "$temporary/source" fetch --quiet --depth 1 origin "$commit"
  git -C "$temporary/source" checkout --quiet --detach FETCH_HEAD
  mkdir -p "$destination"
  cp -a "$temporary/source/." "$destination/"
  rm -rf -- "$temporary"
}

prepare_legacy_source() {
  section 'Preparing legacy OSXCross source'
  checkout_osxcross "$legacy_root" "$osxcross_legacy_commit"

  # shellcheck disable=SC2016 # Match literal variables in the upstream script.
  sed -i '/pushd $OSXCROSS_BUILD_DIR/i mkdir -p $OSXCROSS_BUILD_DIR' \
    "$legacy_root/build_gcc.sh"
  cp /usr/share/misc/config.guess "$legacy_root/config.guess.new"
  cp /usr/share/misc/config.sub "$legacy_root/config.sub.new"
  # shellcheck disable=SC2016 # Insert literal variables into the upstream script.
  sed -i \
    '/extract "$OSXCROSS_TARBALL_DIR\/gcc-$APPLE_GCC_VERSION.tar.gz" 1/a \  find . -name "config.guess" -exec cp ../config.guess.new {} \\; \n  find . -name "config.sub" -exec cp ../config.sub.new {} \\;' \
    "$legacy_root/build_gcc.sh"

  patch "$legacy_root/build.sh" --quiet \
    < "$build_input/patches/osxcross-build-host-gcc14.patch"
  cp "$legacy_root/build_gcc.sh" "$legacy_root/build_gcc_ppc.sh"
  patch "$legacy_root/build_gcc.sh" --quiet \
    < "$build_input/patches/osxcross-build-gcc-intel.patch"
  patch "$legacy_root/build_gcc_ppc.sh" --quiet \
    < "$build_input/patches/osxcross-build-gcc-ppc.patch"
  chmod +x "$legacy_root/build_gcc.sh" "$legacy_root/build_gcc_ppc.sh"
  ln -sfn /usr/bin/python3 /usr/local/bin/python

  mkdir -p "$legacy_root/tarballs"
  ln -s "$(archive_path MacOSX10.5.sdk.tar.xz)" \
    "$legacy_root/tarballs/MacOSX10.5.sdk.tar.xz"
}

build_legacy_toolchain() {
  section 'Building legacy OSXCross and Apple GCC'
  (
    cd "$legacy_root"
    CC=/usr/bin/clang CXX=/usr/bin/g++-14 \
      SDK_VERSION=10.5 OSX_VERSION_MIN=10.5 UNATTENDED=1 JOBS="$jobs" \
      ./build.sh

    GCC_VERSION=4.2.1 APPLE_GCC=1 JOBS="$jobs" POWERPC=1 \
      ./build_gcc_ppc.sh
    rm -rf build
    GCC_VERSION=4.2.1 APPLE_GCC=1 JOBS="$jobs" ./build_gcc.sh
    rm -rf build
  )

  local base_ld base_prefix
  base_ld="$(find "$legacy_target/bin" -maxdepth 1 \
    -name 'x86_64-apple-darwin*-ld' -print -quit)"
  [[ -n "$base_ld" ]] || die 'legacy x86_64 linker was not installed'
  base_prefix="${base_ld##*/}"
  base_prefix="${base_prefix%-ld}"
  ln -sfn "${base_prefix}-ld" "$legacy_target/bin/ld"
  ln -sfn "${base_prefix}-lipo" "$legacy_target/bin/lipo"
}

prepare_modern_source() {
  section 'Preparing modern OSXCross source'
  checkout_osxcross "$modern_source" "$osxcross_modern_commit"
  mkdir -p "$modern_source/tarballs"
  ln -s "$(archive_path MacOSX11.3.sdk.tar.xz)" \
    "$modern_source/tarballs/MacOSX11.3.sdk.tar.xz"
}

build_modern_toolchain() {
  section 'Building modern OSXCross'
  (
    cd "$modern_source"
    CC=/usr/bin/clang CXX=/usr/bin/clang++ \
      TARGET_DIR="$modern_target" SDK_VERSION=11.3 OSX_VERSION_MIN=10.9 \
      ENABLE_ARCHS='x86_64 arm64' BUILD_FLAVOR=stable UNATTENDED=1 \
      JOBS="$jobs" ./build.sh
  )

  # OSXCross installs the two macOS SDKs itself, outside altivec-sdk's receipt
  # model. Replace those copies so every SDK used by subsequent project builds
  # was extracted by altivec-sdk from a checksum-verified archive.
  ALTIVEC_SDK_ARCHIVE_DIR="${ALTIVEC_SDK_ARCHIVE_DIR:-/altivec-sdk}" \
    altivec-sdk purge
  ALTIVEC_SDK_ARCHIVE_DIR="${ALTIVEC_SDK_ARCHIVE_DIR:-/altivec-sdk}" \
    altivec-sdk ensure

  local tool tool_path
  for tool in ld ar ranlib lipo libtool nm otool strip install_name_tool; do
    tool_path="$(find "$modern_target/bin" -maxdepth 1 \
      \( -type f -o -type l \) -name "*-apple-darwin*-${tool}" \
      -print | sort | head -n 1)"
    [[ -n "$tool_path" ]] || die "modern OSXCross tool is missing: ${tool}"
    ln -sfn "$(basename "$tool_path")" "$modern_target/bin/$tool"
  done
  ln -sfn "$modern_target" /osxcross/target
}

assert_min_version() {
  local file="$1"
  local expected="$2"
  local actual

  actual="$("$modern_target/bin/otool" -l "$file" | awk '
    $1 == "cmd" && ($2 == "LC_VERSION_MIN_MACOSX" ||
                     $2 == "LC_VERSION_MIN_IPHONEOS" ||
                     $2 == "LC_BUILD_VERSION") { found = 1; next }
    found && ($1 == "version" || $1 == "minos") { print $2; exit }
  ')"
  [[ "$actual" == "$expected" ]] ||
    die "${file} has minimum version ${actual}; expected ${expected}"
}

smoke_toolchains() {
  section 'Testing toolchains and deployment floors'
  local output modern_x64 modern_arm64 slice expected arch
  local -a modern_x64_candidates modern_arm64_candidates
  output="$(mktemp -d /tmp/altivec-toolchain-smoke.XXXXXX)"
  mapfile -t modern_x64_candidates < <(
    find "$modern_target/bin" -maxdepth 1 \
      -name 'x86_64-apple-darwin*-clang' \
      ! -name '*-cmake-*' -print | sort
  )
  mapfile -t modern_arm64_candidates < <(
    find "$modern_target/bin" -maxdepth 1 \
      -name 'arm64-apple-darwin*-clang' \
      ! -name '*-cmake-*' -print | sort
  )
  [[ "${#modern_x64_candidates[@]}" -eq 1 ]] ||
    die "expected exactly one modern x86_64 Clang wrapper; found ${#modern_x64_candidates[@]}"
  [[ "${#modern_arm64_candidates[@]}" -eq 1 ]] ||
    die "expected exactly one modern arm64 Clang wrapper; found ${#modern_arm64_candidates[@]}"
  modern_x64="${modern_x64_candidates[0]}"
  modern_arm64="${modern_arm64_candidates[0]}"

  "$legacy_target/bin/oppc32-gcc" -arch ppc -mmacosx-version-min=10.4 \
    -isysroot "$legacy_target/SDK/MacOSX10.5.sdk" "$fixture" \
    -lgcc_s.10.4 -o "$output/macos-ppc"
  "$legacy_target/bin/o32-gcc" -arch i386 -mmacosx-version-min=10.4 \
    -isysroot "$legacy_target/SDK/MacOSX10.5.sdk" "$fixture" \
    -lgcc_s.10.4 -o "$output/macos-i386"
  "$modern_x64" -target x86_64-apple-macos10.9 \
    -isysroot "$modern_target/SDK/MacOSX11.3.sdk" "$fixture" \
    -o "$output/macos-x86_64"
  "$modern_arm64" -target arm64-apple-macos11.0 \
    -isysroot "$modern_target/SDK/MacOSX11.3.sdk" "$fixture" \
    -o "$output/macos-arm64"
  /usr/bin/clang -target arm64-apple-ios -arch armv7 -arch arm64 \
    -Xarch_armv7 -miphoneos-version-min=5.0 \
    -Xarch_arm64 -miphoneos-version-min=7.0 \
    -Werror=overriding-option \
    -isysroot "$modern_target/SDK/iPhoneOS8.4.sdk" \
    -B"$modern_target/bin" "$fixture" -o "$output/ios-universal"

  "$legacy_target/bin/i386-apple-darwin9-lipo" -create \
    "$output/macos-ppc" "$output/macos-i386" \
    "$output/macos-x86_64" "$output/macos-arm64" \
    -output "$output/macos-universal"
  "$legacy_target/bin/i386-apple-darwin9-lipo" \
    "$output/macos-universal" -verify_arch ppc i386 x86_64 arm64
  "$modern_target/bin/lipo" "$output/ios-universal" \
    -verify_arch armv7 arm64

  for slice in \
    macos-ppc:10.4 macos-i386:10.4 macos-x86_64:10.9 \
    macos-arm64:11.0 ios-armv7:5.0 ios-arm64:7.0; do
    expected="${slice##*:}"
    slice="${slice%%:*}"
    arch="${slice#*-}"
    if [[ "$slice" == macos-* ]]; then
      "$legacy_target/bin/i386-apple-darwin9-lipo" \
        "$output/macos-universal" -thin "$arch" \
        -output "$output/verify-$slice"
    else
      "$modern_target/bin/lipo" "$output/ios-universal" -thin "$arch" \
        -output "$output/verify-$slice"
    fi
    assert_min_version "$output/verify-$slice" "$expected"
  done
  rm -rf -- "$output"
}

build_altivec_libraries() {
  section 'Building AltivecCore'
  (
    cd "$repo_root/libs/core"
    make all
    make prune-intermediates
  )
  rm -rf \
    "$repo_root/libs/libcurl/build-mac" \
    "$repo_root/libs/libcurl/build-phone" \
    "$repo_root/libs/sqlite/build-mac" \
    "$repo_root/libs/sqlite/build-phone"

  section 'Building AltivecCocoa'
  (
    cd "$repo_root/libs/cocoa"
    make all
    make prune-intermediates
  )
}

smoke_runtime() {
  section 'Testing retained runtime outputs'
  [[ -f "$repo_root/libs/core/build-mac/lib/libAltivecCore.a" ]]
  [[ -f "$repo_root/libs/core/build-phone/lib/libAltivecCore.a" ]]
  [[ -f "$repo_root/libs/cocoa/build-phone/lib/libAltivecCocoa.a" ]]
  [[ -f "$repo_root/apps/CURLmac/AICURLConnection.m" ]]
  [[ -f "$repo_root/apps/CURLphone/AICURLConnection.m" ]]
  [[ ! -e "$repo_root/libs/core/build-mac/lib/libAICURLConnection.a" ]]
  [[ ! -e "$repo_root/libs/core/build-phone/lib/libAICURLConnection.a" ]]
  [[ -f "$repo_root/libs/core/build-phone/lib/cacert.pem" ]]
  [[ -f "$repo_root/libs/cocoa/build-phone/Resources/Fonts/FA7-Solid-900.otf" ]]
  [[ -f "$repo_root/libs/cocoa/build-phone/Resources/Fonts/LICENSE-Font-Awesome.txt" ]]
  [[ ! -d "$repo_root/libs/core/build-phone/lib/AltivecCore.framework" ]]
  [[ ! -d "$repo_root/libs/cocoa/build-phone/lib/AltivecCocoa.framework" ]]
  [[ -z "$(find "$repo_root/apps" -type d -name 'build-*' -print -quit)" ]]

  local app binary thin arch expected actual
  for app in SingleWindow SingleScreen CURLmac CURLphone; do
    make -C "$repo_root/apps/$app" -n release ALTIVEC_ROOT="$repo_root" \
      >/dev/null
  done
  make -C "$repo_root/apps/SingleScreen" release ALTIVEC_ROOT="$repo_root"
  binary="$repo_root/apps/SingleScreen/build-release/SingleScreen.app/SingleScreen"
  "$modern_target/bin/lipo" "$binary" -verify_arch armv7 arm64
  for arch in armv7:5.0 arm64:7.0; do
    expected="${arch##*:}"
    arch="${arch%%:*}"
    thin="/tmp/altivec-singlescreen-${arch}"
    "$modern_target/bin/lipo" "$binary" -thin "$arch" -output "$thin"
    actual="$("$modern_target/bin/otool" -l "$thin" | awk '
      $1 == "cmd" && ($2 == "LC_VERSION_MIN_IPHONEOS" ||
                       $2 == "LC_BUILD_VERSION") { found = 1; next }
      found && ($1 == "version" || $1 == "minos") { print $2; exit }
    ')"
    [[ "$actual" == "$expected" ]] ||
      die "${arch} application minimum is ${actual}; expected ${expected}"
    rm -f "$thin"
  done
  make -C "$repo_root/apps/SingleScreen" clean ALTIVEC_ROOT="$repo_root"
  [[ -z "$(find "$repo_root/apps/SingleScreen" -type d -name 'build-*' -print -quit)" ]]

  local arc_plan
  arc_plan="$(mktemp /tmp/altivec-arc-plan.XXXXXX)"
  make -C "$repo_root/apps/CURLphone" -Bn release \
    ALTIVEC_ROOT="$repo_root" PHONE_SOURCE_FLAGS=-fobjc-arc > "$arc_plan"
  grep -Fq -- '-fobjc-arc' "$arc_plan" ||
    die 'CURLphone ARC compile plan lost its ARC flag'
  if grep -Fqi arclite "$arc_plan"; then
    die 'CURLphone ARC build plan unexpectedly references ARCLite'
  fi
  rm -f "$arc_plan"
}

remove_sdk_inputs() {
  local fixed_sdk_header

  section 'Removing SDK input from the image filesystem'
  altivec-sdk purge
  rm -rf -- "$modern_source"
  find "$legacy_root" -mindepth 1 -maxdepth 1 ! -name target \
    -exec rm -rf -- {} +
  # Apple GCC's fixincludes copied this APSL header from the 10.5 SDK into the
  # compiler tree. It is not needed by the retained toolchain and must not
  # survive merely because its content was transformed after extraction.
  find "$legacy_target/lib/gcc" -type f \
    -path '*/include/pexpert/pexpert.h' -delete
  fixed_sdk_header="$(grep -RIl --binary-files=without-match \
    'auto-edited by fixincludes from:' "$legacy_target/lib/gcc" 2>/dev/null \
    | head -n 1 || true)"
  [[ -z "$fixed_sdk_header" ]] ||
    die "SDK-derived fixed header remains: ${fixed_sdk_header}"
  rm -f \
    "$legacy_target/SDK/.altivec-sdk.lock" \
    "$modern_target/SDK/.altivec-sdk.lock"

  altivec-sdk audit /osxcross
  altivec-sdk audit /altivec
  altivec-sdk audit /opt
  altivec-sdk audit /usr/local
}

altivec-sdk verify
prepare_legacy_source
run_logged 'legacy OSXCross and Apple GCC build' build_legacy_toolchain
prepare_modern_source
run_logged 'modern OSXCross build' build_modern_toolchain
smoke_toolchains
run_logged 'Altivec library build' build_altivec_libraries
smoke_runtime
remove_sdk_inputs

section 'SDK-dependent build complete'
