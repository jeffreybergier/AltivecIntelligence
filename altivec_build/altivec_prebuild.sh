#!/usr/bin/env bash

# AltivecIntelligence Pre-build Script
# This script clones osxcross and prepares the Hybrid SDK

set -e

BASE_DIR=$(pwd)
TARBALLS_DIR="$BASE_DIR/tarballs"
TEMP_DIR="$BASE_DIR/temp_build_assets"
OSXCROSS_GIT="https://github.com/tpoechtrager/osxcross.git"
OSXCROSS_BRANCH="ppc-test"

# Ensure cleanup on exit
trap 'echo "Cleaning up..."; rm -rf "$TEMP_DIR"' EXIT

# Prepare directories
mkdir -p "$TARBALLS_DIR"
mkdir -p "$TEMP_DIR/downloads"

# 1. Clone osxcross
echo "--- Initializing Toolchain Source ---"
echo "  > Cloning osxcross ($OSXCROSS_BRANCH)"
git clone --branch $OSXCROSS_BRANCH $OSXCROSS_GIT "$TEMP_DIR/osxcross" --depth 1 --quiet
cp -r "$TEMP_DIR/osxcross"/* ./

# 2. BASE REPAIR
echo "--- Repairing Build Scripts ---"
sed -i 's/if \[ $(osxcross-cmp $OSX_VERSION_MIN .<=. 10.5) -eq 1 \]; then/if false; then/g' build_gcc.sh
sed -i '/pushd $OSXCROSS_BUILD_DIR/i mkdir -p $OSXCROSS_BUILD_DIR' build_gcc.sh
curl -sL 'https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.guess' -o config.guess.new
curl -sL 'https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.sub' -o config.sub.new
sed -i '/extract "$OSXCROSS_TARBALL_DIR\/gcc-$APPLE_GCC_VERSION.tar.gz" 1/a \  find . -name "config.guess" -exec cp ../config.guess.new {} \\; \n  find . -name "config.sub" -exec cp ../config.sub.new {} \\;' build_gcc.sh

# 3. Apply Global OSXCross patches
echo "--- Applying Global Patches ---"
patch -p1 --quiet < altivec_build/osxcross-build.patch
patch -p1 --quiet < altivec_build/osxcross-tools.patch

# 4. Prepare GCC scripts
cp build_gcc.sh build_gcc_ppc.sh
patch build_gcc_ppc.sh --quiet < altivec_build/osxcross-build-gcc.patch
chmod +x build_gcc_ppc.sh build_gcc.sh
ln -sf /usr/bin/python3 /usr/local/bin/python

# 5. Download base SDKs
echo "--- Downloading SDKs ---"

echo "> Mac OS X 10.4u SDK"
curl -sL https://github.com/phracker/MacOSX-SDKs/releases/download/11.3/MacOSX10.4u.sdk.tar.xz -o "$TARBALLS_DIR/MacOSX10.4u.sdk.tar.xz"

echo "> Mac OS X 10.11 SDK"
curl -sL https://github.com/phracker/MacOSX-SDKs/releases/download/11.3/MacOSX10.11.sdk.tar.xz -o "$TARBALLS_DIR/MacOSX10.11.sdk.tar.xz"

echo "> macOS 11.3 SDK"
curl -sL https://github.com/phracker/MacOSX-SDKs/releases/download/11.3/MacOSX11.3.sdk.tar.xz -o "$TARBALLS_DIR/MacOSX11.3.sdk.tar.xz"

echo "> iPhoneOS 8.4 SDK"
curl -sL https://github.com/okanon/iPhoneOS.sdk/releases/download/v0.0.1/iPhoneOS8.4.sdk.tar.gz -o "$TARBALLS_DIR/iPhoneOS8.4.sdk.tar.gz"

# Finalize
cp altivec_build/altivec_postbuild.sh ./
echo "--- Pre-build preparation complete ---"
