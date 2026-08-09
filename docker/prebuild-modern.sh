#!/usr/bin/env bash

# Prepare a pinned current OSXCross checkout and the SDK inputs used by the
# modern macOS and iOS profiles.

set -euo pipefail

BASE_DIR="$(pwd)"
readonly BASE_DIR
readonly TARBALLS_DIR="$BASE_DIR/tarballs"
readonly TEMP_DIR="$BASE_DIR/temp_build_assets"
readonly OSXCROSS_GIT="https://github.com/tpoechtrager/osxcross.git"
readonly OSXCROSS_COMMIT="27d21e4977c9751d01199c7a226a6faf494c3dd9"

curl_retry() {
  curl --fail --location --silent --show-error \
       --retry 5 --retry-delay 2 --retry-all-errors \
       --connect-timeout 30 "$@"
}

trap 'rm -rf "$TEMP_DIR"' EXIT
mkdir -p "$TARBALLS_DIR" "$TEMP_DIR"

echo "--- Initializing Modern Toolchain Source ---"
echo "  > Fetching osxcross ($OSXCROSS_COMMIT)"
git -C "$TEMP_DIR" init --quiet osxcross
git -C "$TEMP_DIR/osxcross" remote add origin "$OSXCROSS_GIT"
git -C "$TEMP_DIR/osxcross" fetch --quiet --depth 1 origin "$OSXCROSS_COMMIT"
git -C "$TEMP_DIR/osxcross" checkout --quiet --detach FETCH_HEAD
cp -a "$TEMP_DIR/osxcross"/. ./

echo "--- Downloading Modern SDKs ---"
curl_retry \
  https://github.com/phracker/MacOSX-SDKs/releases/download/11.3/MacOSX11.3.sdk.tar.xz \
  -o "$TARBALLS_DIR/MacOSX11.3.sdk.tar.xz"
curl_retry \
  https://github.com/okanon/iPhoneOS.sdk/releases/download/v0.0.1/iPhoneOS8.4.sdk.tar.gz \
  -o "$TARBALLS_DIR/iPhoneOS8.4.sdk.tar.gz"

sha256sum -c <<EOF
cd4f08a75577145b8f05245a2975f7c81401d75e9535dcffbb879ee1deefcbf4  $TARBALLS_DIR/MacOSX11.3.sdk.tar.xz
677be5a92577c5e29cbab6067a9a624a3369af1cc00578941565886ea6a0a7da  $TARBALLS_DIR/iPhoneOS8.4.sdk.tar.gz
EOF

echo "--- Modern toolchain preparation complete ---"
