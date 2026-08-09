#!/usr/bin/env bash

# Legacy OSXCross postbuild hook. The ppc-test branch invokes this conventional
# filename after its own build. Modern SDKs and tools are installed separately
# by postbuild-modern.sh.

set -eo pipefail

pushd "${0%/*}" >/dev/null

export DESC="altivec-legacy-finalizer"
# shellcheck source=/dev/null
source tools/tools.sh
set -u

if [[ ! -d "$SDK_DIR/MacOSX10.5.sdk" ]]; then
  echo "error: legacy MacOSX10.5.sdk was not installed" >&2
  exit 1
fi

echo "Finalizing legacy toolchain symlinks in $TARGET_DIR/bin..."
base_ld="$(find "$TARGET_DIR/bin" -maxdepth 1 \
  -name 'x86_64-apple-darwin*-ld' -print -quit)"
if [[ -z "$base_ld" ]]; then
  echo "error: legacy x86_64 ld was not installed" >&2
  exit 1
fi

base_prefix="${base_ld##*/}"
base_prefix="${base_prefix%-ld}"
ln -sfn "${base_prefix}-ld" "$TARGET_DIR/bin/ld"
ln -sfn "${base_prefix}-lipo" "$TARGET_DIR/bin/lipo"

popd >/dev/null
echo "Legacy SDK installation and toolchain finalization complete."
