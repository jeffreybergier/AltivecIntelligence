#!/usr/bin/env bash

set -euo pipefail

if [[ "${ALTIVEC_IOS_APP_SMOKE_REMOTE:-0}" != "1" ]]; then
  if (($# > 1)); then
    printf 'Usage: %s [ssh-host]\n' "$(basename "$0")" >&2
    exit 2
  fi

  readonly device_host="${1:-koolphone5}"
  [[ "$device_host" =~ ^[A-Za-z0-9_.@%:+-]+$ &&
    "$device_host" != -* ]] || {
    printf 'error: unsafe SSH host or alias: %s\n' "$device_host" >&2
    exit 1
  }

  exec ssh -o BatchMode=yes -o ConnectTimeout=10 "$device_host" \
    'ALTIVEC_IOS_APP_SMOKE_REMOTE=1 bash -l -c "$(cat)"' < "$0"
fi

unset ALTIVEC_IOS_APP_SMOKE_REMOTE

readonly altivec_prefix="/var/altivec"
readonly altivec_bin="${altivec_prefix}/bin"
readonly common_makefile="${altivec_prefix}/share/altivec/make/ios-app.mk"
readonly project_template="${altivec_prefix}/share/altivec/templates/ios-app"
readonly project_template_makefile="${project_template}/source/iOS/Makefile"
readonly app_tool="${altivec_bin}/altivec-app"
readonly temporary_root="/var/root/tmp_altivec"
readonly smoke_dir="${temporary_root}/ios-app-make-smoke.$$"

cleanup() {
  local rc=$?

  trap - EXIT
  case "$smoke_dir" in
    /var/root/tmp_altivec/ios-app-make-smoke.*)
      if [[ -d "$smoke_dir" && ! -L "$smoke_dir" ]]; then
        /bin/rm -r "$smoke_dir"
      fi
      ;;
    *)
      printf 'error: refusing to remove unsafe smoke path: %s\n' \
        "$smoke_dir" >&2
      rc=1
      ;;
  esac
  exit "$rc"
}
trap cleanup EXIT

for installed_file in \
  "$common_makefile" \
  "$project_template_makefile" \
  "$app_tool"; do
  [[ -f "$installed_file" ]] || {
    printf 'error: packaged iOS app build file is missing: %s\n' \
      "$installed_file" >&2
    exit 1
  }
done

for tool in altivec-app awk clang clang++ cmp file find grep ldid make nm otool unzip zip; do
  [[ -x "${altivec_bin}/${tool}" ]] || {
    printf 'error: installed tool is missing: %s/%s\n' \
      "$altivec_bin" "$tool" >&2
    exit 1
  }
done

[[ -d "${altivec_prefix}/SDKs/Current.sdk" ]] || {
  printf '%s\n' \
    'error: no selected SDK; install and select one with altivec-sdk first' >&2
  exit 1
}

if ! /usr/bin/dpkg-query -S "$common_makefile" |
    "${altivec_bin}/grep" -Fq \
      'com.altivecintelligence.toolchain:'; then
  printf 'error: common Makefile is not owned by the toolchain package: %s\n' \
    "$common_makefile" >&2
  exit 1
fi
if ! /usr/bin/dpkg-query -S "$app_tool" |
    "${altivec_bin}/grep" -Fq \
      'com.altivecintelligence.toolchain:'; then
  printf 'error: app initializer is not owned by the toolchain package: %s\n' \
    "$app_tool" >&2
  exit 1
fi
if ! /usr/bin/dpkg-query -S "$project_template_makefile" |
    "${altivec_bin}/grep" -Fq \
      'com.altivecintelligence.toolchain:'; then
  printf 'error: app template is not owned by the toolchain package: %s\n' \
    "$project_template_makefile" >&2
  exit 1
fi
/bin/mkdir -p "$temporary_root"
[[ -d "$temporary_root" && ! -L "$temporary_root" ]] || {
  printf 'error: unsafe temporary root: %s\n' "$temporary_root" >&2
  exit 1
}

umask 077
"$app_tool" new \
  --name AltivecMakeSmoke \
  --display-name 'Altivec Make Smoke' \
  --bundle-id com.altivecintelligence.make-smoke \
  --destination "$smoke_dir"

readonly availability_probe=\
"${smoke_dir}/source/iOS/AvailabilityWarningProbe.m"
printf '%s\n' \
  '#import <Foundation/Foundation.h>' \
  '' \
  'id AltivecSubscriptAvailabilityProbe(NSArray *values) {' \
  '  return values[0];' \
  '}' \
  > "$availability_probe"

readonly source_makefile="${smoke_dir}/source/iOS/Makefile"
readonly updated_source_makefile="${source_makefile}.updated"
"${altivec_bin}/awk" '
    /^ALTIVEC_PREFIX / && !added {
      print "SOURCES += AvailabilityWarningProbe.m"
      print "APP_OBJCFLAGS += -Wno-error=unguarded-availability"
      added = 1
    }
    { print }
    END { if (!added) exit 1 }
  ' "$source_makefile" > "$updated_source_makefile"
/bin/mv "$updated_source_makefile" "$source_makefile"

cd "$smoke_dir"

printf '%s\n' 'Building the sample app and IPA...'
if ! "${altivec_bin}/make" --no-print-directory release \
    > release-output.txt 2>&1; then
  /bin/cat release-output.txt
  exit 1
fi
/bin/cat release-output.txt
expected_subscript_warning=\
"'objectAtIndexedSubscript:' is only available on iOS 6.0 or newer"
expected_subscript_warning+=' [-Wunguarded-availability]'
readonly expected_subscript_warning
subscript_warning_count="$(
  "${altivec_bin}/grep" -F -c -- \
    "$expected_subscript_warning" release-output.txt || true
)"
readonly subscript_warning_count
[[ "$subscript_warning_count" == 1 ]] || {
  printf 'error: expected one subscripting warning, found %s\n' \
    "$subscript_warning_count" >&2
  exit 1
}
"${altivec_bin}/grep" -Fq \
  '[OBJC] AvailabilityWarningProbe.m' release-output.txt || {
    printf '%s\n' \
      'error: app build did not compile the subscripting probe' >&2
    exit 1
  }
if "${altivec_bin}/grep" -E ': (warning|error):' release-output.txt |
    "${altivec_bin}/grep" -Fv -- '[-Wdeprecated-declarations]' \
    | "${altivec_bin}/grep" -Fv -- "$expected_subscript_warning" \
      > unexpected-build-diagnostics.txt; then
  /bin/cat unexpected-build-diagnostics.txt >&2
  printf '%s\n' \
    'error: app build produced non-deprecation diagnostics' >&2
  exit 1
fi
if "${altivec_bin}/grep" -Fq \
    "using sysroot for 'Current'" release-output.txt; then
  printf '%s\n' \
    'error: selected SDK symlink was not resolved before compilation' >&2
  exit 1
fi
if "${altivec_bin}/grep" -Fq \
    'too small, changing to 7.0' release-output.txt; then
  printf '%s\n' \
    'error: linker raised the requested iOS 5.0 deployment target' >&2
  exit 1
fi

readonly app_path="${smoke_dir}/source/iOS/build-release/AltivecMakeSmoke.app"
readonly executable_path="${app_path}/AltivecMakeSmoke"
readonly ipa_path="${smoke_dir}/source/iOS/build-release/AltivecMakeSmoke.ipa"

[[ -d "$app_path" && -x "$executable_path" && -s "$ipa_path" ]] || {
  printf '%s\n' 'error: release did not produce both the .app and IPA' >&2
  exit 1
}

file_output="$("${altivec_bin}/file" "$executable_path")"
[[ "$file_output" == *"Mach-O"* &&
  ( "$file_output" == *"arm_v7"* || "$file_output" == *"armv7"* ) ]] || {
  printf 'error: unexpected app executable: %s\n' "$file_output" >&2
  exit 1
}
if ! "${altivec_bin}/nm" "$executable_path" |
    "${altivec_bin}/grep" -F \
      '_AltivecSubscriptAvailabilityProbe' >/dev/null; then
  printf '%s\n' \
    'error: linked app omitted the subscripting availability probe' >&2
  exit 1
fi
"${altivec_bin}/otool" -hv "$executable_path" >/dev/null
load_commands="$("${altivec_bin}/otool" -l "$executable_path")"
# The awk program intentionally uses its own $1/$2 fields.
# shellcheck disable=SC2016
if ! printf '%s\n' "$load_commands" | "${altivec_bin}/awk" '
    $1 == "cmd" && $2 == "LC_VERSION_MIN_IPHONEOS" {
      in_version_command = 1
      next
    }
    in_version_command && $1 == "version" && $2 == "5.0" {
      found_version = 1
    }
    END { exit(found_version ? 0 : 1) }
  '; then
  printf '%s\n' \
    'error: app executable does not declare iOS 5.0' >&2
  exit 1
fi
[[ "$load_commands" == *LC_UNIXTHREAD* ]] || {
  printf '%s\n' \
    'error: iOS 5.0 app executable has no LC_UNIXTHREAD entry point' >&2
  exit 1
}
[[ "$load_commands" != *LC_MAIN* ]] || {
  printf '%s\n' \
    'error: iOS 5.0 app executable incorrectly uses LC_MAIN' >&2
  exit 1
}
"${altivec_bin}/ldid" -e "$executable_path" > extracted-entitlements.plist

"${altivec_bin}/cmp" \
  source/iOS/Info.plist "$app_path/Info.plist"
"${altivec_bin}/cmp" \
  source/iOS/Resources/Default.png "$app_path/Default.png"
"${altivec_bin}/cmp" \
  source/shared/Resources/en.lproj/Localizable.strings \
  "$app_path/en.lproj/Localizable.strings"
[[ ! -e "$app_path/.altivec-built" ]] || {
  printf '%s\n' 'error: private build stamp leaked into the .app' >&2
  exit 1
}

"${altivec_bin}/unzip" -l "$ipa_path" > ipa-contents.txt
for ipa_entry in \
  Payload/AltivecMakeSmoke.app/AltivecMakeSmoke \
  Payload/AltivecMakeSmoke.app/Info.plist \
  Payload/AltivecMakeSmoke.app/Default.png \
  Payload/AltivecMakeSmoke.app/Default-iOS12-896h@3x.png \
  Payload/AltivecMakeSmoke.app/en.lproj/Localizable.strings; do
  "${altivec_bin}/grep" -Fq "$ipa_entry" ipa-contents.txt || {
    printf 'error: IPA is missing: %s\n' "$ipa_entry" >&2
    exit 1
  }
done

/bin/mkdir extracted-ipa
"${altivec_bin}/unzip" -q "$ipa_path" -d extracted-ipa
"${altivec_bin}/cmp" \
  source/shared/Resources/en.lproj/Localizable.strings \
  extracted-ipa/Payload/AltivecMakeSmoke.app/en.lproj/Localizable.strings

if "${altivec_bin}/find" source/iOS/build-release -name '*.deb' -print -quit |
    "${altivec_bin}/grep" -q .; then
  printf '%s\n' 'error: iOS app rules unexpectedly produced a Debian package' >&2
  exit 1
fi

printf '%s\n' \
  '#import <Foundation/Foundation.h>' \
  '#include <stdio.h>' \
  '' \
  'static int probeDeallocations;' \
  '' \
  '@interface ArcRuntimeProbe : NSObject' \
  '@property(nonatomic, strong) NSObject *value;' \
  '@end' \
  '' \
  '@implementation ArcRuntimeProbe' \
  '- (void)dealloc {' \
  '  probeDeallocations++;' \
  '}' \
  '@end' \
  '' \
  'static ArcRuntimeProbe *MakeProbe(void) {' \
  '  ArcRuntimeProbe *probe = [[ArcRuntimeProbe alloc] init];' \
  '  probe.value = [[NSObject alloc] init];' \
  '  return probe;' \
  '}' \
  '' \
  'int main(void) {' \
  '  __block int blockCalls = 0;' \
  '  @autoreleasepool {' \
  '    ArcRuntimeProbe *probe = MakeProbe();' \
  '    int (^probeBlock)(void) = ^{' \
  '      blockCalls++;' \
  '      return probe.value != nil;' \
  '    };' \
  '    if (!probeBlock()) {' \
  '      return 11;' \
  '    }' \
  '  }' \
  '  if (probeDeallocations != 1 || blockCalls != 1) {' \
  '    return 12;' \
  '  }' \
  '  printf("ARC runtime smoke passed\n");' \
  '  return 0;' \
  '}' \
  > ArcRuntimeSmoke.m

printf '%s\n' 'Building and executing the iOS 5.0 ARC runtime smoke test...'
resolved_sdk="$(cd "${altivec_prefix}/SDKs/Current.sdk" && /bin/pwd -P)"
# iOS 5 provides the ARC runtime.  Compile with ARC, then link without the ARC
# driver flag so Clang does not request ARCLite for Objective-C subscripting.
"${altivec_bin}/clang" \
  --target=armv7-apple-ios5.0 \
  -arch armv7 \
  -miphoneos-version-min=5.0 \
  -isysroot "$resolved_sdk" \
  -B"${altivec_bin}" \
  -fobjc-arc \
  -Os \
  -Wall \
  -Wextra \
  -Wunguarded-availability \
  -Werror \
  ArcRuntimeSmoke.m \
  -c \
  -o ArcRuntimeSmoke.o
"${altivec_bin}/clang" \
  --target=armv7-apple-ios5.0 \
  -arch armv7 \
  -miphoneos-version-min=5.0 \
  -isysroot "$resolved_sdk" \
  -B"${altivec_bin}" \
  ArcRuntimeSmoke.o \
  -framework Foundation \
  -o ArcRuntimeSmoke
"${altivec_bin}/ldid" -S ArcRuntimeSmoke
if "${altivec_bin}/nm" ArcRuntimeSmoke |
    "${altivec_bin}/grep" -Fq '___ARCLite__'; then
  printf '%s\n' 'error: ARC runtime smoke unexpectedly linked ARCLite' >&2
  exit 1
fi
./ArcRuntimeSmoke

if "${altivec_bin}/make" --no-print-directory -n debug \
    >/dev/null 2>&1; then
  printf '%s\n' 'error: common rules unexpectedly expose a debug target' >&2
  exit 1
fi

printf '%s\n' 'Running Clang static analysis...'
"${altivec_bin}/make" --no-print-directory analyze
readonly analyze_report="${smoke_dir}/source/iOS/build-analyze/analyze.txt"
[[ -f "$analyze_report" ]] || {
  printf '%s\n' 'error: analyze did not produce its report' >&2
  exit 1
}
for source_name in main.m AppDelegate.m UI/MainViewController.m \
  ../shared/app_model.c AvailabilityWarningProbe.m; do
  "${altivec_bin}/grep" -Fq "== ${source_name} ==" \
    "$analyze_report" || {
    printf 'error: analyze report omitted source: %s\n' \
      "$source_name" >&2
    exit 1
  }
done
if "${altivec_bin}/grep" -Fq \
    "using sysroot for 'Current'" "$analyze_report"; then
  printf '%s\n' \
    'error: selected SDK symlink was not resolved before analysis' >&2
  exit 1
fi

printf '%s\n' 'Cleaning generated app build state...'
"${altivec_bin}/make" --no-print-directory clean
[[ ! -e source/iOS/build-release && ! -e source/iOS/build-analyze ]] || {
  printf '%s\n' 'error: clean left generated build directories behind' >&2
  exit 1
}
[[ -f source/iOS/main.m && -f source/iOS/AppDelegate.m &&
  -f source/iOS/AvailabilityWarningProbe.m &&
  -f source/iOS/Resources/Default.png &&
  -f source/shared/Resources/en.lproj/Localizable.strings ]] || {
  printf '%s\n' 'error: clean removed project inputs' >&2
  exit 1
}

printf '%s\n' \
  "Common Makefile: ${common_makefile}" \
  "Project template: ${project_template}" \
  "Built executable: ${file_output}" \
  'Availability warning, IPA layout, signing, analyzer, and clean passed.' \
  'Altivec iOS app Makefile device smoke test passed.'
