#!/bin/sh
# Builds the closed-lid helper, embeds it in the app bundle and signs app and helper ad hoc with distinct
# identities. The installer pins each CDHash, so the two must differ. Local development signing only.
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
codesign --force --sign - --identifier com.camlid.power-helper "$DEST/camlid-power-helper"
codesign --force --sign - --identifier com.camlid.CamLid "$APP"
