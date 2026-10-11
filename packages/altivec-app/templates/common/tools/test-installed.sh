#!/bin/sh
# Explicitly selected rootful iOS lifecycle test. Run only on a disposable test identity.
set -eu
export PATH=/var/altivec/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH
name=$1
identifier=$2
archive=$3
stage=$4
# dpkg enforces root privileges; do not require coreutils id on old phones.
[ "$(dpkg-deb -f "$archive" Package)" = "$identifier" ]
if dpkg-query -W -f='${Status}' "$identifier" 2>/dev/null | grep -q 'install ok installed'; then
  echo 'Refusing to replace an installed project' >&2; exit 1
fi
for existing in "/usr/libexec/${name}Service" "/usr/libexec/${name}Client" "/Library/LaunchDaemons/${identifier}.plist" "/Applications/${name}.app"; do
  [ ! -e "$existing" ] || { echo "Refusing existing path: $existing" >&2; exit 1; }
done
socket="/tmp/${identifier}.sock"
[ ! -e "$socket" ] || { echo 'Socket already exists' >&2; exit 1; }
printf '%s\n' 'preserve test data' > "$stage/user-data.txt"
installed=0
cleanup() {
  if [ "$installed" = 1 ]; then dpkg --remove "$identifier"; fi
}
trap cleanup EXIT HUP INT TERM
ready() {
  n=0
  until "/usr/libexec/${name}Client" "$socket"; do
    n=$((n+1)); [ "$n" -lt 20 ] || return 1; sleep 1
  done
}
installed=1
dpkg -i "$archive"
ready
launchctl unload "/Library/LaunchDaemons/${identifier}.plist"
launchctl load "/Library/LaunchDaemons/${identifier}.plist"
ready
dpkg -i "$archive"
ready
dpkg --remove "$identifier"
installed=0
[ "$(cat "$stage/user-data.txt")" = 'preserve test data' ]
[ ! -e "/usr/libexec/${name}Service" ]
[ ! -e "/usr/libexec/${name}Client" ]
[ ! -e "/Library/LaunchDaemons/${identifier}.plist" ]
n=0
while [ -e "$socket" ]; do n=$((n+1)); [ "$n" -lt 20 ]; sleep 1; done
rm "$stage/user-data.txt"
echo 'PASS: rootful install, launchd readiness, restart, reinstall, removal and retained test data'
