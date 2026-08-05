#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

if (($# != 3)); then
  printf 'Usage: %s <ios-app.mk> <project-template-dir> <altivec-app>\n' \
    "$(basename "$0")" >&2
  exit 2
fi

for tool in awk chmod cmp cp dirname file grep make mkdir mktemp mv realpath; do
  command -v "$tool" >/dev/null 2>&1 ||
    die "required validation tool not found: ${tool}"
done

common_makefile="$(realpath -m "$1")"
project_template_dir="$(realpath -m "$2")"
app_tool="$(realpath -m "$3")"
readonly common_makefile project_template_dir app_tool

[[ -f "$common_makefile" ]] ||
  die "common iOS app Makefile not found: ${common_makefile}"
[[ -d "$project_template_dir" && ! -L "$project_template_dir" ]] ||
  die "iOS app project template not found: ${project_template_dir}"
[[ -f "$app_tool" && -x "$app_tool" ]] ||
  die "iOS app initializer not found: ${app_tool}"

for template_file in \
  Makefile \
  source/iOS/Makefile \
  source/iOS/Info.plist \
  source/iOS/Resources/Default.png \
  source/iOS/Resources/Default@2x.png \
  source/shared/Resources/en.lproj/Localizable.strings; do
  [[ -f "${project_template_dir}/${template_file}" ]] ||
    die "iOS app project template is missing: ${template_file}"
done

grep -Fqx 'IPHONEOS_DEPLOYMENT_TARGET ?= 4.3' "$common_makefile" ||
  die 'common Makefile does not default app builds to iOS 4.3'
grep -Fqx 'APP_USE_ARC ?= 1' "$common_makefile" ||
  die 'common Makefile does not default app builds to ARC'
grep -Fqx 'BUNDLE_LOCALIZATION_DIRS ?=' "$common_makefile" ||
  die 'common Makefile does not expose shared localization roots'
awk '
    /@"\$\(_altivec_link_driver\)"/ { in_link = 1 }
    in_link && /\$\(_altivec_arc_flag\)/ { found_arc_link_flag = 1 }
    in_link && /\$\(APP_LDFLAGS\)/ { in_link = 0 }
    END { exit(found_arc_link_flag ? 0 : 1) }
  ' "$common_makefile" ||
  die 'common Makefile does not pass the ARC flag to the final link'

# shellcheck disable=SC2016
grep -Fqx \
  'include $(ALTIVEC_PREFIX)/share/altivec/make/ios-app.mk' \
  "$project_template_dir/source/iOS/Makefile" ||
  die 'project template does not include the installed common Makefile'
grep -Fqx 'BUNDLE_LOCALIZATION_DIRS := ../shared/Resources' \
  "$project_template_dir/source/iOS/Makefile" ||
  die 'project template does not stage shared localizations'

for target in release analyze clean; do
  grep -Eq "^${target}:" "$common_makefile" ||
    die "common Makefile has no ${target} target"
done

for forbidden_target in debug deb ipa install; do
  if grep -Eq "^${forbidden_target}:" "$common_makefile"; then
    die "common Makefile exposes forbidden public target: ${forbidden_target}"
  fi
done

check_png() {
  local path="$1"
  local width="$2"
  local height="$3"
  local description=""

  description="$(file -b "$path")"
  [[ "$description" == *"PNG image data, ${width} x ${height}"* &&
    "$description" == *" RGB,"* && "$description" != *" RGBA,"* ]] ||
    die "unexpected PNG asset: ${path}: ${description}"
}

resource_root="$project_template_dir/source/iOS/Resources"
check_png "$resource_root/Default.png" 320 480
check_png "$resource_root/Default@2x.png" 640 960
check_png "$resource_root/Default-568h@2x.png" 640 1136
check_png "$resource_root/Default-iOS8-667h@2x.png" 750 1334
check_png "$resource_root/Default-iOS8-736h@3x.png" 1242 2208
check_png "$resource_root/Default-iOS11-812h@3x.png" 1125 2436
check_png "$resource_root/Default-iOS12-896h@2x.png" 828 1792
check_png "$resource_root/Default-iOS12-896h@3x.png" 1242 2688
check_png "$resource_root/AppIcon29x29.png" 29 29
check_png "$resource_root/AppIcon29x29@2x.png" 58 58
check_png "$resource_root/AppIcon40x40@2x.png" 80 80
check_png "$resource_root/AppIcon57x57.png" 57 57
check_png "$resource_root/AppIcon57x57@2x.png" 114 114
check_png "$resource_root/AppIcon60x60@2x.png" 120 120
check_png "$resource_root/AppIcon60x60@3x.png" 180 180

check_root="$(mktemp -d "${TMPDIR:-/tmp}/altivec-ios-make-check.XXXXXX")"
readonly check_root

cleanup() {
  local rc=$?

  trap - EXIT
  case "$check_root" in
    "${TMPDIR:-/tmp}"/altivec-ios-make-check.*)
      if [[ -d "$check_root" && ! -L "$check_root" ]]; then
        rm -r "$check_root"
      fi
      ;;
    *)
      printf 'error: refusing to remove unsafe validation path: %s\n' \
        "$check_root" >&2
      rc=1
      ;;
  esac
  exit "$rc"
}
trap cleanup EXIT

mkdir -p \
  "$check_root/fake-prefix/bin" \
  "$check_root/fake-prefix/Libraries/1.0.9/AltivecCore/include" \
  "$check_root/fake-prefix/Libraries/1.0.9/AltivecCore/lib" \
  "$check_root/fake-prefix/Libraries/1.0.9/AltivecCocoa/include" \
  "$check_root/fake-prefix/Libraries/1.0.9/AltivecCocoa/lib" \
  "$check_root/fake-prefix/Libraries/1.0.9/Bundle/Fonts" \
  "$check_root/fake-prefix/lib/arc" \
  "$check_root/fake-prefix/share/altivec-lib" \
  "$check_root/fake-prefix/share/altivec/make" \
  "$check_root/fake-prefix/SDKs/Current.sdk/System/Library/Frameworks/UIKit.framework/Headers"

cp "$common_makefile" \
  "$check_root/fake-prefix/share/altivec/make/ios-app.mk"
printf '%s\n' '/* validation header */' \
  > "$check_root/fake-prefix/SDKs/Current.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIKit.h"

managed_root="$check_root/fake-prefix/Libraries/1.0.9"
readonly managed_root
printf '%s\n' 'fake core archive' \
  > "$managed_root/AltivecCore/lib/libAltivecCore.a"
printf '%s\n' 'fake cocoa archive' \
  > "$managed_root/AltivecCocoa/lib/libAltivecCocoa.a"
printf '%s\n' '/* fake core header */' \
  > "$managed_root/AltivecCore/include/AltivecCore.h"
printf '%s\n' '/* fake cocoa header */' \
  > "$managed_root/AltivecCocoa/include/AltivecCocoa.h"
printf '%s\n' 'managed CA bundle' > "$managed_root/Bundle/cacert.pem"
printf '%s\n' 'managed font' > "$managed_root/Bundle/Fonts/font.ttf"
printf '%s\n' 'fake ARC compatibility archive' \
  > "$check_root/fake-prefix/lib/arc/libarclite_iphoneos.a"

{
  printf '%s\n' 'ALTIVEC_MANAGED_VERSION := 1.0.9'
  printf 'ALTIVEC_MANAGED_ROOT := %s\n' "$managed_root"
  printf 'ALTIVEC_MANAGED_INCLUDE_DIRS := %s %s\n' \
    "$managed_root/AltivecCore/include" \
    "$managed_root/AltivecCocoa/include"
  printf 'ALTIVEC_MANAGED_ARCHIVES := %s %s\n' \
    "$managed_root/AltivecCocoa/lib/libAltivecCocoa.a" \
    "$managed_root/AltivecCore/lib/libAltivecCore.a"
  printf '%s\n' 'ALTIVEC_MANAGED_FRAMEWORKS := CoreText'
  printf 'ALTIVEC_MANAGED_BUNDLE_DIR := %s\n' \
    "$managed_root/Bundle"
  printf 'ALTIVEC_MANAGED_RESOURCE_FILES := %s %s\n' \
    "$managed_root/Bundle/cacert.pem" \
    "$managed_root/Bundle/Fonts/font.ttf"
} > "$check_root/fake-prefix/share/altivec-lib/current.mk"

# These fake tools let the host check execute packaging without an iOS
# compiler or signer.
for tool in clang clang++; do
  # shellcheck disable=SC2016
  printf '%s\n' \
    '#!/bin/sh' \
    'output=' \
    'while [ "$#" -gt 0 ]; do' \
    '  if [ "$1" = "-o" ]; then shift; output="$1"; fi' \
    '  shift' \
    'done' \
    'if [ -n "$output" ]; then' \
    '  mkdir -p "$(dirname "$output")"' \
    '  printf "fake compiler output\n" > "$output"' \
    'fi' \
    'exit 0' \
    > "$check_root/fake-prefix/bin/$tool"
done
printf '%s\n' '#!/bin/sh' 'exit 0' \
  > "$check_root/fake-prefix/bin/ldid"
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/bin/sh' \
  'shift' \
  'output="$1"' \
  'mkdir -p "$(dirname "$output")"' \
  'printf "fake zip\n" > "$output"' \
  > "$check_root/fake-prefix/bin/zip"
chmod 0755 "$check_root/fake-prefix/bin/clang" \
  "$check_root/fake-prefix/bin/clang++" \
  "$check_root/fake-prefix/bin/ldid" \
  "$check_root/fake-prefix/bin/zip"

ALTIVEC_APP_TEMPLATE_ROOT="$project_template_dir" \
  "$app_tool" new \
    --name ValidationApp \
    --display-name 'Validation App' \
    --bundle-id com.altivecintelligence.validation \
    --destination "$check_root/project" \
    > "$check_root/initializer.txt"

if ALTIVEC_APP_TEMPLATE_ROOT="$project_template_dir" \
    "$app_tool" new \
      --name ValidationApp \
      --bundle-id com.altivecintelligence.validation \
      --destination "$check_root/project" >/dev/null 2>&1; then
  die 'initializer overwrote an existing destination'
fi

grep -Fq '<string>Validation App</string>' \
  "$check_root/project/source/iOS/Info.plist" ||
  die 'initializer did not render the display name'
grep -Fq '<string>com.altivecintelligence.validation</string>' \
  "$check_root/project/source/iOS/Info.plist" ||
  die 'initializer did not render the bundle identifier'
if grep -R '@ALTIVEC_' "$check_root/project" >/dev/null 2>&1; then
  die 'initializer left unresolved project placeholders'
fi

# Exercise project-over-managed resource precedence in the generated app.
mkdir -p \
  "$check_root/project/source/iOS/Resources/Data" \
  "$check_root/project/source/iOS/Resources/Fonts"
printf '%s\n' 'validation resource' \
  > "$check_root/project/source/iOS/Resources/Data/value.txt"
printf '%s\n' 'project CA bundle' \
  > "$check_root/project/source/iOS/Resources/cacert.pem"
printf '%s\n' 'project font override' \
  > "$check_root/project/source/iOS/Resources/Fonts/font.ttf"

project_makefile="$check_root/project/source/iOS/Makefile"
awk '
    /^ALTIVEC_PREFIX / && !added {
      print "RESOURCES += Data/value.txt cacert.pem Fonts"
      added = 1
    }
    { print }
  ' "$project_makefile" > "$project_makefile.updated"
mv "$project_makefile.updated" "$project_makefile"

fake_prefix="$check_root/fake-prefix"
readonly fake_prefix
make -C "$check_root/project" --no-print-directory -n release \
  ALTIVEC_PREFIX="$fake_prefix" > "$check_root/release-dry-run.txt"
make -C "$check_root/project" --no-print-directory -n analyze \
  ALTIVEC_PREFIX="$fake_prefix" > "$check_root/analyze-dry-run.txt"
make -C "$check_root/project" --no-print-directory -n \
  ALTIVEC_PREFIX="$fake_prefix" > "$check_root/default-dry-run.txt"
make -C "$check_root/project" --no-print-directory -n release \
  ALTIVEC_PREFIX="$fake_prefix" IPHONEOS_DEPLOYMENT_TARGET=6.0 \
  > "$check_root/ios6-override-dry-run.txt"
make -C "$check_root/project" --no-print-directory -n release \
  ALTIVEC_PREFIX="$fake_prefix" APP_USE_ARC=0 \
  > "$check_root/ios43-mrc-dry-run.txt"

grep -Fq 'ValidationApp.app' "$check_root/release-dry-run.txt" ||
  die 'release dry run does not assemble an .app'
grep -Fq 'ValidationApp.ipa' "$check_root/release-dry-run.txt" ||
  die 'release dry run does not package an IPA'
grep -Fq -- '--analyze' "$check_root/analyze-dry-run.txt" ||
  die 'analyze dry run does not invoke the Clang analyzer'
grep -Fq 'ValidationApp.ipa' "$check_root/default-dry-run.txt" ||
  die 'release is not the default repository target'
grep -Fq -- '--target=armv7-apple-ios4.3' \
  "$check_root/release-dry-run.txt" ||
  die 'release does not use the default iOS 4.3 target triple'
grep -Fq -- '-miphoneos-version-min=4.3' \
  "$check_root/release-dry-run.txt" ||
  die 'release does not pass the iOS 4.3 deployment target'
grep -Fq -- '-fobjc-arc' "$check_root/release-dry-run.txt" ||
  die 'default iOS 4.3 release does not enable ARC'
if grep -Fq -- '-fobjc-arc' "$check_root/ios43-mrc-dry-run.txt"; then
  die 'APP_USE_ARC=0 did not disable ARC for iOS 4.3'
fi
grep -Fq -- '--target=armv7-apple-ios6.0' \
  "$check_root/ios6-override-dry-run.txt" ||
  die 'deployment-target override did not reach the target triple'
grep -Fq "$managed_root/AltivecCocoa/lib/libAltivecCocoa.a" \
  "$check_root/release-dry-run.txt" ||
  die 'release does not link the selected AltivecCocoa archive'
grep -Fq -- "-I$managed_root/AltivecCore/include" \
  "$check_root/release-dry-run.txt" ||
  die 'release does not add managed AltivecCore headers'
grep -Fq -- '-framework CoreText' "$check_root/release-dry-run.txt" ||
  die 'release does not add managed system frameworks'
grep -Fq 'for localization_root in ../shared/Resources' \
  "$check_root/release-dry-run.txt" ||
  die 'release does not stage shared localization directories'

make -C "$check_root/project" --no-print-directory -n release \
  ALTIVEC_PREFIX="$fake_prefix" ALTIVEC_LIBS=none \
  > "$check_root/no-managed-libs-dry-run.txt"
if grep -Fq "$managed_root/AltivecCore/lib/libAltivecCore.a" \
    "$check_root/no-managed-libs-dry-run.txt"; then
  die 'ALTIVEC_LIBS=none did not disable managed libraries'
fi

outside_localizations="$check_root/outside-localizations"
mkdir -p "$outside_localizations/en.lproj"
printf '%s\n' '"Outside" = "Outside";' \
  > "$outside_localizations/en.lproj/Localizable.strings"
if make -C "$check_root/project/source/iOS" --no-print-directory \
    __altivec_ios_validate ALTIVEC_PREFIX="$fake_prefix" \
    BUNDLE_LOCALIZATION_DIRS="$outside_localizations" \
    > "$check_root/outside-localizations.txt" 2>&1; then
  die 'localization validation allowed a root outside the app repository'
fi
grep -Fq 'localization root escapes app project' \
  "$check_root/outside-localizations.txt" ||
  die 'outside-localization failure did not explain the project boundary'

make -C "$check_root/project" --no-print-directory release \
  ALTIVEC_PREFIX="$fake_prefix" > "$check_root/release.txt"
grep -Fq '[LOCALIZATIONS] ../shared/Resources' "$check_root/release.txt" ||
  die 'executed release did not report shared localization staging'
app_dir="$check_root/project/source/iOS/build-release/ValidationApp.app"
ipa_path="$check_root/project/source/iOS/build-release/ValidationApp.ipa"
readonly app_dir ipa_path
[[ -f "$app_dir/ValidationApp" && -f "$ipa_path" ]] ||
  die 'executed release did not produce an app and IPA'
cmp "$check_root/project/source/iOS/Info.plist" "$app_dir/Info.plist" ||
  die 'release did not copy the generated Info.plist'
cmp "$check_root/project/source/shared/Resources/en.lproj/Localizable.strings" \
  "$app_dir/en.lproj/Localizable.strings" ||
  die 'release did not copy shared localized strings'
cmp "$check_root/project/source/iOS/Resources/Default.png" \
  "$app_dir/Default.png" ||
  die 'release did not copy a launch image'
cmp "$check_root/project/source/iOS/Resources/cacert.pem" \
  "$app_dir/cacert.pem" ||
  die 'project resource did not override managed cacert.pem'
cmp "$check_root/project/source/iOS/Resources/Fonts/font.ttf" \
  "$app_dir/Fonts/font.ttf" ||
  die 'project directory resource did not override the managed font'
[[ ! -e "$app_dir/Fonts/Fonts" ]] ||
  die 'managed and project directory resources nested incorrectly'

for launch_image in \
  Default.png \
  Default@2x.png \
  Default-568h@2x.png \
  Default-iOS8-667h@2x.png \
  Default-iOS8-736h@3x.png \
  Default-iOS11-812h@3x.png \
  Default-iOS12-896h@2x.png \
  Default-iOS12-896h@3x.png; do
  [[ -f "$app_dir/$launch_image" ]] ||
    die "application bundle is missing launch image: ${launch_image}"
done

for unsupported_target in debug deb ipa; do
  if make -C "$check_root/project" --no-print-directory -n \
      "$unsupported_target" ALTIVEC_PREFIX="$fake_prefix" \
      >/dev/null 2>&1; then
    die "unexpected repository target is available: ${unsupported_target}"
  fi
done

make -C "$check_root/project" --no-print-directory analyze \
  ALTIVEC_PREFIX="$fake_prefix" > "$check_root/analyze.txt"
analyze_report="$check_root/project/source/iOS/build-analyze/analyze.txt"
for source_name in main.m AppDelegate.m UI/MainViewController.m \
  ../shared/app_model.c; do
  grep -Fq "== ${source_name} ==" "$analyze_report" ||
    die "analyze report omitted source: ${source_name}"
done

make -C "$check_root/project" --no-print-directory clean \
  ALTIVEC_PREFIX="$fake_prefix"
[[ ! -e "$check_root/project/source/iOS/build-release" &&
  ! -e "$check_root/project/source/iOS/build-analyze" ]] ||
  die 'clean did not remove both generated build directories'
[[ -f "$check_root/project/source/iOS/main.m" &&
  -f "$check_root/project/source/shared/app_model.c" &&
  -f "$check_root/project/source/iOS/Resources/Default.png" ]] ||
  die 'clean removed project inputs'

printf '%s\n' \
  'Complete iOS app template, initializer, localization, and Make rules passed.'
