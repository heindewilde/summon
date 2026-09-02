#!/bin/bash
# Creates a self-signed code-signing identity for local development.
#
# Why: an ad-hoc signature identifies an app by a hash of its binary, so every
# rebuild looks like a different app to macOS and silently drops the Accessibility
# grant. Signing with a stable certificate means the grant is given once and kept.
#
# The certificate is local-only. It is not trusted by anyone else's Mac, it never
# leaves this one, and it can be deleted any time from Keychain Access by searching
# for the name below.
set -euo pipefail

NAME="${1:-Summon Local Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "==> '$NAME' already exists in the login keychain. Nothing to do."
    exit 0
fi

echo "==> Generating a code-signing certificate: $NAME"
cat > "$WORK/openssl.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[ dn ]
CN = $NAME

[ ext ]
basicConstraints       = critical,CA:false
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
subjectKeyIdentifier   = hash
CNF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -config "$WORK/openssl.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

echo "==> Importing into the login keychain"
# Key and certificate are imported separately. A PKCS#12 bundle from OpenSSL 3
# uses a MAC algorithm the macOS Security framework refuses to read.
# -A lets codesign use the key without prompting on every build.
security import "$WORK/key.pem" -k "$KEYCHAIN" -A -T /usr/bin/codesign
security import "$WORK/cert.pem" -k "$KEYCHAIN" -A -T /usr/bin/codesign

echo "==> Trusting it for code signing (macOS will ask for your password)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo "==> Done. Available identities:"
security find-identity -v -p codesigning
