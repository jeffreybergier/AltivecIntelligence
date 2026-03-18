#!/usr/bin/env bash
# create_super_sdk.sh - Merges 10.4u, 10.5, and 10.6 into a single SDK

set -e

BASE_DIR=$(pwd)
WORK_DIR="$BASE_DIR/super_sdk_work"
OUTPUT_DIR="$BASE_DIR/tarballs"

# URLs for Phracker sources
SDK106_URL="https://github.com/phracker/MacOSX-SDKs/releases/download/11.0-11.1/MacOSX10.6.sdk.tar.xz"
SDK105_URL="https://github.com/phracker/MacOSX-SDKs/releases/download/11.0-11.1/MacOSX10.5.sdk.tar.xz"
SDK104_URL="https://github.com/phracker/MacOSX-SDKs/releases/download/11.0-11.1/MacOSX10.4u.sdk.tar.xz"

# Ensure cleanup on exit
trap 'rm -rf "$WORK_DIR"' EXIT

echo "--- STARTING SUPER SDK CREATION ---"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

echo "[1/6] Downloading all Phracker sources..."
wget -q "$SDK106_URL" -O "$WORK_DIR/10.6.tar.xz"
wget -q "$SDK105_URL" -O "$WORK_DIR/10.5.tar.xz"
wget -q "$SDK104_URL" -O "$WORK_DIR/10.4.tar.xz"

echo "[2/6] Extracting SDKs..."
mkdir -p "$WORK_DIR/106" "$WORK_DIR/105" "$WORK_DIR/104"
tar -xJf "$WORK_DIR/106.tar.xz" -C "$WORK_DIR/106"
tar -xJf "$WORK_DIR/10.5.tar.xz" -C "$WORK_DIR/105"
tar -xJf "$WORK_DIR/10.4.tar.xz" -C "$WORK_DIR/104"

# Source paths
SRC106="$WORK_DIR/106/MacOSX10.6.sdk"
SRC105="$WORK_DIR/105/MacOSX10.5.sdk"
SRC104="$WORK_DIR/104/MacOSX10.4u.sdk"

echo "[3/6] Injecting Leopard (10.5) support..."
# Copy all object files from 10.5 as primary stubs
cp "$SRC105/usr/lib/"*.o "$SRC106/usr/lib/"
# Create explicit 10.5 versioned stubs for clarity
for f in "$SRC105/usr/lib/"*.o; do
    filename=$(basename "$f")
    cp "$f" "$SRC106/usr/lib/${filename%.o}.10.5.o"
done
cp -R "$SRC105/usr/lib/gcc" "$SRC106/usr/lib/"

echo "[4/6] Injecting Tiger (10.4) support..."
# Create explicit 10.4 versioned stubs from 10.4u
for f in "$SRC104/usr/lib/"*.o; do
    filename=$(basename "$f")
    cp "$f" "$SRC106/usr/lib/${filename%.o}.10.4.o"
done
# Layer in any unique GCC files from 10.4u
cp -rn "$SRC104/usr/lib/gcc" "$SRC106/usr/lib/"

echo "[5/6] Finalizing Super SDK Metadata..."
# Update the display name in the Plist so you know it's the Super version
sed -i 's/Mac OS X 10.6/Mac OS X Super SDK (10.4-10.6)/g' "$SRC106/SDKSettings.plist"

echo "[6/6] Packaging Super SDK (Flat format)..."
cd "$SRC106"
tar -czf "$BASE_DIR/MacOSX-Super.sdk.tar.gz" .
cd "$BASE_DIR"

mv "MacOSX-Super.sdk.tar.gz" "$OUTPUT_DIR/"

echo "--- SUCCESS ---"
echo "Super SDK created at: $OUTPUT_DIR/MacOSX-Super.sdk.tar.gz"
