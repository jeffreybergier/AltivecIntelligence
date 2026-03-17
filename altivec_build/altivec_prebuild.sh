#!/usr/bin/env bash

# AltivecIntelligence Pre-build Script
# This script clones osxcross, applies patches, and prepares SDKs

set -e

BASE_DIR=$(pwd)
TARBALLS_DIR="$BASE_DIR/tarballs"
TEMP_SDK="$BASE_DIR/temp_sdk"
TEMP_OSXCROSS="$BASE_DIR/temp_osxcross"
OSXCROSS_GIT="https://github.com/tpoechtrager/osxcross.git"
OSXCROSS_BRANCH="ppc-test"

# 1. Clone osxcross ppc-test branch
echo "Cloning osxcross ($OSXCROSS_BRANCH branch)..."
git clone --branch $OSXCROSS_BRANCH $OSXCROSS_GIT "$TEMP_OSXCROSS" --depth 1

# Move contents to current directory
echo "Moving osxcross files to $BASE_DIR..."
# Use a glob to skip hidden files like .git, .gitignore, etc.
cp -r "$TEMP_OSXCROSS"/* ./
rm -rf "$TEMP_OSXCROSS"

# 2. Apply Altivec Intelligence patches
echo "Applying patches..."
patch -p1 < altivec_build/osxcross-build.patch
patch -p1 < altivec_build/osxcross-build-gcc.patch
patch -p1 < altivec_build/osxcross-build-clang.patch
patch -p1 < altivec_build/osxcross-tools.patch

# 3. Prepare tarballs directory
echo "Preparing tarballs directory..."
mkdir -p "$TARBALLS_DIR"

# Ensure python is linked to python3 (required by some build scripts)
echo "Ensuring python symlink exists..."
ln -sf /usr/bin/python3 /usr/local/bin/python

# 4. Clone the SDK repository from Bitbucket
if [ ! -d "$TEMP_SDK" ]; then
    echo "Downloading SDKs..."
    git clone https://bitbucket.org/retromacdev/sdk.git "$TEMP_SDK" --depth 1
fi

echo "Moving SDK tarballs to $TARBALLS_DIR..."
find "$TEMP_SDK" -maxdepth 1 -name "*.tar.*" -exec mv {} "$TARBALLS_DIR/" \;

echo "Cleaning up temporary SDK repository..."
rm -rf "$TEMP_SDK"

# Ensure our custom scripts are also available in the root for the next steps
cp altivec_build/altivec_postbuild.sh ./

echo "Pre-build preparation complete."
