#!/bin/sh
# Creates the stable code-signing identity that releases are signed with (no Apple Developer account involved).
# Why: with ad-hoc signing every build has a new CDHash, so the helper must be reinstalled after every app update.
# Signed with one certificate, the helper pins the certificate instead; an app update then needs no reinstall unless
# the helper itself changed (PowerHelperVersion).
#
# Usage: scripts/make-signing-identity.sh ["Certificate Name"]
#   CAMLID_KEYCHAIN      keychain to import into (default: the login keychain)
#   CAMLID_SIGNING_OUT   where the backup is written (default: ~/CamLid-signing)
#   CAMLID_SKIP_TRUST=1  skip the trust step (tests only; codesign then refuses the identity)
#
# It asks macOS once to trust the certificate for code signing (a password or Touch ID prompt). Trust is needed only on
# the machine that signs; a Mac that runs the app needs nothing. Then build releases with:
#   CAMLID_SIGN_IDENTITY="CamLid Release Signing" scripts/release.sh
#
# Keep the backup (the .p12 and its password) somewhere safe, apart from the repo. Anyone holding the key can sign an
# app the helper trusts, and losing it means every user reinstalls the helper once when you switch to a new one.
set -eu
NAME="${1:-CamLid Release Signing}"
KEYCHAIN="${CAMLID_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
OUT="${CAMLID_SIGNING_OUT:-$HOME/CamLid-signing}"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "A certificate named \"$NAME\" already exists in $KEYCHAIN; nothing created." >&2
  security find-certificate -c "$NAME" -Z "$KEYCHAIN" | sed -n 's/^SHA-1 hash: //p'
  exit 0
fi
[ ! -e "$OUT" ] || { echo "$OUT already exists; move it away first." >&2; exit 1; }
mkdir -m 700 "$OUT"
cd "$OUT"

cat > cert.cnf <<EOF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF
openssl req -x509 -newkey rsa:3072 -nodes -keyout key.pem -out cert.pem -days 7300 -config cert.cnf >/dev/null 2>&1
PASS="$(openssl rand -base64 24)"
# macOS `security import` cannot read the newer PKCS#12 defaults, so the legacy algorithms are named explicitly.
openssl pkcs12 -export -inkey key.pem -in cert.pem -out "$NAME.p12" -passout "pass:$PASS" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1
umask 077
printf '%s\n' "$PASS" > password.txt
security import "$NAME.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
if [ "${CAMLID_SKIP_TRUST:-0}" != 1 ]; then
  echo "macOS will ask you to allow this certificate for code signing."
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" cert.pem
fi
SHA1="$(openssl x509 -in cert.pem -noout -fingerprint -sha1 | sed 's/.*=//; s/://g' | tr 'A-F' 'a-f')"
rm -f key.pem cert.cnf
echo "Created \"$NAME\" (SHA-1 $SHA1) in $KEYCHAIN."
echo "Backup: $OUT/$NAME.p12 and $OUT/password.txt. Move both somewhere safe, outside the repo."
echo "Build a release with: CAMLID_SIGN_IDENTITY=\"$NAME\" scripts/release.sh"
