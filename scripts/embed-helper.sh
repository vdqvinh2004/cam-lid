#!/bin/sh
# Builds the closed-lid helper and the camlid command-line tool, embeds both in the app bundle and signs app, helper and tool with distinct
# identifiers. Hardened runtime is required: the helper identity check rejects a signature without it.
# Signing is ad hoc by default, and then the installer pins each exact CDHash, so any rebuild needs a new install.
# With CAMLID_SIGN_IDENTITY set (a keychain identity name or SHA-1, see scripts/make-signing-identity.sh) all three
# are signed with that one certificate, the installer pins the certificate, and an app update keeps working until
# the helper itself changes (PowerHelperVersion).
set -eu
SIGN="${CAMLID_SIGN_IDENTITY:--}"
# CAMLID_SIGN_KEYCHAIN names a keychain outside the search list (a CI keychain); by default the search list is used.
sign() {
  if [ -n "${CAMLID_SIGN_KEYCHAIN:-}" ]; then codesign --force --sign "$SIGN" --keychain "$CAMLID_SIGN_KEYCHAIN" "$@"
  else codesign --force --sign "$SIGN" "$@"; fi
}
APP="${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME}"
SCRATCH="${DERIVED_FILE_DIR}/helper-build"
CONFIG=release
[ "${CONFIGURATION:-Debug}" = "Debug" ] && CONFIG=debug
env -u SDKROOT -u MACOSX_DEPLOYMENT_TARGET swift build -c "$CONFIG" --package-path "${SRCROOT}/Packages/CamLidPowerHelper" \
  --product camlid-power-helper --scratch-path "$SCRATCH"
CLI_SCRATCH="${DERIVED_FILE_DIR}/cli-build"
env -u SDKROOT -u MACOSX_DEPLOYMENT_TARGET swift build -c "$CONFIG" --package-path "${SRCROOT}/Packages/CamLidCore" \
  --product camlid --scratch-path "$CLI_SCRATCH"
DEST="${APP}/Contents/Library/LaunchServices"
mkdir -p "$DEST"
cp "$SCRATCH/$CONFIG/camlid-power-helper" "$DEST/camlid-power-helper"
sign --options runtime --identifier com.camlid.power-helper "$DEST/camlid-power-helper"
# The command-line tool ships inside the app, sealed by the app's signature. Not in Contents/MacOS: the filesystem is
# case-insensitive, so `camlid` there would overwrite the app's own `CamLid` executable.
mkdir -p "${APP}/Contents/Helpers"
cp "$CLI_SCRATCH/$CONFIG/camlid" "${APP}/Contents/Helpers/camlid"
sign --options runtime --identifier com.camlid.cli "${APP}/Contents/Helpers/camlid"
# Only a Debug build needs the library-validation exception (Xcode's debug dylib carries another ad-hoc signature);
# a Release app has no nested code, so it is signed with no entitlements at all.
if [ "${CONFIGURATION:-Debug}" = "Debug" ]; then
  sign --options runtime --entitlements "${SRCROOT}/Config/CamLid.dev-signing.entitlements" \
    --identifier com.camlid.CamLid "$APP"
else
  sign --options runtime --identifier com.camlid.CamLid "$APP"
fi
