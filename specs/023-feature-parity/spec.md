# Feature Specification: display option and copyable diagnostics

**Status:** Decided 2026-11-09: D1–D4 accepted as recommended. Implemented for v0.2 on 2026-11-09, not released, not
committed. Open: the live checks in [tasks.md](tasks.md) (T034 and the parts marked partly).
Comparison: [comparison.md](comparison.md).

## Context

The comparison with LidRun and LidWalk ([comparison.md](comparison.md)) found that CamLid already covers most of what they
offer. Two items are needed:

- **A display option.** `allowDisplaySleep` is stored and can be set from the CLI, and its default lets the display sleep.
  No assertion uses it and no app control shows it. The setting therefore does nothing, and the app does not say so.
- **Copyable diagnostics.** Someone reporting a sleep problem has no one-step way to share the state. The "Qualify my Mac"
  issue template asks for logs by hand.

One further item is an owner decision, not a build: the audio hold (spec 019, T070 and T071). Research found no signal that
tells playback apart in general. Only Chromium browsers name "Playing audio" in a power assertion.

## Goal

Make the stored display setting real, let a user copy a redacted diagnostics report, and leave the rest of the LidRun and
LidWalk list out until a user need appears.

## User stories

1. **Display (P1).** As a user, I can keep the display on during Auto and Timed sessions. The default stays as today: the
   display may sleep.
   - With the option off, a session holds a display-awake assertion owned by CamLid. It is released when the session ends,
     and when the app quits.
   - With the option on (default), no display assertion is created.
   - Closed-lid behaviour does not change.
2. **Copy diagnostics (P2).** As a user reporting a problem, I can copy a plain-text report from the Sleep diagnostics window.
   - The text has the same facts as `camlid diagnose --json`: app version, helper status, session state and mode,
     protection readiness, reason codes, and counts of recent transitions.
   - It contains none of the excluded items under Requirements.
3. **Audio (P3, only if D3 is "go").** As a user whose Chromium-based browser plays audio during an Auto session, the Mac
   stays awake until the audio stops.
   - The hold exists only while the browser's named "Playing audio" assertion exists.
   - It ends after a quiet period (proposed 60 seconds). It never holds without a named signal.
   - Activity records the start and the end only.

## Requirements

- **FR-001** `allowDisplaySleep` is the single source of truth, and its default stays `true`. The Settings control reads
  "Let the display sleep during sessions" and writes that same key, so the meaning is not inverted.
- **FR-002** A display hold uses the same owned-assertion pattern as the system hold: create, read back, release
  idempotently, and inject the system call so tests can use a fake.
- **FR-003** A change applies at the next session start (decision D2).
- **FR-004** Sleep diagnostics shows the display hold as CamLid's own assertion, not as another app. This follows the
  existing rule for CamLid's system assertion.
- **FR-005** Copy diagnostics writes plain text to the general pasteboard, and only when the user presses the button. It
  never runs at launch.
- **FR-006** The report never contains prompts, transcripts, command output, environment variables, agent task
  identifiers, helper secrets, or file paths outside the app's own folders. A test fails if any of these appears.
- **FR-007** Audio (only if D3 is "go"): the signal reader sits behind a protocol with a fake for tests. The rule kind
  appears next to watched programs, and the UI names it as a browser rule.

## Success criteria

- **SC-001** By default, no display assertion is created during any session. Test.
- **SC-002** With the option off, exactly one display assertion exists during an Auto or Timed session, and it is released
  when the session ends. Test.
- **SC-003** The copied report contains none of the excluded items. Test.
- **SC-004** If D3 is "go": the audio hold starts and ends only with the named signal. Test.

## Decisions

- **D1. Display default. Decided:** the display may sleep by default. Battery life is the reason.
- **D2. When the display option applies. Decided:** at the next session start.
- **D3. Audio. Decided:** go, for Chromium-based browsers only. This moves tasks T080–T083 from spec 019 (v0.3) into
  this spec as User Story 3. The go decision is recorded as T071 in spec 019.
- **D4. Release. Decided:** include this in v0.2.

## Out of scope

The excluded and deferred rows in [comparison.md](comparison.md): fan control, wake scheduling, phone and chat push,
webhooks, command output capture, charge limiting, updates installed in place, weekly reports, time windows and smart
rules, and App Intents. The Vietnamese interface stays in spec 019.

## Clean room

The behaviour is taken from observation and documentation only. No code, assets, identifiers, keys or credentials from
LidRun or LidWalk are used.

## Tasks

See [tasks.md](tasks.md).
