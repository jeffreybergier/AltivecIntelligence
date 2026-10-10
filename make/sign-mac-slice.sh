#!/bin/bash
# Sign only the modern thin Mach-O inputs. Legacy slices remain untouched.
set -euo pipefail
binary="$1" identifier="$2" plist="$3" pem="${4:-}" arch="$5"
args=(--binary-identifier "$identifier" --info-plist-file "$plist" --timestamp-url none)
if [ -n "$pem" ] && [ -f "$pem" ]; then
  args+=(--pem-file "$pem")
else
  echo "Signing $identifier ($arch) ad-hoc; configure RCLOUD_SIGNING_PEM for a stable identity" >&2
fi
if [ "$arch" = x86_64 ]; then args+=(--digest sha1 --digest sha256); fi
rcodesign -C /dev/null sign "${args[@]}" "$binary" > "$binary.signing.log" 2>&1 || {
  cat "$binary.signing.log" >&2; exit 1;
}
