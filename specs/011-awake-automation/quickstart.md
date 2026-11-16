# M8 Validation Guide

**Partial implementation**: `diagnose`, Preview `sleep --dry-run`/sleep refusal, protected-run denial, `watch` editing and Preview lifetime matching are executable. Actual sleep refusals record blockers; dry-run writes nothing. Verified protection remains deferred. Alerts/login adapters are wired; isolated native failure delivery and grant/readback/revoke are verified, while complete native alert and signed lifecycle acceptance remain open. See current evidence; do not run physical tests as a documentation check.

## Prerequisites and document inspection

From repository root:

```sh
rtk env SPECIFY_FEATURE_DIRECTORY=specs/011-awake-automation .specify/scripts/bash/check-prerequisites.sh --json --require-spec --require-tasks --include-tasks
```

Before live tests require accepted M1 support row, accepted M2 ownership/recovery, supervised ventilated desk test, current rollback/Stop capability and verified restoration baseline. Hardware tests never deliberately overheat/deplete battery. No foreign blockers/settings changed.

## Automated checks after implementation

```sh
rtk env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --no-parallel --package-path Packages/CamLidCore
rtk env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CamLid.xcodeproj -scheme CamLid -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Run targeted new Core/CLI/App suites first; full suites once integrated. Use existing simulator fixture conventions for stale observations, safety, clock/wake, admission expiry, PID reuse, error and replay cases. Simulator never changes host power. See [contract](contracts/awake-automation.md) for exact command schema and bounds.

## US1: Read-only MVP

After implementing shared diagnostics, run `rtk camlid diagnose --json` while app is open. Inspect matching GUI window with Refresh/Cmd-R. Seed a harmless system-idle hold and a separate display hold only in an isolated supervised QA session, clean both afterwards. Expect distinct effects/owners, explicit global/kernel coverage, redacted default report and <=5-second partial/failure result under stalled collection. Test oversize256-owner/64KiB inputs with fixtures, not thousands of host processes. Saved Timed/no actual session => activeSessionMode null.

## US2: Display behavior

On a qualified lid-open row: start session, allow display sleep, observe system work still progressing with panel off. Disable display sleep, observe panel awake; edit during active session without resetting timer. Close lid only on qualified row and independently verify panel off. Stop, safety, quit and crash recovery release owned resources; foreign assertions unaffected. Repeat finite/Infinite/Auto policy without inventing an Infinite session cap.

## US3: Protected command

In explicitly armed Auto on a qualified backend, run `rtk camlid run --keep-awake -- /usr/bin/true`, then an isolated bounded QA command. Expect admission before launch, direct-child exit behavior and hold release. With app absent/Preview/Timed/safety denied, fixture child marker must never appear. Simulate stale receipt, wrong UID/boot/generation, 21st admission, app loss, failed spawn and delayed finish. Stop revokes hold without killing child or re-arming. Verify IO/exit/signals through existing wrapper integration harness; no output persisted.

## US4: Lifetime rules

Select a known user executable in Settings or `watch add`, explicitly arm Auto, start/exit it. Expect “app running” lifetime reason, never “AI working/completed” from presence alone. Rules do nothing while stopped/Timed. Fixtures exercise overlapping rules, PID reuse, symlink/path changes, 21st rule, invalid selectors, truncated process list and two fresh absences. Unknown/disappearance must not cause completion sleep. Agent Settings still shows CLI detection only; persistent editing never arms a mode.

## US5: Guarded sleep

Run dry-run only on normal desktop. Expect blocked if open lid/display awake or fresh interaction; all reasons visible and no host mutation. Use fixtures for unknown/stale input/display/work/restoration. Preview actual sleep must refuse. Perform eligible actual request only after qualifying support row and clearing/restoring owned holds; report requested before suspension, then independently observe sleep and verify observed history after wake. No force command or retries waiting for user inactivity.

## US6: Alerts

Isolated QA preferences: enable alerts explicitly, approve/deny native prompt, test each category, duplicate transitions and >5 ordinary events within10m. A new critical safety/restoration reason must still alert once, replay must not. Fresh normalized runs start at sequence 0; starting at sequence 1 buffers the event and cannot prove delivery. Inspect Preview and requested/observed wording, no private payloads, permission revoke and no startup prompt/replayed history. Return to an already-open Settings window after external grant/revoke and confirm actual permission/login state refreshes without another prompt or session. Restore test preferences and OS permission.

## US7: Login

Use signed isolated QA app identity for register/unregister and OS approval cases. Verify actual Settings state after external revoke, user login and update/uninstall. Login opens app without active session; no automatic arming. Never change the installed user's login preference for QA without their authorization.

## Native and release acceptance

Inspect Dashboard, options/context menu, all Settings tabs, Activity and Diagnostics at small/large sizes and light/dark. Keyboard-only focus, native labels, whole-row disclosure, hover help, empty/loading/error states and active icon must work. No duplicate mode controls or irrelevant status in Agent Settings. Full VoiceOver acceptance remains excluded by existing user revision.

Record build/OS/hardware/case IDs/expected/actual/artifacts. Mark simulated vs native vs physical separately. M5 upgrade/uninstall and M6 security/recovery/privacy regression required; zero unresolved critical/high defects before M7 users. No support matrix row passes from a CLI acknowledgement alone.

Native banner/consent checks still require observing the real main QA app separately. Keep a bounded observation immediately after emission; a later empty screenshot does not prove a transient banner was shown.

## Isolated app cleanup

Use an existing, uniquely identified QA root and bundle. Embed `CamLidQAStateDirectory` in the QA copy's Info.plist: its command-line tool reads its folder only from there, and without it the tool reaches no folder. `--qa-state-directory` at launch sets the app's folder alone. The root must already exist. Never change the installed app's identity/preferences to make QA easier.

Quit through that app's isolated control socket, then confirm its exact parent/helper PIDs have exited and its bundle ID is absent from `NSWorkspace.runningApplications`. A CLI quit acknowledgement precedes termination. A filtered whole-process listing or empty layer-0 window list is insufficient: accessory apps and layer-25 popovers can be omitted. Keep the complete bundle and resources present until every owned process exits; removing a live bundle can trap `Bundle.module` resource loading. Only then unregister/remove the task-owned app and temporary root. Leave installed Preview running and keep native permission/appearance settings at their original values. Native input checks require an unlocked desktop; do not send input to the lock screen.
