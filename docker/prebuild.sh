#!/usr/bin/env bash

# AltivecIntelligence legacy-toolchain preparation.
#
# The PowerPC-capable ppc-test branch is intentionally isolated under the
# legacy prefix. Modern macOS and iOS builds are prepared separately by
# prebuild-modern.sh.

set -e

BASE_DIR=$(pwd)
TARBALLS_DIR="$BASE_DIR/tarballs"
TEMP_DIR="$BASE_DIR/temp_build_assets"
OSXCROSS_GIT="https://github.com/tpoechtrager/osxcross.git"
OSXCROSS_COMMIT="af8300c6b3e099c91970a8d2d0f3bffe703f2421"

curl_retry() {
    curl --fail --location --silent --show-error \
         --retry 5 --retry-delay 2 --retry-all-errors \
         --connect-timeout 30 "$@"
}

# Ensure cleanup on exit
trap 'echo "Cleaning up..."; rm -rf "$TEMP_DIR"' EXIT

# Prepare directories
mkdir -p "$TARBALLS_DIR"
mkdir -p "$TEMP_DIR/downloads"

# 1. Clone osxcross
echo "--- Initializing Toolchain Source ---"
echo "  > Fetching legacy osxcross ($OSXCROSS_COMMIT)"
git -C "$TEMP_DIR" init --quiet osxcross
git -C "$TEMP_DIR/osxcross" remote add origin "$OSXCROSS_GIT"
git -C "$TEMP_DIR/osxcross" fetch --quiet --depth 1 origin "$OSXCROSS_COMMIT"
git -C "$TEMP_DIR/osxcross" checkout --quiet --detach FETCH_HEAD
cp -a "$TEMP_DIR/osxcross"/. ./

# 2. BASE REPAIR
echo "--- Repairing Build Scripts ---"
# Ensure build directory exists (Fix for some environments)
# shellcheck disable=SC2016 # Match literal variables in the upstream script.
sed -i '/pushd $OSXCROSS_BUILD_DIR/i mkdir -p $OSXCROSS_BUILD_DIR' build_gcc.sh

# Update config.guess/sub to support modern host architectures during the
# Apple GCC build. Ubuntu's autotools-dev package supplies maintained copies,
# avoiding mutable downloads from GCC master.
cp /usr/share/misc/config.guess config.guess.new
cp /usr/share/misc/config.sub config.sub.new
# shellcheck disable=SC2016 # Insert literal variables into the upstream script.
sed -i '/extract "$OSXCROSS_TARBALL_DIR\/gcc-$APPLE_GCC_VERSION.tar.gz" 1/a \  find . -name "config.guess" -exec cp ../config.guess.new {} \\; \n  find . -name "config.sub" -exec cp ../config.sub.new {} \\;' build_gcc.sh

# 3. Apply Global OSXCross patches
echo "--- Applying Global Patches ---"
# osxcross-build.patch eliminated (native 10.5 support)
# osxcross-tools.patch eliminated (10.5 SDK has ppc64)

# 4. Prepare GCC scripts
# Create PPC copy from original first
cp build_gcc.sh build_gcc_ppc.sh

# Prepare Intel version (default build_gcc.sh)
patch build_gcc.sh --quiet < docker/patches/osxcross-build-gcc-intel.patch

# Prepare PPC version (build_gcc_ppc.sh)
patch build_gcc_ppc.sh --quiet < docker/patches/osxcross-build-gcc-ppc.patch

chmod +x build_gcc_ppc.sh build_gcc.sh

ln -sf /usr/bin/python3 /usr/local/bin/python

# 5. Download base SDKs
echo "--- Downloading SDKs ---"

echo "> Mac OS X 10.5  SDK"
curl_retry https://github.com/phracker/MacOSX-SDKs/releases/download/11.3/MacOSX10.5.sdk.tar.xz -o "$TARBALLS_DIR/MacOSX10.5.sdk.tar.xz"
echo "3970800422a5e22122b92e7ce2f30513714272e4cd9096e551b8bd27466e3c2b  $TARBALLS_DIR/MacOSX10.5.sdk.tar.xz" | sha256sum -c -

# Finalize
cp docker/postbuild.sh ./
echo "--- Pre-build preparation complete ---"
