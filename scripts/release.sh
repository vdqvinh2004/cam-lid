#!/bin/sh
# Builds a GitHub release of CamLid: a Release build, ad-hoc signed (there is no Apple Developer ID), verified, zipped,
# with the SHA-256 of the zip and the code hashes (CDHash) of the app and its helper.
# Usage: scripts/release.sh [version]     version defaults to MARKETING_VERSION in project.yml
# Output: dist/CamLid-<version>-macos-arm64.zip, its .sha256, and dist/RELEASE_NOTES-<version>.md
# Uploading is a separate, deliberate step (the GitHub Releases page, or `gh release create`).
set -eu
cd "$(dirname "$0")/.."
VERSION="${1:-$(sed -n 's/^ *MARKETING_VERSION: *//p' project.yml | head -1)}"
case "$VERSION" in [0-9]*.[0-9]*) ;; *) echo "bad version: $VERSION" >&2; exit 2 ;; esac
if [ -n "$(git status --porcelain)" ] && [ "${ALLOW_DIRTY:-0}" != 1 ]; then
  echo "The working tree has uncommitted changes; a release must come from a commit (ALLOW_DIRTY=1 to override)." >&2
  exit 1
fi
COMMIT="$(git rev-parse --short HEAD)"
NAME="CamLid-$VERSION-macos-arm64"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
mkdir -p dist

echo "== Building $VERSION ($COMMIT)"
xcodebuild -project CamLid.xcodeproj -scheme CamLid -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$BUILD" CODE_SIGNING_ALLOWED=NO ARCHS=arm64 MARKETING_VERSION="$VERSION" build >"$BUILD/build.log" 2>&1 \
  || { tail -30 "$BUILD/build.log" >&2; exit 1; }
APP="$BUILD/Build/Products/Release/CamLid.app"
HELPER="$APP/Contents/Library/LaunchServices/camlid-power-helper"

echo "== Verifying the bundle"
fail() { echo "FAILED: $1" >&2; exit 1; }
verify() {
  codesign --verify --deep --strict "$1" 2>/dev/null || fail "deep signature check of $1"
  info="$(codesign -dvvv "$1" 2>&1)"
  echo "$info" | grep -q 'flags=.*adhoc' || fail "app is not ad-hoc signed"
  echo "$info" | grep -q 'flags=.*runtime' || fail "hardened runtime is off (the helper rejects the app without it)"
  [ -z "$(codesign -d --entitlements - "$1" 2>/dev/null | grep -i 'key' || true)" ] || fail "the app carries entitlements"
  [ ! -d "$1/Contents/Frameworks" ] || fail "unexpected nested frameworks"
  [ -x "$1/Contents/Library/LaunchServices/camlid-power-helper" ] || fail "helper missing"
  [ -x "$1/Contents/Helpers/camlid" ] || fail "command-line tool missing"
  [ "$(lipo -archs "$1/Contents/Helpers/camlid")" = "arm64" ] || fail "command-line tool is not arm64 only"
  codesign -dvvv "$1/Contents/Helpers/camlid" 2>&1 | grep -q 'Identifier=com.camlid.cli' || fail "command-line tool identifier"
  [ "$(lipo -archs "$1/Contents/MacOS/CamLid")" = "arm64" ] || fail "not arm64 only"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist")" = "$VERSION" ] || fail "bundle version"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$1/Contents/Info.plist")" = "14.0" ] || fail "minimum macOS"
}
verify "$APP"
APP_CDHASH="$(codesign -dvvv "$APP" 2>&1 | sed -n 's/^CDHash=//p')"
HELPER_CDHASH="$(codesign -dvvv "$HELPER" 2>&1 | sed -n 's/^CDHash=//p')"
[ -n "$APP_CDHASH" ] && [ -n "$HELPER_CDHASH" ] && [ "$APP_CDHASH" != "$HELPER_CDHASH" ] || fail "code hashes"

echo "== Zipping"
rm -f "dist/$NAME.zip" "dist/$NAME.zip.sha256"
ditto -c -k --keepParent "$APP" "dist/$NAME.zip"
( cd dist && shasum -a 256 "$NAME.zip" > "$NAME.zip.sha256" )
mkdir "$BUILD/unzipped"
ditto -x -k "dist/$NAME.zip" "$BUILD/unzipped"
verify "$BUILD/unzipped/CamLid.app"   # the signature must survive the archive
[ "$(codesign -dvvv "$BUILD/unzipped/CamLid.app" 2>&1 | sed -n 's/^CDHash=//p')" = "$APP_CDHASH" ] || fail "app changed in the archive"
SHA="$(cut -d' ' -f1 "dist/$NAME.zip.sha256")"

cat > "dist/RELEASE_NOTES-$VERSION.md" <<NOTES
## CamLid $VERSION

Keeps a Mac awake with the lid closed while AI coding agents work, and lets it sleep when they are done.

**Pre-release.** Tested on one Mac (Mac17,3, macOS 26A434, Apple silicon). On any other model or macOS build, closed
lid stays off until you accept "untested configuration" in Settings › Closed Lid. Strict mode is limited to tested
Macs. See the README for what this does to your Mac.

### Install
1. Download \`$NAME.zip\`, unzip it and move **CamLid.app** to \`/Applications\`.
2. **macOS will refuse the first launch** because the app is not notarized by Apple (this project has no Apple
   Developer account). Open it once, then go to *System Settings › Privacy & Security*, scroll down and choose
   **Open Anyway** for CamLid. Or, in Terminal: \`xattr -dr com.apple.quarantine /Applications/CamLid.app\`
3. Open CamLid, then *Settings › Closed Lid › Install helper…* (asks for your administrator password once).

### Verify before you run it (it installs a root helper)
\`\`\`sh
shasum -a 256 $NAME.zip      # must print: $SHA
codesign -dvvv /Applications/CamLid.app 2>&1 | grep CDHash    # app:    $APP_CDHASH
codesign -dvvv /Applications/CamLid.app/Contents/Library/LaunchServices/camlid-power-helper 2>&1 | grep CDHash   # helper: $HELPER_CDHASH
\`\`\`
The helper only obeys the exact app (and helper) code hashes it was installed with, so a changed app is refused.
You can always build it yourself instead: see the README.

### Remove
*Settings › Closed Lid › Remove helper…* restores the sleep setting and removes the helper, then delete the app.

### Command line (optional)
The \`camlid\` tool is inside the app. Put it on your PATH with
\`sudo ln -s /Applications/CamLid.app/Contents/Helpers/camlid /usr/local/bin/camlid\`. It needs the quarantine flag
cleared (the \`xattr\` command above) to run from Terminal. \`camlid status\`, \`start\`, \`stop\`, \`config\` talk to
the running app; \`sudo camlid helper install|uninstall|status\` manage the helper.

Built from commit \`$COMMIT\`. Requires macOS 14 or later, Apple silicon.
NOTES

echo
echo "Built dist/$NAME.zip"
echo "SHA-256   $SHA"
echo "App CDHash    $APP_CDHASH"
echo "Helper CDHash $HELPER_CDHASH"
echo "Notes     dist/RELEASE_NOTES-$VERSION.md"
