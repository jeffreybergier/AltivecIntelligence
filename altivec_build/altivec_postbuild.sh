#!/usr/bin/env bash

# AltivecIntelligence SDK Installer
# This script installs all available SDKs in the tarballs directory
# that were not already installed by the main build.sh script.

pushd "${0%/*}" &>/dev/null

DESC="altivec-sdk-installer"
source tools/tools.sh

# Ensure build directory exists
mkdir -p $BUILD_DIR
pushd $BUILD_DIR &>/dev/null

function install_sdk()
{
  local sdk_tarball=$1
  local sdk_filename=$(basename $sdk_tarball)
  
  # Heuristic to guess the SDK name from the filename
  local guessed_name=$(echo $sdk_filename | $SED 's/\.tar\..*//')
  
  # Check if it looks already installed in TARGET_DIR/SDK
  if [ -d "$SDK_DIR/$guessed_name" ]; then
    echo "SDK $guessed_name is already installed, skipping."
    return 0
  fi

  echo "Installing additional SDK: $sdk_filename"
  
  # Extract into build dir
  extract $sdk_tarball 1 1
  
  local target_sdk_dir=""
  local extracted_name=""

  if [ -d "SDKs" ]; then
    extracted_name=$(ls SDKs/ | head -n1)
    target_sdk_dir="$SDK_DIR/$extracted_name"
    rm -rf $target_sdk_dir 2>/dev/null
    mv -f SDKs/$extracted_name $SDK_DIR
    rm -rf SDKs
  else
    extracted_name=$(ls -d *.sdk 2>/dev/null | head -n1)
    if [ -z "$extracted_name" ]; then
        extracted_name=$(ls -F | grep "/" | head -n1 | sed 's/\///')
    fi
    
    if [[ $sdk_filename == iPhoneOS* ]] && [[ $extracted_name == "iPhoneOS.sdk" ]]; then
        local version=$(echo $sdk_filename | $SED 's/[^0-9.]//g' | $SED 's/\.*$//')
        if [ -n "$version" ]; then
            mv -f iPhoneOS.sdk iPhoneOS$version.sdk
            extracted_name="iPhoneOS$version.sdk"
        fi
    fi

    target_sdk_dir="$SDK_DIR/$extracted_name"
    
    if [ -d "$target_sdk_dir" ]; then
        echo "SDK $extracted_name already exists in $SDK_DIR, skipping move."
    else
        mv -f $extracted_name $SDK_DIR
    fi
  fi

  if [ -d "$target_sdk_dir" ] && [[ $extracted_name == MacOSX* ]]; then
    echo "Applying quirks to $extracted_name..."
    pushd $target_sdk_dir &>/dev/null
    set +e
    ln -s \
      $target_sdk_dir/System/Library/Frameworks/Kernel.framework/Versions/A/Headers/std*.h \
      usr/include 2>/dev/null
    [ ! -f "usr/include/float.h" ] && cp -f $BASE_DIR/oclang/quirks/float.h usr/include
    [ $PLATFORM == "FreeBSD" ] && cp -f $BASE_DIR/oclang/quirks/tgmath.h usr/include
    set -e
    popd &>/dev/null
  fi
  
  echo "Successfully installed $extracted_name"
}

# 1. Install all SDKs
SDK_TARBALLS=$(find -L $TARBALL_DIR -type f -name "*.sdk.tar.*")
if [ -n "$SDK_TARBALLS" ]; then
    for SDK_PATH in $SDK_TARBALLS; do
        install_sdk $SDK_PATH
    done
fi

# 2. Finalize toolchain symlinks (Fixes for standalone and iPhone builds)
echo "Finalizing toolchain symlinks in $TARGET_DIR/bin..."
pushd $TARGET_DIR/bin &>/dev/null

# Detect the base prefix (usually darwin8 for Tiger, or darwin10 for Snow Leopard)
BASE_PREFIX=$(ls x86_64-apple-darwin*-ld 2>/dev/null | head -n1 | sed 's/-ld//')
if [ -z "$BASE_PREFIX" ]; then
    BASE_PREFIX="x86_64-apple-darwin8" # Fallback
fi

echo "  > Using base prefix: $BASE_PREFIX"

# Ensure ld and lipo exist without prefixes (required by Clang)
ln -sf ${BASE_PREFIX}-ld ld
ln -sf ${BASE_PREFIX}-lipo lipo

# Link the system dsymutil-14 for modern targets (x86_64)
ln -sf /usr/bin/dsymutil-14 llvm-dsymutil
ln -sf /usr/bin/dsymutil-14 osxcross-llvm-dsymutil

# Link the system lld for Apple Silicon targets (arm64)
ln -sf /usr/bin/ld64.lld-14 ld64.lld

# Ensure arm and x86_64 (darwin15) wrappers are correctly linked to the universal wrapper
# We use powerpc64-* wrapper as the universal base if available
WRAPPER=$(ls powerpc64-apple-darwin*-wrapper 2>/dev/null | head -n1)
if [ -z "$WRAPPER" ]; then
    WRAPPER=$(ls x86_64-apple-darwin*-wrapper 2>/dev/null | head -n1)
fi

if [ -f "$WRAPPER" ]; then
    echo "  > Linking wrappers to $WRAPPER"
    for arch in arm64 armv7 armv7s; do
        ln -sf $WRAPPER ${arch}-apple-darwin11-clang
        ln -sf $WRAPPER ${arch}-apple-darwin11-clang++
    done
fi

popd &>/dev/null

popd &>/dev/null
echo "Altivec SDK installation and toolchain finalization complete."
