#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf '%s\n' \
    "Usage: $(basename "$0") --device <ssh-host> --deb <package.deb>" \
    '       --package-id <id> --version <version> --arch <architecture>' \
    '       [--dpkg-deb <tool>]' \
    '' \
    'Uploads and installs an existing Debian package over SSH. The uploaded' \
    'copy is always removed from the device.'
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

device=""
deb_path=""
expected_package=""
expected_version=""
expected_arch=""
dpkg_deb_tool="dpkg-deb"
remote_deb=""
remote_deb_valid=0
ssh_options=(
  -o BatchMode=yes
  -o ConnectTimeout=10
)

while (($#)); do
  case "$1" in
    --device)
      (($# >= 2)) || die '--device requires a value'
      device="$2"
      shift 2
      ;;
    --deb)
      (($# >= 2)) || die '--deb requires a value'
      deb_path="$2"
      shift 2
      ;;
    --package-id)
      (($# >= 2)) || die '--package-id requires a value'
      expected_package="$2"
      shift 2
      ;;
    --version)
      (($# >= 2)) || die '--version requires a value'
      expected_version="$2"
      shift 2
      ;;
    --arch)
      (($# >= 2)) || die '--arch requires a value'
      expected_arch="$2"
      shift 2
      ;;
    --dpkg-deb)
      (($# >= 2)) || die '--dpkg-deb requires a value'
      dpkg_deb_tool="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$device" ]] || die '--device is required'
[[ -n "$deb_path" ]] || die '--deb is required'
[[ -n "$expected_package" ]] || die '--package-id is required'
[[ -n "$expected_version" ]] || die '--version is required'
[[ -n "$expected_arch" ]] || die '--arch is required'
[[ "$device" =~ ^[A-Za-z0-9_.@%:+-]+$ && "$device" != -* ]] ||
  die "unsafe SSH host or alias: $device"
[[ "$expected_package" =~ ^[A-Za-z0-9.+-]+$ ]] ||
  die "unsafe package id: $expected_package"
[[ "$expected_version" =~ ^[A-Za-z0-9.+:~_-]+$ ]] ||
  die "unsafe package version: $expected_version"
[[ "$expected_arch" =~ ^[A-Za-z0-9_-]+$ ]] ||
  die "unsafe package architecture: $expected_arch"
[[ -f "$deb_path" ]] ||
  die "package is missing: $deb_path (run 'make deb' first)"
command -v "$dpkg_deb_tool" >/dev/null 2>&1 ||
  die "dpkg-deb tool not found: $dpkg_deb_tool"
command -v ssh >/dev/null 2>&1 || die 'ssh not found'
command -v scp >/dev/null 2>&1 || die 'scp not found'

actual_package="$("$dpkg_deb_tool" -f "$deb_path" Package)"
actual_version="$("$dpkg_deb_tool" -f "$deb_path" Version)"
actual_arch="$("$dpkg_deb_tool" -f "$deb_path" Architecture)"

[[ "$actual_package" == "$expected_package" ]] ||
  die "package id is $actual_package, expected $expected_package"
[[ "$actual_version" == "$expected_version" ]] ||
  die "package version is $actual_version, expected $expected_version"
[[ "$actual_arch" == "$expected_arch" ]] ||
  die "package architecture is $actual_arch, expected $expected_arch"

cleanup() {
  local rc=$?

  trap - EXIT
  if [[ "$remote_deb_valid" -eq 1 ]]; then
    if ! ssh "${ssh_options[@]}" "$device" \
        /bin/rm -f "$remote_deb" >/dev/null 2>&1; then
      printf 'error: could not remove device upload: %s:%s\n' \
        "$device" "$remote_deb" >&2
      rc=1
    fi
  fi
  exit "$rc"
}
trap cleanup EXIT

printf 'Checking SSH access to %s...\n' "$device"
remote_deb="$(
  ssh "${ssh_options[@]}" "$device" \
    'umask 077; /bin/mktemp /var/tmp/altivec-device-install.XXXXXX'
)"
[[ "$remote_deb" =~ ^/var/tmp/altivec-device-install\.[A-Za-z0-9]+$ ]] ||
  die "device returned an unsafe temporary path: $remote_deb"
remote_deb_valid=1

printf 'Uploading %s %s to %s...\n' \
  "$expected_package" "$expected_version" "$device"
scp -O -q "${ssh_options[@]}" \
  "$deb_path" "${device}:${remote_deb}"

remote_package="$(
  ssh "${ssh_options[@]}" "$device" \
    /usr/bin/dpkg-deb -f "$remote_deb" Package
)"
remote_version="$(
  ssh "${ssh_options[@]}" "$device" \
    /usr/bin/dpkg-deb -f "$remote_deb" Version
)"
remote_arch="$(
  ssh "${ssh_options[@]}" "$device" \
    /usr/bin/dpkg-deb -f "$remote_deb" Architecture
)"
[[ "$remote_package" == "$expected_package" &&
  "$remote_version" == "$expected_version" &&
  "$remote_arch" == "$expected_arch" ]] ||
  die "uploaded package metadata does not match the local package"

printf 'Installing on %s...\n' "$device"
ssh "${ssh_options[@]}" "$device" \
  /usr/bin/dpkg -i "$remote_deb"

installed_control="$(
  ssh "${ssh_options[@]}" "$device" \
    /usr/bin/dpkg-query -s "$expected_package"
)"
installed_status=""
installed_version=""
while IFS=: read -r control_field control_value; do
  control_value="${control_value# }"
  case "$control_field" in
    Status) installed_status="$control_value" ;;
    Version) installed_version="$control_value" ;;
  esac
done <<< "$installed_control"
[[ "$installed_status" == "install ok installed" ]] ||
  die "package status after installation is: $installed_status"
[[ "$installed_version" == "$expected_version" ]] ||
  die "installed version is $installed_version, expected $expected_version"

printf 'Installed %s %s on %s.\n' \
  "$expected_package" "$installed_version" "$device"
