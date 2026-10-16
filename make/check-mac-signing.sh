#!/bin/bash
# Validate identity material without printing the private key or certificate.
set -euo pipefail
pem="${1:-}"
policy="${2:-required}"
if [ -z "$pem" ]; then
  if [ "$policy" = optional ]; then exit 0; fi
  echo 'Mac release signing requires ALTIVEC_SIGNING_PEM (persistent certificate and private key).' >&2
  exit 1
fi
if [ ! -s "$pem" ] || [ ! -r "$pem" ]; then
  echo 'ALTIVEC_SIGNING_PEM must name a readable, nonempty PEM file.' >&2
  exit 1
fi
# Empty passphrase prevents an encrypted key from prompting unattended builds.
cert_public=$(openssl x509 -in "$pem" -pubkey -noout 2>/dev/null) || {
  echo 'Signing PEM must contain an X.509 certificate.' >&2; exit 1;
}
key_public=$(openssl pkey -in "$pem" -passin pass: -pubout 2>/dev/null) || {
  echo 'Signing PEM must contain an unencrypted private key.' >&2; exit 1;
}
if [ "$cert_public" != "$key_public" ]; then
  echo 'Signing certificate and private key do not match.' >&2
  exit 1
fi
