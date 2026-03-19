#!/usr/bin/env bash
# create_super_sdk.sh - Recreates RetroMacDev 10.6 SDK

set -e
INPUT_DIR=$1
OUTPUT_PATH=$2

if [ -z "$INPUT_DIR" ] || [ -z "$OUTPUT_PATH" ]; then
    echo "Usage: $0 <input_tarball_dir> <output_tarball_path>"
    exit 1
fi

BASE_DIR=$(pwd)
WORK_DIR="$BASE_DIR/super_sdk_work"

# Ensure cleanup on exit
trap 'rm -rf "$WORK_DIR"' EXIT

echo "--- CREATING PERFECT HYBRID SDK ---"
mkdir -p "$WORK_DIR/phreak106" "$WORK_DIR/retro106"

echo "[1/4] Extracting Source SDKs..."
# Base: Phracker 10.6 (Modern headers)
tar -xJf "$INPUT_DIR/phreak106.tar.xz" -C "$WORK_DIR/phreak106"
# Donor: RetroMacDev 10.6 (Proven libraries/stubs)
tar -xzf "$INPUT_DIR/retro106.tar.gz" -C "$WORK_DIR/retro106"

# Handle Phracker's nesting
SRC106="$WORK_DIR/phreak106/MacOSX10.6.sdk"
RETRO106="$WORK_DIR/retro106/MacOSX10.6.sdk"

# 1. Base is 10.6 (Headers, etc.)
# 2. OVERWRITE libraries with RetroMacDev versions
echo "[2/4] Injecting RetroMacDev library structure into 10.6 base..."
rm -rf "$SRC106/usr/lib"
cp -R "$RETRO106/usr/lib" "$SRC106/usr/"

# 3. Ensure all versioned stubs are present (matching Retro exactly)
echo "[3/4] Synchronizing linker stubs..."
cp -n "$RETRO106/usr/lib/"*.o "$SRC106/usr/lib/"

# 4. Packaging
echo "[4/4] Finalizing and Packaging..."
sed -i 's/Mac OS X 10.6/Mac OS X 10.6 Hybrid (RetroMatch)/g' "$SRC106/SDKSettings.plist"

cd "$WORK_DIR/phreak106"
tar -cJf "$BASE_DIR/super_temp.tar.xz" "MacOSX10.6.sdk"
cd "$BASE_DIR"

mv "super_temp.tar.xz" "$OUTPUT_PATH"

echo "--- SUCCESS ---"
echo "Perfect Hybrid SDK created at: $OUTPUT_PATH"
