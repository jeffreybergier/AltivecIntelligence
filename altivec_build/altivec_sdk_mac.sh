#!/usr/bin/env bash
# altivec_sdk_mac.sh - Recreates functional 10.6 SDK using Phracker sources

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

echo "--- CREATING HYBRID SDK ---"
mkdir -p "$WORK_DIR/donor_libs"

# 1. SURGICAL EXTRACTION of 10.5 (Donor for legacy stubs)
echo "[1/4] Extracting legacy stubs from 10.5..."
tar -xJf "$INPUT_DIR/phreak105.tar.xz" --wildcards -C "$WORK_DIR/donor_libs" \
    "MacOSX10.5.sdk/usr/lib/*.o" \
    "MacOSX10.5.sdk/usr/lib/libgcc_s.10.4.dylib" \
    "MacOSX10.5.sdk/usr/lib/libgcc_s.10.5.dylib" \
    "MacOSX10.5.sdk/usr/lib/libgcc_s.1.dylib"

# 2. Extract 10.6 (Base - Brain and primary Muscle)
echo "[2/4] Extracting 10.6 header/library base..."
mkdir -p "$WORK_DIR/base"
tar -xJf "$INPUT_DIR/phreak106.tar.xz" -C "$WORK_DIR/base"

SRC106="$WORK_DIR/base/MacOSX10.6.sdk"
SRC105="$WORK_DIR/donor_libs/MacOSX10.5.sdk"

# 3. SELECTIVE INJECTION
echo "[3/4] Grafting legacy components into 10.6 base..."
cp -n "$SRC105/usr/lib/"*.o "$SRC106/usr/lib/"
cp -n "$SRC105/usr/lib/libgcc_s"* "$SRC106/usr/lib/"

# Create versioned linker stubs for the Apple Linker
for f in "$SRC105/usr/lib/"*.o; do
    if [ -f "$f" ]; then
        filename=$(basename "$f")
        cp "$f" "$SRC106/usr/lib/${filename%.o}.10.5.o"
    fi
done

# 4. Packaging
echo "[4/4] Finalizing and Packaging..."
# Ensure linker compatibility by linking /lib -> /usr/lib
ln -sf usr/lib "$SRC106/lib"
sed -i 's/Mac OS X 10.6/Mac OS X 10.6 Hybrid/g' "$SRC106/SDKSettings.plist"

cd "$WORK_DIR/base"
tar -cJf "$BASE_DIR/super_temp.tar.xz" "MacOSX10.6.sdk"
cd "$BASE_DIR"

mv "super_temp.tar.xz" "$OUTPUT_PATH"

echo "--- SUCCESS ---"
echo "Hybrid SDK created at: $OUTPUT_PATH"
