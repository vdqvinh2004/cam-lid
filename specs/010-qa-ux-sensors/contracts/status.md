# Status/config compatibility contract

Feature010 preview increment implements additive status fields; existing keys and CLI exit semantics remain intact. Per-source qualification and full acceptance remain open. No new direct power escape hatch.

## Status projection

health.temperature: valueCelsius (number|null), sensorID, displayName, source, availability (available/stale/unsupported/error), ageSeconds (number|null), reasonCode (bounded enum).
health.lid: state (open/closed/unknown/notApplicable), source, availability, ageSeconds, reasonCode.
health.thermalPressure remains existing qualitative value; numerical temperature never replaces it.
agentDetection[]: provider, detectionEnabled, readiness, observedState, workingCount, waitingCount, unknownCount, evidenceAgeSeconds/confidence. No prompts, paths, raw provider output or user identifiers.
protection: requested intent, effective state, qualified supportRowID|null, blockerCodes[], backendVerified, leaseVerified, recoveryRequired. Protected requires actual verified actuation.

GUI and CLI receive the same immutable snapshot/revision. Null means unavailable, not zero. Schema decoding distinguishes absent legacy fields from null readings. Diagnostic reasons are known bounded codes with user-facing localized mapping, never raw lidUnknown on screen. Unit conversions are presentation-only; stored temperature uses Celsius. Sampling timestamps are monotonic, invalid future/negative ages rejected.

## Config writes

Reuse existing config/app control endpoint, with typed per-field patch + expected revision; no filesystem bypass from GUI. Validate complete resultant Configuration atomically; preserve all untouched fields. Backend reports persisted revision/value or conflict/validation/storage error. Use current/Apply my value rereads latest revision. Limits/defaults unchanged by migration; preserve non-preset custom values. Do not invent a CLI syntax: document actual commands/help after implementation, add tests against it.

## QA boundaries

Fixture injection belongs to simulator/isolated QA root; production live status cannot silently replace readings with fixtures. PowerActuationAvailable remains false until M1/M2 gates pass. Read-only status must not arm/start helper/check network updates. Shared policy assertions pin caps/unknown waiting/critical thermal and existing provider replay semantics.

## Current authority implementation

GUI uses ConfigPatch plus expected revision through AppCoordinator; same-user CLI uses the existing `camlid config set --file <patch.json> --expectedRevision <N>` syntax. File `History/preferences.json` stores validated schema1 revision+configuration, owner mode0600 and atomic same-directory rename. Legacy UserDefaults config is read only when no authoritative file exists. Invalid/unreadable authoritative file cannot silently fall back to older settings. Persistence precedes authority/policy update; no partial in-memory apply on error.

Untouched fields rebase once after unrelated concurrent writes. Same-field conflict preserves input until Use current or Apply my value. Open Settings receives current revisions on each tick while keeping pending raw text and its original field base. Existing cap/grace/wait anchors are retained. Runtime GUI/RPC writes prepare on one bounded off-main worker, then the authority rechecks cancellation, deadline and revision before atomic installation. Pending edits are serialized/coalesced; Applying appears after150 ms; Preference settlement waits at most2 s before explicit disposition; quit additionally gives accepted history a separate2 s barrier. Late preparation removes staging files and cannot install settings. Final installation runs off main thread and is admitted atomically against cancellation. Once its filesystem syscall starts, timeout returns commitUnconfirmed/exit5 with mayApplyLater:true/readBackRequired:true; further writes and updates remain blocked until the actual result reconciles once. Status exposes settingsCommitPending. A confirmed late failure replaces stale uncertainty in Settings. A late success advances the persisted revision once. Discard does not claim to cancel an installation already in progress. Quit seals history mutation admission, preserves bounded deferred transitions on Keep Open, and requires explicit consent if any settings/history work is unconfirmed. Tests establish application-level bounds, not a universal filesystem latency guarantee. IOKit runs on one utility worker; stalled reads never block pressure sampling or schedule unlimited jobs. Physical/native latency acceptance remains open.

Live status reads real sensors and exports lid state/source/availability/age plus numerical temperature fields as explicit null/unsupported when no source is qualified. Provider ages serialize explicit null when disconnected. Current protection preserves effectiveState:Preview and adds readinessState from the pure gate projection. supportRowID:null, backendVerified:false, leaseVerified:false and recoveryRequired:false stay truthful. Missing ownership evidence yields Conflict; blockerCodes and user-facing details include previewPowerDisabled, backendPendingM1, ownershipUnverified and absent support/helper/journal requirements. Pure fixtures pin every gate and precedence; production facts cannot raise verification. Real helper/backend qualification remains open. Status contract integration test resides in CamLidAppTests because that module owns live authority; CLI model tests remain independent of the GUI/Sparkle dependency.
