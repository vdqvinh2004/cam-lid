# Attended install trial (no sleep change)

Purpose: prove on the real Mac that the helper installs, accepts the app's pinned identity, answers a read-only
query and uninstalls cleanly, **without starting a session or changing the sleep setting**. Run by the owner; each
step needs an administrator password where marked. This is not G2 and passes no gate.

Use the app from one fixed path for the whole trial; the helper pins that build's CDHash. Rebuilding changes it
(then run `helper trust`).

```sh
# 0. Build (no password)
xcodebuild -project CamLid.xcodeproj -scheme CamLid -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/camlid-xcode-trial CODE_SIGNING_ALLOWED=NO build
APP=/tmp/camlid-xcode-trial/Build/Products/Debug/CamLid.app
CLI=/tmp/camlid-xcode-trial/Build/Products/Debug/camlid

# 1. Baseline (no password). On a Mac with earlier CamLid QA material, expect status "partial" with
#    missing helper/daemonPlist/recoveryPlist: an old /Library/Application Support/CamLidPowerHelper/identity.json
#    is present. It is never overwritten without --replace-pins (step 3). Otherwise expect notInstalled.
#    SleepDisabled should be 0 or absent; launchctl prints an error.
$CLI helper status --app "$APP"
pmset -g | grep -i SleepDisabled
launchctl print system/com.camlid.power-helper 2>&1 | head -2

# 2. Read-only unreachable check (no password). Expect: "helper-inspect: unreachable", exit 1.
"$APP/Contents/MacOS/CamLid" --helper-inspect; echo "exit=$?"

# 3. Install (password). Expect: "accepted":true,"reason":"installed". Without --replace-pins and with an old
#    identity.json present, expect "foreignPinsPresent" and no change. With it, the old file is kept as
#    identity.json.previous and the other files in that directory (QA scope evidence) are not touched.
sudo $CLI helper install --app "$APP" --replace-pins
$CLI helper status --app "$APP"          # expect installed
launchctl print system/com.camlid.power-helper | grep -E 'state|program|arguments' | head
launchctl print system/com.camlid.power-recovery | grep -E 'state|program|arguments' | head
ls -l /Library/PrivilegedHelperTools/com.camlid.power-helper /Library/LaunchDaemons/com.camlid.power-*.plist
sudo cat "/Library/Application Support/CamLidPowerHelper/identity.json"

# 4. Read-only XPC round trip. Expect: "helper-inspect: accepted=true state=ready reason=noPendingIntent", exit 0.
"$APP/Contents/MacOS/CamLid" --helper-inspect; echo "exit=$?"
pmset -g | grep -i SleepDisabled          # must be unchanged from step 1

# 5. Identity check. Run from a copy (different CDHash is not possible by copying; re-sign it):
cp -R "$APP" /tmp/CamLid-other.app && codesign --force --sign - --options runtime /tmp/CamLid-other.app
/tmp/CamLid-other.app/Contents/MacOS/CamLid --helper-inspect; echo "exit=$?"   # expect unreachable / exit 1

# 6. Recovery job (no password). The journal is empty, so it must do nothing.
sudo /Library/PrivilegedHelperTools/com.camlid.power-helper --recover-v1   # expect "recovery: nothingToRecover"

# 7. Uninstall (password). Expect: "uninstalled"; the old identity.json restored if step 3 moved it; the support
#    directory kept if it holds other files; SleepDisabled unchanged. Status then matches step 1.
sudo $CLI helper uninstall
$CLI helper status --app "$APP"
ls /Library/PrivilegedHelperTools /Library/LaunchDaemons | grep -i camlid     # expect nothing
ls -l "/Library/Application Support/CamLidPowerHelper/"
pmset -g | grep -i SleepDisabled
rm -rf /tmp/CamLid-other.app
```

Report back for each step: the exact output, and whether `SleepDisabled` ever changed. Stop and run
`sudo $CLI helper uninstall --force` if any step differs from the expectation. Do not start Auto, Timed or Manual
during the trial: a shipped build has no qualified support row, so it would not reach the helper anyway.

If step 4 prints `unreachable` while the helper is installed, check `launchctl print system/com.camlid.power-helper`
(is it running?) and the app's signature flags (`codesign -dvvv "$APP"` must show `runtime`).
