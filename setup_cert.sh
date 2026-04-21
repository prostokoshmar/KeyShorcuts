#!/usr/bin/env bash
# Creates a local self-signed code-signing certificate.
# Run this ONCE.  After that, every build will be signed with the same identity,
# so macOS will NOT revoke Accessibility / Input Monitoring between builds.

set -euo pipefail
CERT_NAME="KeyShortcuts Local"

if security find-certificate -c "$CERT_NAME" ~/Library/Keychains/login.keychain-db &>/dev/null; then
    echo "✅ Certificate '$CERT_NAME' already exists — nothing to do."
    exit 0
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Generate a 4-year RSA key + self-signed cert marked for code signing.
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 1461 -nodes \
    -subj "/CN=$CERT_NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false"

# Bundle into PKCS#12 so 'security import' can ingest both key and cert.
openssl pkcs12 -export -out "$TMP/cert.p12" \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -passout pass:ks_local_tmp \
    -legacy

# Import into the login keychain, allow codesign to use it without a passphrase.
security import "$TMP/cert.p12" \
    -k ~/Library/Keychains/login.keychain-db \
    -P ks_local_tmp \
    -T /usr/bin/codesign \
    -A

# Remove the macOS password UI prompt when codesign accesses the key.
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -k "" \
    ~/Library/Keychains/login.keychain-db 2>/dev/null || true

echo ""
echo "✅ Certificate '$CERT_NAME' created and imported."
echo "   All future builds will use it — Accessibility / Input Monitoring"
echo "   permissions will now survive updates without re-prompting."
