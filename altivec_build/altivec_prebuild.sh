#!/usr/bin/env bash

# AltivecIntelligence Pre-build Script
# This script clones the SDK repository and prepares the tarballs directory

set -e

BASE_DIR=$(pwd)
TARBALLS_DIR="$BASE_DIR/tarballs"
TEMP_DIR="$BASE_DIR/temp_sdk"

echo "Preparing tarballs directory..."
mkdir -p "$TARBALLS_DIR"

# Ensure python is linked to python3 (required by some build scripts)
echo "Ensuring python symlink exists..."
ln -sf /usr/bin/python3 /usr/local/bin/python

# Clone the SDK repository if it hasn't been cloned yet
if [ ! -d "$TEMP_DIR" ]; then
    echo "Downloading SDKs"
    git clone https://bitbucket.org/retromacdev/sdk.git "$TEMP_DIR" --depth 1
fi

echo "Moving SDK tarballs to $TARBALLS_DIR..."
# Move all tarballs from the cloned repo to the tarballs directory
# We look for .tar.gz and .tar.xz files which are typical for SDKs and cctools
find "$TEMP_DIR" -maxdepth 1 -name "*.tar.*" -exec mv {} "$TARBALLS_DIR/" \;

echo "Cleaning up temporary SDK repository..."
rm -rf "$TEMP_DIR"

echo "Pre-build preparation complete."
