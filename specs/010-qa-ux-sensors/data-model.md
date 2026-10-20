# Data model: preferences, evidence and capability

## PreferenceEdit (US2)

Field key, baseValue/baseRevision, candidate, latestPersistedValue/revision, editSequence; state clean/editing/invalid/pending/applied/conflict/failed. Only validated typed patches enter configuration. Persisted revision remains authoritative.

Transitions: clean → editing → invalid or pending → applied/failed/conflict. Rapid edits serialize/coalesce per field; older responses cannot overwrite a newer candidate. A failed write never advertises Applied. Invalid Custom text remains local. Successful writes update only their affected fields. External same-field change requires explicit Use current / Apply my value resolution against latest revision; unrelated conflicts retry once after reread, then explain failure. No unbounded retry loop.

Custom debounce 400 ms after last non-composing edit; Return/focus departure commits immediately if valid. Selection/toggle commits immediately. Pending indicator appears if write takes >150 ms. Normal writes settle within 1 s; blocked storage has no false success. Close flushes valid pending edits with 2 s bounded wait, then shows Retry / Keep window open / Discard unapplied edit. Invalid text may be explicitly discarded; prior applied changes stay applied. Quit uses same settlement. UpdateController treats editing/pending/invalid/conflict/failed as unsaved safety context until resolved; no installing path introduced.

## NumericChoice (US2)

Preset(value,label), Custom(rawText,lastAppliedValue). Defaults/ranges remain Configuration authority; no migration changes numerical values.

| Field | Range | Presets in order | Default | Custom behavior |
| --- | --- | --- | --- | --- |
| completionDelayMinutes | 0…30 integer min | Immediately (0), 1, 2, 5, 10, 15, 30 min | 2 | Last option Custom… |
| waitRetentionMinutes | 0…30 integer min | Do not retain (0), 1, 2, 5, 10, 15, 30 min | 5 | Last option Custom… |
| batteryFloorPercent | 10…50 integer % | 10, 15, 20, 25, 30, 40, 50% | 20 | Last option Custom… |
| runCapMinutes | 5…480 integer min | 15, 30 min, 1, 2, 4, 8 hr | 120 | Last option Custom…; 5 min remains valid |

Loaded valid non-preset value selects Custom and shows that value. Match to a preset after successful commit may select that preset only after editing ends. Reject decimals, negatives and overflow; trim outer whitespace, accept locale decimal digits if unambiguous integer; composition never saves intermediate text. No Unlimited preset and no new safety bounds. Cap/grace edits never renew existing anchored deadlines.

## HealthObservation (US3)

kind, optional value, unit, sourceID, sensorID/displayName, sampledAtMonotonic, age, availability available/stale/unsupported/error/notApplicable, bounded reasonCode. Unknown numerical values encode null, never zero or NaN. Lid Open/Closed is typed Boolean-derived state; desktop is Not applicable only after hardware absence is established. Missing key is Unknown.

Each sensor has its own timestamp; do not refresh all timestamps when only one succeeds. Lid age >5 s is stale; sample at 1 s while armed/dashboard-visible and ≤2 s otherwise while awake, suspend correctly during system sleep and resample on wake. Temperature candidate default 2 s interval, stale >10 s; bounded 200 ms read timeout outside main thread, no privilege solely for displaying temperature. Provider selection/source manifest must record supported models/builds, schema/type, units, documented hardware limits, calibration reference and acceptance tolerance before enabling it. No generic CPU temperature average without explicit sensor list/aggregation definition. Temperature is optional advisory; ProcessInfo thermal pressure retains independent stop priority. Source failure logs only availability transitions, not every sample.

## AgentBadge (US4)

providerID in orca/codex/opencode/claude; detectionEnabled; readiness disabled/needsSetup/disconnected/connected/unsupported/error; observed state Active/Waiting/Inactive/Unknown; workingCount/waitingCount/unknownCount; lastEvidenceAge/confidence; enrollment persistence pending/error.

Presentation has two axes: selected/check appearance is detection intent; one line says Active/count, Waiting, Inactive, Unknown, Not connected or Not monitored. Accessible values retain explicit detection intent and confidence; status schema is unchanged. Inactive requires fresh explicit idle/terminal evidence. Never derive activity from checkbox intent/process presence/CPU. Mixed work+unknown shows Active with unknown count in details; no work+unknown shows Unknown; waiting-only shows Waiting; all fresh idle/terminal shows Inactive. Detection Off shows Off without promising completion. Click toggles enrollment intent only; source setup is a separate explicit review flow.

## ProtectionCapability (US5)

buildKind, supportRowID, helperTrust/state, recoveryJournalState, externalOwnership/conflict, qualificationState, requestedClosedLidIntent, backendVerified, leaseVerified, effectiveProtection, blockerCodes.

Statuses Preview / Needs setup / Untested configuration / Conflict / Recovery required / Ready / Protected. Protected requires verified backend+lease and current qualifying safety/evidence; Ready does not imply a held lease. Blocker ordering: recovery/conflict, untrusted helper, unqualified hardware/build, missing setup, preview. Lid sensor success never advances backend qualification. Another utility's global override is conflict even when its mode is Off if ownership cannot be established. Store owned baseline and generation only in existing M1/M2 recovery design, never infer ownership from matching value.
