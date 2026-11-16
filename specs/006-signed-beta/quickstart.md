# Validation Quickstart: M5 Signed Beta and Updates

**Current availability**: Native preview Updates window, CLI update status and local packaging audit/archive tool. Information-only check remains unavailable without signed release metadata.

1. Verify prerequisites: M2, M3, M4; review their recorded gate evidence.
2. Read [spec](spec.md), [plan](plan.md), [tasks](tasks.md), shared limitations.
3. Execute authorized scoped work only after prerequisites. Validation: Signed candidate install/upgrade/remove and update trust tests on supported rows.
4. Check independent story outcomes in spec.md; record expected/actual, source, environment and
   failure-class timing. No simulator result establishes lid/display behavior.
5. Exit only when Distribution trust and owned-state cleanup verified before external test; unresolved recovery prevents installer/removal success claims.

Future CLI usage and supervised end-to-end sequence: shared guide.
Use explicit feature context from repository root when invoking Spec Kit:
```
SPECIFY_FEATURE_DIRECTORY=specs/006-signed-beta rtk .specify/scripts/bash/check-prerequisites.sh --json --require-spec --require-tasks --include-tasks
```
This check resolves documents only. M6 and M7 remain separate quality/user gates.

Open native Check for Updates… to inspect status. CLI `camlid status --json` includes `updates`. No update installation, power helper, notarization submission or publication occurs in the preview.


## M8 login registration regression — implementation added 2026-10-08

SMAppService.mainApp now applies explicit `launchAtLogin` intent and reports actual OS state. Ordinary Quit preserves login intent; startup never resumes an active mode. An ad-hoc QA app reporting notFound does not establish signed startup support.

For a signed isolated candidate only:

1. Record prior intent and actual Login Items state. Use the isolated app identity, not the user's installed app.
2. Enable startup explicitly in Defaults. Verify enabled or requiresApproval in macOS and CamLid; denied registration must remain an error, not a successful config claim. Complete required OS approval intentionally.
3. Revoke externally, reopen Settings, verify reconciliation; disable through the app and verify notRegistered. Login must open with activeSessionMode=null and no lease.
4. Upgrade the same signed identity at its installed path. Preserve intent; read actual OS registration after update and test next login. Never resume a prior session or silently register when intent is off.
5. Before removing the final installed copy, stop and verify owned power restoration, explicitly turn Launch at login off, then verify notRegistered in CamLid and macOS. Registration/cleanup error blocks a successful uninstall claim; do not delete unknown/foreign login entries. Quit and remove only the isolated owned app after verification.
6. Restore the isolated test's original registration intent/state and record all results in the M8 QA report.

These signed login/update/removal checks remain NOT RUN; unit adapter/error/no-auto-arm checks and five packaging-tool tests are separate evidence.
