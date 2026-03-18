#!/usr/bin/env bash
# hybridize_sdk.sh - Recreates the RetroMacDev 10.6 SDK using Phracker sources

set -e

BASE_DIR=$(pwd)
WORK_DIR="$BASE_DIR/hybrid_work"
OUTPUT_DIR="$BASE_DIR/tarballs"
SDK106_URL="https://github.com/phracker/MacOSX-SDKs/releases/download/11.0-11.1/MacOSX10.6.sdk.tar.xz"
SDK105_URL="https://github.com/phracker/MacOSX-SDKs/releases/download/11.0-11.1/MacOSX10.5.sdk.tar.xz"

# Ensure cleanup on exit
trap 'rm -rf "$WORK_DIR"' EXIT

echo "--- STARTING HYBRIDIZATION ---"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

echo "[1/5] Downloading Phracker sources..."
wget -q "$SDK106_URL" -O "$WORK_DIR/10.6.tar.xz"
wget -q "$SDK105_URL" -O "$WORK_DIR/10.5.tar.xz"

echo "[2/5] Extracting SDKs..."
mkdir -p "$WORK_DIR/106" "$WORK_DIR/105"
tar -xJf "$WORK_DIR/10.6.tar.xz" -C "$WORK_DIR/106"
tar -xJf "$WORK_DIR/10.5.tar.xz" -C "$WORK_DIR/105"

# Paths to the actual SDK root (handling Phracker's nesting)
SRC106="$WORK_DIR/106/MacOSX10.6.sdk"
SRC105="$WORK_DIR/105/MacOSX10.5.sdk"

echo "[3/5] Injecting legacy linker stubs (.o files)..."
# Phreak 10.6 is missing these entirely; we take them from 10.5
cp "$SRC105/usr/lib/"*.o "$SRC106/usr/lib/"

echo "[4/5] Injecting GCC runtime support..."
# This provides stubs for older architectures like PPC
cp -R "$SRC105/usr/lib/gcc" "$SRC106/usr/lib/"

echo "[5/5] Packaging Hybrid SDK (Flat format)..."
cd "$SRC106"
tar -czf "$BASE_DIR/MacOSX10.6.sdk.tar.gz" .
cd "$BASE_DIR"

mv "MacOSX10.6.sdk.tar.gz" "$OUTPUT_DIR/"

echo "--- SUCCESS ---"
echo "Hybrid SDK created at: $OUTPUT_DIR/MacOSX10.6.sdk.tar.gz"
