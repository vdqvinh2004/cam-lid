#!/bin/sh
# Builds the closed-lid helper, embeds it in the app bundle and signs app and helper ad hoc with distinct
# identities. Hardened runtime is required: the helper identity check rejects a signature without it. The installer pins each CDHash, so the two must differ. Local development signing only.
set -eu
APP="${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME}"
SCRATCH="${DERIVED_FILE_DIR}/helper-build"
CONFIG=release
[ "${CONFIGURATION:-Debug}" = "Debug" ] && CONFIG=debug
env -u SDKROOT -u MACOSX_DEPLOYMENT_TARGET swift build -c "$CONFIG" --package-path "${SRCROOT}/Packages/CamLidPowerHelper" \
  --product camlid-power-helper --scratch-path "$SCRATCH"
DEST="${APP}/Contents/Library/LaunchServices"
mkdir -p "$DEST"
cp "$SCRATCH/$CONFIG/camlid-power-helper" "$DEST/camlid-power-helper"
codesign --force --sign - --options runtime --identifier com.camlid.power-helper "$DEST/camlid-power-helper"
# Only a Debug build needs the library-validation exception (Xcode's debug dylib carries another ad-hoc signature);
# a Release app has no nested code, so it is signed with no entitlements at all.
if [ "${CONFIGURATION:-Debug}" = "Debug" ]; then
  codesign --force --sign - --options runtime --entitlements "${SRCROOT}/Config/CamLid.dev-signing.entitlements" \
    --identifier com.camlid.CamLid "$APP"
else
  codesign --force --sign - --options runtime --identifier com.camlid.CamLid "$APP"
fi
