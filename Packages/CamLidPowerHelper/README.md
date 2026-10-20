# CamLid competitor-style power helper candidate

Original implementation of the persistent SleepDisabled + authenticated recovery-helper architecture documented by LidRun and Amphetamine Power Protect. No competitor code copied. No Apple contact needed or proposed.

**Not wired into CamLid, qualified or shippable.** A frozen v3 QA helper was subsequently installed under exact owner approval; its short closed-work and client-failure tests succeeded, but an owner-performed Apple-menu Sleep test was blocked. Therefore the pmset candidate fails the retained manual-Sleep criterion and must not be promoted into the main app. Chronological evidence/permissions: [QA report](../../docs/qa/power-helper-candidate-2026-10-16.md).

Current source also contains an unselected lid-specific IOKit primitive reusing `LidNativeAdapter`, with process-owned timed idle assertion and distinct shared clamshell control, no global pmset mutation. It is deliberately not adapted to a Boolean global-setting getter or claimed restoration guarantee. Mechanism-specific journal/lease integration and separately approved native testing remain necessary; compilation does not change the already-installed frozen v3 helper. No executable currently selects the new primitive. Tests inject fake boundaries. Existing main app remains Preview; do not install/update/activate native code without exact approval.

## Implemented path

- Root launchd daemon over a fixed named XPC service. No arbitrary commands, paths, pmset keys, shell, sudo or sudoers changes.
- Kernel-enforced XPC signing requirements at listener and connection. Production: exact app identifier plus the helper's validated Team ID and Apple certificate anchor. Local development without a developer certificate: distinct exact app/helper CDHash pins must first be installed by root at the fixed protected identity path. No UID-only/unsigned/debug-entitled bypass, no caller-provided requirements. Both local executables must have valid hardened-runtime signatures; client authenticates the helper in reverse and checks root EUID. Missing local trust refuses before storage/power setup.
- One lease bound to its authenticated connection and UID; random token, increasing renewal sequence, 30-second heartbeat deadline, non-extendable session cap (at most 4 hours), disconnection cleanup.
- Durable journal **before** enable/restore; existing tested `LidRecoveryJournal` storage reused, not a second persistence framework. Root-owned 0700 directory and lifetime single-instance lock.
- Native fixed `/usr/bin/pmset -g` readback and `-a disablesleep 1/0` writes. Explicit command completion/exit, output limits, no shell interpolation. Two-second subprocess wait; timeout poisons runner and prevents a racing reset. This bounds application waiting, not accepted OS work or process teardown.
- Initial candidate is deliberately **AC-only**, battery at least 20%, nominal thermal state, current console user, known lid, no online external display. Admission requires lid open; monitoring permits lid closed. Native helper collects its own readings; clients cannot supply sensor evidence. Battery-enabled sessions are not supported by this candidate yet.
- Acknowledged same-boot enable may be restored after helper restart. Uncertain enable, interrupted restoration or another boot's still-enabled setting refuses blind reset. Readback already off can be acknowledged without a write.
- `qualifiedClosedLidProtection` remains false in replies. No GUI/CLI success badge or readiness gate is upgraded by compilation/tests.

## Retained limits, not guarantees

`SleepDisabled` is global/persistent and may block manual/low-battery/thermal software Sleep while set. Healthy helper safety policy reduces exposure but does not replace OS safeguards. A helper/watchdog cannot supply OS-owned expiry, atomic ownership, cancellation of accepted OS writes, bounded kernel calls, or recovery while all local executors are hung/dead. Same-value foreign writers are indistinguishable; journal/compare/readback do not solve that. No independent power-resource ownership is claimed. Existing LidRun/other keep-awake resources must not be changed during QA.

The existing stronger product requirement remains unmet. This implementation makes the competitor-style path concrete without silently turning it into the stronger guarantee. Manual Sleep preservation, app/helper crash/hang, AC transitions, thermal/battery exits, continuity and restoration still need separately reviewed real-host qualification. Internal panel reduced-power proof remains deferred; it is not a substitute for workload progress.

## Build/test (no host power actions)

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --package-path Packages/CamLidPowerHelper \
  --scratch-path .pi/qa-builds/power-helper-2026-10-16 --jobs 2 --no-parallel
```

Use `--configuration release` for Release. Executable `--version` is inert. No-argument execution as non-root refuses before opening storage or creating bindings. Do not run no-argument execution as root, `launchctl`, service registration or pmset writes as part of software tests.

`Support/com.camlid.power-helper.plist` is an uninstalled **production SMAppService reference only**: current SDK requires apps containing LaunchDaemons to be notarized. It is not the deployment path for an ad-hoc local QA app. `Support/com.camlid.power-helper.local.plist` instead names a fixed root-installed legacy daemon executable at `/Library/PrivilegedHelperTools/com.camlid.power-helper`, with fixed label/Mach service and argv. Root installation/bootstrap still requires separate exact approval; no notarization bypass or OS security change is attempted.

`Support/stage-local-candidate.py` prepares a new, ad-hoc hardened-runtime signed QA app inside repository `.pi/qa-builds`, derives distinct role pins after signing and writes an external `identity.json`, local-daemon plist and manifest. Signing is offline (`--timestamp=none`); deep verification includes the nested helper. It never installs, registers or executes the bundle. Its `--self-test` performs no signing/power calls. Local trust later requires root-owned, non-writable ancestor directories and root-owned 0644 `/Library/Application Support/CamLidPowerHelper/identity.json`; each endpoint verifies its own pin before accepting the opposite role. Pins stay outside the signed app to avoid circular mutual-CDHash dependencies. Updates need an explicit new root pin installation, never a silent trust relaxation.

The staged QA bundle has its own `com.camlid.PowerCandidate` identity and must be addressed by exact path. Only root-installed exact pins admit that QA identity; the production Team-ID policy still accepts only the real CamLid app. Staging never registers it with Launch Services or replaces the running/installed CamLid. Root identity/helper/plist installation, daemon bootstrap consent and exact action approval are still required before native QA. The QA client has no `--register` command; `--registration-status` only reads legacy service status. Do not use the superseded first SMAppService-oriented staged bundle. Use only the latest frozen manifest. There is no installer or registration side effect in the package build.

## Lid-specific modes and the frozen best-effort candidate

The daemon accepts exactly three argv forms: none (`pmset-global-v1`), `--lid-specific-v1`
(24 s cap) and `--lid-specific-best-effort-v1` (900 s cap, 24 s leases, 10 s heartbeats).
Only the best-effort form constructs `RootDomainGeneralInterestObserver`, so a qualified
`kIOMessageSystemWillSleep` terminates the current session and latches no-resume through
wake. That mapping is passive general-interest subscription only: this daemon never
registers for system power, never calls `IOAllowPowerChange`/`IOCancelPowerChange` and never
vetoes OS intent. Synthetic or unobserved sleep events are not qualified evidence.

`camlid-power-qa` exposes two fixed bounded runs, `--acquire-24s` and
`--acquire-best-effort-900s`, described by one `BoundedRunPlan` type. Each acquires exactly
once, renews on a 10 s timer, issues exactly one release and never re-arms or resumes. The
hard client deadline is a backstop only; it cannot extend the helper's session cap. Both
commands are inert until a separate approved root install of a frozen packet exists, and
`--self-test` touches no service, journal, assertion or selector.

The frozen v8 best-effort bundle, its manifest/CDHashes, the exact upgrade packet and the
attended recorder are recorded in
[docs/qa/best-effort-frozen-candidate-2026-10-19.md](../../docs/qa/best-effort-frozen-candidate-2026-10-19.md).
One attended closed-lid episode ran on 2026-10-19 (boot `7180E052-…`) after the separately
approved root install; outcome and limits:
[docs/qa/closed-lid-best-effort-episode-2026-10-19.md](../../docs/qa/closed-lid-best-effort-episode-2026-10-19.md).
The current staging is the v9 freeze (same helper/service sources; QA client run-loop fix;
helper payload `3d268478…`): the upgrade packet, the instrumented closed-lid recorder, the
new manual-Sleep recorder, and a host observation that the v8 episode's acknowledged cleanup
left clamshell sleep disabled until reboot are recorded in
[docs/qa/best-effort-v9-increment-2026-10-19.md](../../docs/qa/best-effort-v9-increment-2026-10-19.md).
The first manual-Sleep episode on the v9 lab ran on 2026-10-19 (boot `CC935B3A-…`) and
closed honestly as `MANUAL_SLEEP_NOT_ESTABLISHED` — the machine's own wifi/BT maintenance
wake surfaced it from a ≈0.79 s suspend; the helper path (`willSleep` →
`restore(sleepObserved)` → acknowledged cleanup), the owned-assertion journal attribution
and the real-run client run-loop confirmation are recorded in
[docs/qa/manual-sleep-v9-adjudication-2026-10-19.md](../../docs/qa/manual-sleep-v9-adjudication-2026-10-19.md).
A same-day retry chain (two fresh boots; operator radios off before the cue) reached the
first full-gate manual-Sleep observation — a 16.577 s suspended interval with zero darkwakes,
`cleanupAcknowledged`/`sleepObserved`, owned assertion released — recorded in
[docs/qa/manual-sleep-v9-retry-adjudication-2026-10-19.md](../../docs/qa/manual-sleep-v9-retry-adjudication-2026-10-19.md).
The optional instrumented closed-lid episode (increment §6 step 4) then ran on a further
fresh boot (`A3994FA4-…`) under separate one-use approvals and reached
`CLOSED_INTERVAL_CANDIDATE_OBSERVED`: 114 lid samples (max cadence 176.9 ms), a conservative
8.42 s observed-closed interval with `AppleClamshellCausesSleep = false` in all 58 closed
rows, 29 independent workload samples inside (7.118 s), zero sleep/wake/dark-wake lines in
the 24-line `pmset` window, the owned assertion present at the cue and in every closed
snapshot and absent after cleanup, client exit 5, final `cleanupAcknowledged`/`userStop`.
The acknowledged cleanup left the shared bit `No`, so lid-close sleep must be re-established
by a reboot before normal use; the post-reboot baseline must be re-read. Record:
[docs/qa/closed-lid-best-effort-episode-v9-2026-10-19.md](../../docs/qa/closed-lid-best-effort-episode-v9-2026-10-19.md).
Nothing in this paragraph qualifies closed-lid protection, manual Sleep or restoration.
