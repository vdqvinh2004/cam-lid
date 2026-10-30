# Attended install trial (no sleep change)

Purpose: prove on the real Mac that the helper installs, accepts the app's pinned identity, answers a read-only
query and uninstalls cleanly, **without starting a session or changing the sleep setting**. Run by the owner; each
step needs an administrator password where marked. This is not G2 and passes no gate.

Use the app from one fixed path for the whole trial; the helper pins that build's CDHash. Rebuilding changes it
(then run `helper trust`).

## Known state of the owner's Mac (found 2026-10-31)
An earlier **Strict** helper is still loaded in launchd under the same label: `launchctl print system/com.camlid.power-helper`
shows `state = running`, `--lid-specific-best-effort-v1`, although its plist and binary are gone. Standard mode shares
that label, so the installer refuses with `labelInUse` and never boots it out. `SleepDisabled` was 0. Decide before
step 3: leave it (no install possible) or remove it yourself with
`sudo launchctl bootout system/com.camlid.power-helper`. Its journal under `/private/var/db/CamLidPowerHelper*` and
the scope evidence under `/Library/Application Support/CamLidPowerHelper/` are not touched by either path.

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

# 2b. Optional (password): remove the leftover Strict service named above, then re-check:
#     sudo launchctl bootout system/com.camlid.power-helper ; launchctl print system/com.camlid.power-helper
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

# 5. Identity check. A copy re-signed ad hoc with the same identifier and entitlements has the SAME CDHash, so
#    it is the same pinned identity and is accepted: the pin follows the code, not the path. To see the helper
#    refuse a different peer, run the probe (an unpinned client) right after a positive control:
swiftc scripts/helper-peer-probe.swift -o /tmp/helper-peer-probe
"$APP/Contents/MacOS/CamLid" --helper-inspect; echo "control exit=$?"      # expect accepted=true, exit 0
/tmp/helper-peer-probe; echo "probe exit=$?"                               # expect "refused", exit 0; "ANSWERED" (exit 1) is a failure

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

## Result of the first run (2026-10-31)
Steps 2b, 3, 4, 6 and 7 were run by the owner; step 5 ran with the first, flawed design. Install returned `installed`, status `installed` with
`serviceLoaded:true`, `--helper-inspect` returned `accepted=true state=ready reason=noPendingIntent` (exit 0),
`SleepDisabled` stayed 0, uninstall returned `uninstalled`, the earlier `identity.json` and the scope directories were
intact and no `identity.json.previous` remained. Paste commands without trailing `#` comments: interactive zsh passes
them as arguments.

Second run (2026-10-31): both daemons loaded (`com.camlid.power-helper` running, `com.camlid.power-recovery` with `runs = 2`,
`last exit code = 0`); `--recover-v1` as root returned `recovery: nothingToRecover` (exit 0) with `SleepDisabled` 0; uninstall
again restored the earlier files. The re-signed copy was **accepted** (same CDHash, same identity), which corrected the
step 5 design above; the helper-side refusal of a different peer is checked with `scripts/helper-peer-probe.swift`.

Third run (2026-10-31): with the helper installed, the control (`--helper-inspect`) returned `accepted=true state=ready`
and the unpinned probe returned `refused: connection interrupted` (exit 0). With no helper installed the same probe
reports `connection invalidated`, so the two outcomes differ. Install and uninstall again left the earlier files intact.
