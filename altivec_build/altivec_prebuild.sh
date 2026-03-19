#!/usr/bin/env bash

# AltivecIntelligence Pre-build Script
# This script clones osxcross and prepares the Perfect Hybrid SDK

set -e

BASE_DIR=$(pwd)
TARBALLS_DIR="$BASE_DIR/tarballs"
TEMP_DIR="$BASE_DIR/temp_build_assets"
OSXCROSS_GIT="https://github.com/tpoechtrager/osxcross.git"
OSXCROSS_BRANCH="ppc-test"

# Ensure cleanup on exit
trap 'echo "Cleaning up..."; rm -rf "$TEMP_DIR"' EXIT

# Prepare directories
echo "Preparing directories..."
mkdir -p "$TARBALLS_DIR"
mkdir -p "$TEMP_DIR/downloads"

# 1. Clone osxcross ppc-test branch
echo "Cloning osxcross ($OSXCROSS_BRANCH branch)..."
git clone --branch $OSXCROSS_BRANCH $OSXCROSS_GIT "$TEMP_DIR/osxcross" --depth 1

# Move contents to current directory
echo "Moving osxcross files to $BASE_DIR..."
cp -r "$TEMP_DIR/osxcross"/* ./

# 2. BASE REPAIR: Fix build_gcc.sh for modern systems and 10.5 compatibility
echo "Performing Base Repair on build_gcc.sh..."

# A. Remove the 10.6 version restriction (More robust regex)
sed -i 's/if \[ $(osxcross-cmp $OSX_VERSION_MIN .<=. 10.5) -eq 1 \]; then/if false; then/g' build_gcc.sh

# B. Ensure build directory exists before pushd (Fixes Intel pass crash)
sed -i '/pushd $OSXCROSS_BUILD_DIR/i mkdir -p $OSXCROSS_BUILD_DIR' build_gcc.sh

# C. Add aarch64 support by downloading modern config scripts
wget -q 'https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.guess' -O config.guess.new
wget -q 'https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.sub' -O config.sub.new

# D. Inject the config script replacement into the extraction logic
sed -i '/extract "$OSXCROSS_TARBALL_DIR\/gcc-$APPLE_GCC_VERSION.tar.gz" 1/a \  find . -name "config.guess" -exec cp ../config.guess.new {} \\; \n  find . -name "config.sub" -exec cp ../config.sub.new {} \\;' build_gcc.sh

# 3. Apply Global OSXCross patches
echo "Applying global patches..."
patch -p1 < altivec_build/osxcross-build.patch
patch -p1 < altivec_build/osxcross-tools.patch
patch -p1 < altivec_build/osxcross-build-clang.patch

# 4. Prepare Architecture-Specific GCC scripts
echo "Preparing architecture-specific GCC scripts..."
# Create the PowerPC-specific build script from the REPAIRED base
cp build_gcc.sh build_gcc_ppc.sh
patch build_gcc_ppc.sh < altivec_build/osxcross-build-gcc.patch

chmod +x build_gcc_ppc.sh
chmod +x build_gcc.sh

# Ensure python is linked to python3
echo "Ensuring python symlink exists..."
ln -sf /usr/bin/python3 /usr/local/bin/python

# 5. Download base SDKs
echo "Downloading base SDKs..."
wget -q https://github.com/phracker/MacOSX-SDKs/releases/download/11.0-11.1/MacOSX10.6.sdk.tar.xz -O "$TEMP_DIR/downloads/phreak106.tar.xz"
git clone https://bitbucket.org/retromacdev/sdk.git "$TEMP_DIR/retro_repo" --depth 1
cp "$TEMP_DIR/retro_repo/MacOSX10.6.sdk.tar.gz" "$TEMP_DIR/downloads/retro106.tar.gz"

# 6. Generate the Hybrid SDK
echo "Generating Perfect Hybrid SDK..."
./altivec_build/altivec_sdk_mac.sh "$TEMP_DIR/downloads" "$TARBALLS_DIR/MacOSX10.6.sdk.tar.xz"

# 7. Handle iPhone SDK
cp "$TEMP_DIR/retro_repo/"iPhoneOS*.tar.* "$TARBALLS_DIR/"

# Ensure our custom scripts are available
cp altivec_build/altivec_postbuild.sh ./

echo "Pre-build preparation complete."
