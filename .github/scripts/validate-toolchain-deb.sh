#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

if (($# != 2)); then
  printf 'Usage: %s <package.deb> <expected-version>\n' \
    "$(basename "$0")" >&2
  exit 2
fi

for tool in awk dpkg-deb find grep mktemp rm sha256sum stat; do
  command -v "$tool" >/dev/null 2>&1 ||
    die "required package validation tool not found: ${tool}"
done

readonly package_path="$1"
readonly expected_version="$2"

[[ "$expected_version" =~ ^[0-9]+([.][0-9]+){0,2}$ ]] ||
  die "invalid expected version: ${expected_version}"
[[ -s "$package_path" ]] || die "Debian package is missing: ${package_path}"

field() {
  dpkg-deb -f "$package_path" "$1"
}

[[ "$(field Package)" == 'com.altivecintelligence.toolchain' ]] ||
  die 'unexpected Debian package identifier'
[[ "$(field Version)" == "$expected_version" ]] ||
  die "Debian version does not match ${expected_version}"
[[ "$(field Architecture)" == 'iphoneos-arm' ]] ||
  die 'unexpected Debian architecture'
[[ "$(field Depends)" == 'firmware (>= 6.0), openssh, profile.d' ]] ||
  die 'unexpected Debian dependency set'
[[ "$(field Conflicts)" == *com.altivecintelligence.altivecchain* ]] ||
  die 'legacy AltivecChain conflict metadata is missing'
[[ "$(stat -c %s "$package_path")" -gt 1000000 ]] ||
  die 'Debian package is implausibly small'

contents="$(dpkg-deb --contents "$package_path")"
if grep -Eiq '(^|/)[^/]*[.]sdk(/|$)|[.]sdk[.]tar[.](gz|xz)([[:space:]]|$)|arclite' \
    <<< "$contents"; then
  die 'Debian package contains Apple SDK or ARCLite content'
fi
audit_dir="$(mktemp -d "${TMPDIR:-/tmp}/altivec-deb-audit.XXXXXX")"
readonly audit_dir
cleanup() {
  rm -rf -- "$audit_dir"
}
trap cleanup EXIT
dpkg-deb --extract "$package_path" "$audit_dir"
while IFS= read -r -d '' packaged_file; do
  if [[ "$(sha256sum "$packaged_file" | awk '{print $1}')" == \
      f019ba9bf87bb7a47cfd063542d9e6ed81efe76472c869ad509230aafef18bf8 ]]; then
    die "Debian package contains Apple Xcode ARCLite: ${packaged_file}"
  fi
done < <(find "$audit_dir" -type f -size 284128c -print0)
for expected_path in \
  './etc/profile.d/altivec.sh' \
  './var/altivec/bin/altivec-app' \
  './var/altivec/bin/altivec-lib' \
  './var/altivec/bin/altivec-sdk' \
  './var/altivec/bin/clang-15' \
  './var/altivec/share/altivec/make/ios-app.mk' \
  './var/altivec/share/altivec/templates/ios-app/Makefile'; do
  grep -Fq "$expected_path" <<< "$contents" ||
    die "Debian payload is missing ${expected_path}"
done

dpkg-deb --info "$package_path" >/dev/null
sha256sum "$package_path"
