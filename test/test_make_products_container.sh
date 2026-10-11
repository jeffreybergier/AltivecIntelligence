#!/bin/bash
# Run inside a network-disabled Altivec container with the SDK volumes mounted.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
if [ -r /proc/net/route ] && awk 'NR > 1 && $2 == "00000000" { found=1 } END { exit !found }' /proc/net/route; then
  echo 'Run these offline tests with docker run --network none.' >&2
  exit 1
fi
python3 "$root/test/test_make_products.py"
for shape in simple daemon products; do
  for platform in mac phone; do
    make -C "$root/test/fixtures/$shape" clean PLATFORM="$platform"
    make -C "$root/test/fixtures/$shape" -j4 debug release PLATFORM="$platform"
    make -C "$root/test/fixtures/$shape" validate-package PLATFORM="$platform" CONFIG=debug
    make -C "$root/test/fixtures/$shape" validate-package PLATFORM="$platform" CONFIG=release
  done
done
make -C "$root/test/fixtures/products" clean BUILD_ROOT=build-legacy
make -C "$root/test/fixtures/products" release ARCHS='ppc i386' BUILD_ROOT=build-legacy
make -C "$root/test/fixtures/products" clean BUILD_ROOT="$root/build-single-slice"
make -C "$root/test/fixtures/products" release ARCHS=arm64 BUILD_ROOT="$root/build-single-slice"
make -C "$root/test/fixtures/simple" clean BUILD_ROOT=build-signed-subset
make -C "$root/test/fixtures/simple" release ARCHS='ppc arm64' BUILD_ROOT=build-signed-subset Fixture_MAC_SIGN=1
mac_sign=(ARCHS='ppc arm64' BUILD_ROOT=build-signed-subset Fixture_MAC_SIGN=1 helper_MAC_SIGN=1
          Fixture_ENTITLEMENTS=AppEntitlements.plist helper_ENTITLEMENTS=HelperEntitlements.plist
          helper_EMBED_PATH=Contents/Helpers/helper)
make -C "$root/test/fixtures/daemon" clean "${mac_sign[@]}"
make -C "$root/test/fixtures/daemon" release "${mac_sign[@]}"
make -C "$root/test/fixtures/daemon" validate-package "${mac_sign[@]}"
policy=(PLATFORM=phone BUILD_ROOT=build-rootless Fixture_PACKAGES=deb-rootless
        Fixture_PACKAGE_ARCH=all Fixture_PACKAGE_ID=org.altivec.fixture Fixture_VERSION=1.0
        Fixture_SANDBOX=container Fixture_ENTITLEMENTS=Entitlements.plist)
make -C "$root/test/fixtures/simple" clean "${policy[@]}"
make -C "$root/test/fixtures/simple" release "${policy[@]}"
make -C "$root/test/fixtures/simple" validate-package "${policy[@]}"
echo 'PASS: offline product contracts, real matrices, architecture subsets, signing and rootless container policy'
