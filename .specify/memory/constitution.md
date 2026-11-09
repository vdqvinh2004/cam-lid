<!-- Sync Impact Report: 2.0.0 -> 3.0.0; owner reaffirmed third-person observation.
Principle II Activity Requires Evidence -> Third-Person Activity Evidence; principle V removes
provider-install obligation and prohibits producer coupling/config writes. Delivery Gates names
agent observation instead of integration. Added third-person scope revision; no section removed.
Major bump replaces incompatible older integration governance, not the existing passive app goal.
Templates read constitution at runtime and remain unchanged. Product/M3/M8 scope banners aligned;
legacy ingress and observer-source audit/removal deferred to M3 T017/T018. Historical evidence,
continuity-first and safety/power gates unchanged. No unresolved constitution placeholders. -->
# CamLid Constitution

## Core Principles

### I. Safety Overrides Keep-Awake
Battery limits, thermal limits, user Stop, and lease expiration MUST override every mode.
Power resources MUST release on normal exit and recover after crashes. Closed-lid support MUST
be advertised only for tested hardware/OS/power combinations. Protection reduces risk; it
MUST NOT promise safe operation in bags or guaranteed recovery of work.

### II. Third-Person Activity Evidence
CamLid MUST observe AI-agent work externally and remain outside agent execution workflows.
Product observation MUST NOT use hooks, MCP, provider bridges/stdin event ingestion, plugins,
agent-launch wrappers or agent configuration edits. Agent work MUST remain independent of CamLid.
Provider selection MUST affect only CamLid policy, not install a producer integration.
Process existence and low CPU MUST NOT prove task activity or completion. Observers MUST
distinguish observed working, waiting, idle and unknown; successful completion or unseen child
termination MUST NOT be invented. UI and CLI MUST expose confidence, freshness and coverage.
Unknown MUST NOT authorize completion sleep. Read-only source communication MUST be reviewed
against this boundary rather than assumed compliant because it performs no configuration write.

### III. Native, Minimal, Accessible
Use native macOS UI and platform services first. Dependencies and privileges MUST solve a
demonstrated requirement. Keyboard access, light/dark appearance, Reduce Motion,
and text equivalents for status colors MUST survive every release.

### IV. One Policy, Two Interfaces
GUI and CLI MUST share policy. Simulator MUST exercise safety, activity, deadlines, and
recovery without host power changes. Hardware tests MUST verify system continuity. Internal
display sleep MUST be verified separately when that behavior is claimed; display observation
MUST NOT substitute for task progress or imply verified display sleep when it is unknown.

### V. Private, Explainable Operation
Logs MUST contain transitions and reasons without prompts, code, secrets, or transcripts.
Export MUST redact identifiers by default; retention MUST be bounded. Agent settings and work
MUST remain untouched. CamLid preferences MAY select sleep relevance of externally observed
providers; they MUST NOT reintroduce producer event enrollment or integration installation.

## Platform Constraints
Prefer public APIs. Global or undocumented power mechanisms require a feasibility report,
bounded ownership, verified restoration, and an unsupported-state path. Administrative access,
if needed, belongs to a narrowly scoped authenticated helper, never arbitrary client commands.
Fan control and battery charging control are outside v1. CPU MUST NOT replace thermal monitoring.

## Delivery Gates
Planning ends before application source generation. Delivery order: feasibility, policy/safety,
external agent observation, native UX, packaging, AI quality gate, supervised real user tests. AI QA
MUST pass before user trials. Gates record evidence, failures, supported configurations, and
exit criteria. Simulation MUST be distinguished from physical observations.

## Governance
Constitution governs implementation reviews. Amendments include rationale, affected requirements,
and validation changes. Semantic versioning: major for incompatible principles, minor for new
principles, patch for clarification. Exceptions require documented decisions and review.

**Version**: 3.0.0 | **Ratified**: 2026-10-04 | **Last Amended**: 2026-10-13

## User scope revision — 2026-10-05

VoiceOver acceptance removed at the user’s explicit request. Keyboard access, meaningful labels, visible focus and non-color state equivalents remain required. Historical VoiceOver NOT RUN records remain historical, not failures or passes for this revised scope.

## Continuity-first scope revision — 2026-10-11

Owner prioritizes keeping the system awake so enrolled AI work continues with the physical lid
closed. Current-phase acceptance MUST establish independently recorded workload progress wholly
inside a confirmed closed-lid interval, with bounded timestamps and declared coverage gaps.
A surviving PID, open terminal, low CPU or governor heartbeat alone MUST NOT prove AI progress.

Independent internal-panel reduced-power qualification is DEFERRED for this phase, not passed.
An awake or unknown panel reading alone is not a failure of the continuity-only objective.
Recorded panel values MUST retain their actual value/Unknown; brightness reduction is optional,
not proof of display sleep or system continuity. No automatic brightness feature is required.
Any published capability MUST omit unverified screen-off/reduced-power promises.

Battery/AC/thermal safeguards, fresh typed safety evidence, known lid/topology, explicit Stop,
finite deadlines, authenticated ownership, manual Sleep and verified restoration remain required.
This revision does not authorize gate activation, native power/brightness actions, lid transitions,
helper installation or a hardware trial. Action-disabled source stays inert. Owner subsequently authorized scoped requirement,
admission and fake-test synchronization; revised monitoring accepts any observed panel state
with known lid and valid safety/topology while initial preflight stays open/awake. Actual
closed-lid continuity and restoration remain unverified until separately approved validation.

This is a priority/acceptance change, not a retroactive PASS for archived B/C, a selected backend
or shipping support. Earlier panel-first plans are historical where superseded by this section;
downstream requirements/protocols and admission tests MUST be synchronized before a new study.
Changed source still requires new matched-role identities/review and separately approved actions.

## Third-person observation reaffirmed — 2026-10-13

Owner corrected the recent Codex bridge direction: CamLid is an outside observer, not an agent
participant. Binding scope and migration limits
reaffirm README/passive-supervision requirements already present. Older producer integration,
installation and wrapper plans are superseded, not acceptance prerequisites. Archived bridge
experiments retain actual verdicts but MUST NOT qualify passive product detection.

Current legacy provider ingress and Orca source compliance still require audit; this governance
change does not claim routes removed or external working/idle signals qualified. Agent pipeline,
user configuration, provider/model jobs and native power MUST NOT be changed merely to finish old
gates. Release of owned holds, a guarded Sleep request and observed sleep remain separate; prior
battery/thermal/AC, interaction, Stop, cap, recovery and physical continuity gates remain binding.
