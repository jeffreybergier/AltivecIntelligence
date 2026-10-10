#!/bin/bash
# Seal bundle resources using modern slices, then restore the untouched legacy
# slices. Refresh hashes for nested files after universal assembly, then seal
# those final resources in the modern main executable only.
set -euo pipefail
bundle="$1" pem="${2:-}" lipo="$3"
shift 3
work=$(mktemp -d "${bundle}.signing.XXXXXX")
trap 'rm -rf "$work"' EXIT
executables=()
# Legacy-only development bundles have no slice that rcodesign can seal.
main=$(python3 -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1],"rb"))["CFBundleExecutable"])' "$bundle/Contents/Info.plist")
if ! "$lipo" -info "$bundle/Contents/MacOS/$main" | grep -Eq 'x86_64|arm64'; then exit 0; fi
while IFS= read -r -d '' binary; do
  info=$("$lipo" -info "$binary" 2>/dev/null) || continue
  if echo "$info" | grep -Eq 'ppc|i386'; then
    index=${#executables[@]}
    executables+=("$binary")
    mkdir "$work/$index"
    modern=()
    for arch in ppc i386 x86_64 arm64; do
      if echo "$info" | grep -qw "$arch"; then
        "$lipo" "$binary" -thin "$arch" -output "$work/$index/$arch"
        case "$arch" in x86_64|arm64) modern+=("$work/$index/$arch");; esac
      fi
    done
    if [ ${#modern[@]} -eq 0 ]; then
      echo "Cannot seal mixed bundle containing legacy-only executable: $binary" >&2; exit 1
    fi
    if [ ${#modern[@]} -eq 1 ]; then cp "${modern[0]}" "$binary"
    else "$lipo" -create "${modern[@]}" -output "$binary"; fi
  fi
done < <(find "$bundle/Contents/MacOS" "$bundle/Contents/Library" "$bundle/Contents/Frameworks" "$@" -type f -print0 2>/dev/null || true)
args=(--timestamp-url none)
if [ -n "$pem" ] && [ -f "$pem" ]; then args+=(--pem-file "$pem"); fi
rcodesign -C /dev/null sign "${args[@]}" "$bundle" > "$work/signing.log" 2>&1 || {
  cat "$work/signing.log" >&2; exit 1;
}
for ((index=0;index<${#executables[@]};index++)); do
  binary="${executables[$index]}"
  legacy=()
  for arch in ppc i386; do [ ! -f "$work/$index/$arch" ] || legacy+=("$work/$index/$arch"); done
  "$lipo" -create "${legacy[@]}" "$binary" -output "$work/$index.fat"
  cp "$work/$index.fat" "$binary"
done

if [ ${#executables[@]} -gt 0 ]; then
  # Embedded executables can be plain resources in rcodesign's envelope.
  # Hash their final universal bytes after restoring the legacy slices.
  python3 - "$bundle" "${executables[@]}" <<'PYCODE'
import hashlib
import plistlib
from pathlib import Path
import sys
contents = Path(sys.argv[1]) / 'Contents'
restored = {str(Path(p).relative_to(contents)) for p in sys.argv[2:]}
path = contents / '_CodeSignature/CodeResources'
resources = plistlib.loads(path.read_bytes())
for entries in (resources.get('files', {}), resources.get('files2', {})):
    for name, value in entries.items():
        if name not in restored:
            continue
        data = (contents / name).read_bytes()
        if isinstance(value, bytes):
            entries[name] = hashlib.sha1(data).digest()
        elif isinstance(value, dict):
            if 'hash' in value: value['hash'] = hashlib.sha1(data).digest()
            if 'hash2' in value: value['hash2'] = hashlib.sha256(data).digest()
path.write_bytes(plistlib.dumps(resources))
PYCODE
  identifier=$(python3 -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1],"rb"))["CFBundleIdentifier"])' "$bundle/Contents/Info.plist")
  for ((index=0;index<${#executables[@]};index++)); do
    binary="${executables[$index]}"
    case "$binary" in "$bundle"/Contents/MacOS/*) ;; *) continue ;; esac
    modern=(); legacy=()
    for arch in x86_64 arm64; do
      if [ -f "$work/$index/$arch" ]; then
        "$lipo" "$binary" -thin "$arch" -output "$work/$index/$arch"
        modern+=("$work/$index/$arch")
      fi
    done
    for arch in ppc i386; do [ ! -f "$work/$index/$arch" ] || legacy+=("$work/$index/$arch"); done
    if [ ${#modern[@]} -eq 1 ]; then cp "${modern[0]}" "$work/main.modern"
    else "$lipo" -create "${modern[@]}" -output "$work/main.modern"; fi
    rcodesign -C /dev/null sign "${args[@]}" --binary-identifier "$identifier" \
      --info-plist-file "$bundle/Contents/Info.plist" \
      --code-resources-file "$bundle/Contents/_CodeSignature/CodeResources" \
      "$work/main.modern" > "$work/main-signing.log" 2>&1 || {
      cat "$work/main-signing.log" >&2; exit 1;
    }
    "$lipo" -create "${legacy[@]}" "$work/main.modern" -output "$work/main.fat"
    cp "$work/main.fat" "$binary"
  done
fi
