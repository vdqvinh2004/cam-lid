# Presentation and Evidence Model

No new persistence or policy model. Existing authoritative configuration, policy, task and history models remain unchanged.

| Entity | Fields / constraints | Relationships |
| --- | --- | --- |
| PresentationState | requestedMode; effectiveState; capability; reason; health/freshness; task summary; cap/grace; nextAction. **Unknown must not become healthy or verified.** | Derived from existing coordinator/policy; never actuates power. |
| SettingsDraft | originalRevision; draft values; field errors; save outcome. **Invalid or conflicted drafts must not partially persist.** | Existing revision-aware config save; preserve draft on failure. |
| ReviewCase | ID; UX requirement; Apple source URL; surface; environment; expected/actual; evidence path; pass/fail/blocked; severity. **Blocked evidence must never be recorded as pass.** | HIG review and M6 evidence. |

State transitions: open → edit → validate → save success/revision conflict/error; Escape/outside click dismiss dashboard; explicit user action can focus windows, background refresh cannot. Policy transitions remain owned by Core. Review disposition can move blocked/failed → passed only after new evidence.
