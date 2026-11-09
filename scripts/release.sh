#!/bin/sh
# Builds a GitHub release of CamLid: a Release build signed with CAMLID_SIGN_IDENTITY (the project's release
# certificate; there is no Apple Developer ID), verified, zipped, with the SHA-256 of the zip and the code hashes
# (CDHash) of the app, its helper and its command-line tool.
# Usage: scripts/release.sh [--adhoc] [version]     version defaults to MARKETING_VERSION in project.yml
# Output: dist/CamLid-<version>-macos-arm64.zip, its .sha256, and dist/RELEASE_NOTES-<version>.md
# Without CAMLID_SIGN_IDENTITY the build is refused. --adhoc makes a local test build instead: it is named -ADHOC
# and its notes say not to publish it.
# Uploading is a separate, deliberate step (the GitHub Releases page, or `gh release create`).
set -eu
cd "$(dirname "$0")/.."
ADHOC=0
VERSION=""
for arg in "$@"; do
  case "$arg" in
    --adhoc) ADHOC=1 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) VERSION="$arg" ;;
  esac
done
[ -n "$VERSION" ] || VERSION="$(sed -n 's/^ *MARKETING_VERSION: *//p' project.yml | head -1)"
case "$VERSION" in [0-9]*.[0-9]*) ;; *) echo "bad version: $VERSION" >&2; exit 2 ;; esac
# A published version is never rebuilt: its zip and checksum would change under the same tag and name.
if [ "$ADHOC" != 1 ] && git rev-parse -q --verify "refs/tags/v$VERSION" > /dev/null; then
  echo "Refusing: tag v$VERSION already exists. Choose a new version; published releases are not rebuilt." >&2
  exit 1
fi
if [ -n "${CAMLID_SIGN_IDENTITY:-}" ] && [ "$ADHOC" = 1 ]; then
  echo "--adhoc conflicts with CAMLID_SIGN_IDENTITY; unset one of them." >&2
  exit 2
fi
if [ -z "${CAMLID_SIGN_IDENTITY:-}" ] && [ "$ADHOC" != 1 ]; then
  echo "Refusing an ad-hoc release. Set CAMLID_SIGN_IDENTITY to the release certificate (see scripts/make-signing-identity.sh)." >&2
  echo "For a local test build that must not be published, pass --adhoc." >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ] && [ "${ALLOW_DIRTY:-0}" != 1 ]; then
  echo "The working tree has uncommitted changes; a release must come from a commit (ALLOW_DIRTY=1 to override)." >&2
  exit 1
fi
sh scripts/check-helper-version.sh || { echo "Refusing the release: the helper version guard failed (see above)." >&2; exit 1; }
COMMIT="$(git rev-parse --short HEAD)"
if [ -n "$(git status --porcelain)" ]; then COMMIT="$COMMIT, with uncommitted changes"; fi
SUFFIX=""
if [ "$ADHOC" = 1 ]; then SUFFIX="-ADHOC"; fi
NAME="CamLid-$VERSION-macos-arm64$SUFFIX"
BUILD="$(mktemp -d)"
# Building registers the product with LaunchServices. Drop that record with its folder, or a later launch by bundle
# id can pick a copy that no longer exists.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
trap '"$LSREGISTER" -u "$BUILD/Build/Products/Release/CamLid.app" >/dev/null 2>&1 || true; rm -rf "$BUILD"' EXIT
mkdir -p dist

echo "== Building $VERSION ($COMMIT)"
# Release binaries must not carry this checkout's path (#filePath, debug info): the flags map it to "." (no spaces in the path).
xcodebuild -project CamLid.xcodeproj -scheme CamLid -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$BUILD" CODE_SIGNING_ALLOWED=NO ARCHS=arm64 MARKETING_VERSION="$VERSION" \
  OTHER_SWIFT_FLAGS="\$(inherited) -file-prefix-map $PWD=. -debug-prefix-map $PWD=." build >"$BUILD/build.log" 2>&1 \
  || { tail -30 "$BUILD/build.log" >&2; exit 1; }
APP="$BUILD/Build/Products/Release/CamLid.app"
HELPER="$APP/Contents/Library/LaunchServices/camlid-power-helper"

echo "== Verifying the bundle"
fail() { echo "FAILED: $1" >&2; exit 1; }
# SHA-1 of the leaf certificate: what the helper pins, taken from the designated requirement.
leaf() { codesign -d -r- "$1" 2>&1 | sed -n 's/.*certificate leaf = H"\([0-9a-f]*\)".*/\1/p' | head -1; }
verify() {
  codesign --verify --deep --strict "$1" 2>/dev/null || fail "deep signature check of $1"
  info="$(codesign -dvvv "$1" 2>&1)"
  if [ -n "${CAMLID_SIGN_IDENTITY:-}" ]; then
    echo "$info" | grep -q 'flags=.*adhoc' && fail "signed ad hoc although CAMLID_SIGN_IDENTITY is set"
    [ -n "$(leaf "$1")" ] || fail "no signing certificate found on $1"
    [ "$(leaf "$1")" = "$(leaf "$1/Contents/Library/LaunchServices/camlid-power-helper")" ] || fail "app and helper use different certificates"
    [ "$(leaf "$1")" = "$(leaf "$1/Contents/Helpers/camlid")" ] || fail "app and command-line tool use different certificates"
  else
    echo "$info" | grep -q 'flags=.*adhoc' || fail "app is not ad-hoc signed"
  fi
  echo "$info" | grep -q 'flags=.*runtime' || fail "hardened runtime is off (the helper rejects the app without it)"
  [ -z "$(codesign -d --entitlements - "$1" 2>/dev/null | grep -i 'key' || true)" ] || fail "the app carries entitlements"
  [ ! -d "$1/Contents/Frameworks" ] || fail "unexpected nested frameworks"
  [ -x "$1/Contents/Library/LaunchServices/camlid-power-helper" ] || fail "helper missing"
  [ -x "$1/Contents/Helpers/camlid" ] || fail "command-line tool missing"
  cmp -s "$1/Contents/Resources/SKILL.md" .agents/skills/camlid/SKILL.md || fail "bundled agent skill differs from .agents/skills/camlid/SKILL.md"
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
CLI_CDHASH="$(codesign -dvvv "$APP/Contents/Helpers/camlid" 2>&1 | sed -n 's/^CDHash=//p')"
[ -n "$CLI_CDHASH" ] || fail "command-line tool code hash"
HELPER_VERSION="$(sed -n 's/^    public static let current = \([0-9][0-9]*\)$/\1/p' Packages/CamLidPowerWire/Sources/CamLidPowerWire/LocalIdentityPins.swift | head -1)"
[ -n "$HELPER_VERSION" ] || fail "helper version not found"

echo "== Zipping"
rm -f "dist/$NAME.zip" "dist/$NAME.zip.sha256"
ditto -c -k --keepParent "$APP" "dist/$NAME.zip"
( cd dist && shasum -a 256 "$NAME.zip" > "$NAME.zip.sha256" )
mkdir "$BUILD/unzipped"
ditto -x -k "dist/$NAME.zip" "$BUILD/unzipped"
verify "$BUILD/unzipped/CamLid.app"   # the signature must survive the archive
[ "$(codesign -dvvv "$BUILD/unzipped/CamLid.app" 2>&1 | sed -n 's/^CDHash=//p')" = "$APP_CDHASH" ] || fail "app changed in the archive"
SHA="$(cut -d' ' -f1 "dist/$NAME.zip.sha256")"

if [ -n "${CAMLID_SIGN_IDENTITY:-}" ]; then
  LEAF="$(leaf "$APP")"
  CERT="$LEAF"
  PIN_TEXT="The helper only obeys an app signed with this release certificate (SHA-1 $LEAF) under the identifier com.camlid.CamLid, so a changed or unsigned app is refused. Updating the app does not need the helper reinstalled unless the notes say the helper changed."
else
  CERT="none (ad-hoc build)"
  PIN_TEXT="The helper only obeys the exact app (and helper) code hashes it was installed with, so a changed app is refused and every rebuild needs Reinstall helper…."
fi

BANNER=""
if [ "$ADHOC" = 1 ]; then BANNER="**Local test build: ad-hoc signed. Do not publish it.**

"; fi
cat > "dist/RELEASE_NOTES-$VERSION$SUFFIX.md" <<NOTES
## CamLid $VERSION

${BANNER}Keeps a Mac awake with the lid closed while AI coding agents work, and lets it sleep when they are done.

### What is in this release
- **Auto and Timed.** Auto keeps the Mac awake while the agents you selected are working, then waits for "Sleep when
  done". Timed keeps it awake for a chosen time.
- **Lid open (new in 0.1.0).** A session keeps the Mac awake with the lid open through a verified power assertion, without the
  helper. If you keep the closed-lid option off, this hold is new to you.
- **Closed lid.** Needs the helper (Settings › Closed Lid). It works on tested Macs; on any other, first choose
  "Allow on this untested Mac" there.
- **\`camlid run -- <command>\` (new in 0.1.0).** Keeps the Mac awake while the command runs and returns its exit status. It needs
  CamLid to be running; otherwise it exits with code 4 and runs nothing.
- **Shortcut ⌃⌥⌘K (new in 0.1.0).** Starts or stops Auto from any app. It needs no Accessibility permission.
- **Dashboard.** Says "Keeping awake (lid open)" when the Mac is held awake with the lid open and closed-lid protection
  is not verified.
- **Sleep diagnostics.** CamLid's own power assertion is labelled "CamLid is active" and is not counted as another app.
- **Agents.** Claude Code, Codex and OpenCode in a terminal are estimated from CPU activity. Orca is read from its CLI.
- **Update check (new in 0.2, off by default).** Settings › General can ask GitHub once a day whether a newer release exists. It never downloads or installs anything.
- **Agent skill (new in 0.2).** Settings › General › *Let AI agents use CamLid* writes one skill file into a project folder you choose. Turning it off removes that file unless you changed it.
- **Display option (new in 0.2).** Settings › General › New sessions: "Let the display sleep during sessions" is on by default. Turn it off to keep the display on while a session holds the Mac awake. It applies to the next session.
- **Copy diagnostics (new in 0.2).** The Sleep diagnostics window copies a plain-text report. It holds no prompts, transcripts, command output or environment values.
- **Chromium audio hold (new in 0.2).** Watched programs can keep an Auto session awake while Chrome, Brave, Edge, Vivaldi, Opera, Arc or Chromium plays audio, and for 60 seconds after it stops. Other apps are not detected.

### Known limits
- **Tested on one Mac:** Mac17,3, macOS build 26A434, Apple silicon. On any other Mac or macOS build, closed-lid operation
  stays off until you choose "Allow on this untested Mac" in Settings › Closed Lid.
- **Strict mode is experimental**, limited to tested Macs. The README says what it changes.
- **Not notarized by Apple.** The project has no Apple Developer account, so the first launch needs the steps below.
- Apple silicon only, macOS 14 or later.
- The lid-open hold and \`camlid run\` were checked on one Mac only.
- Agent activity for terminal agents is an estimate: a model thinking silently for a long time can look idle.
- The Chromium audio hold was checked on Brave only. The other browsers in its list are not yet checked on a live Mac.

### Build and signing
| Item | Value |
| --- | --- |
| Signing certificate (SHA-1) | $CERT |
| Helper version | $HELPER_VERSION |
| App CDHash | \`$APP_CDHASH\` |
| Helper CDHash | \`$HELPER_CDHASH\` |
| Command-line tool CDHash | \`$CLI_CDHASH\` |
| Zip SHA-256 | \`$SHA\` |

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
$PIN_TEXT
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
echo "Notes     dist/RELEASE_NOTES-$VERSION$SUFFIX.md"
