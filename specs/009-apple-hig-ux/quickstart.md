# M4a Validation Guide

Planning only. Future execution needs an accessible macOS desktop, built QA bundle and isolated test state. No power setting changes.

1. Select feature and validate document discovery:
   `rtk env SPECIFY_FEATURE_DIRECTORY=specs/009-apple-hig-ux .specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks`
2. Prepare deterministic ten-state dashboard fixtures and isolated configuration/history. Document launcher resolution before using CUA; do not bypass a locked desktop or inaccessible GUI.
3. Execute essential actions and appearance/layout matrix from [contract](contracts/interaction.md); record before/after evidence.
4. Repeat primary flows with keyboard and real VoiceOver. Verify background refresh never changes focus, drafts survive conflict and timer announcements remain restrained.
6. Compare saved configuration/status with the real CLI. Validate no session cap renewal, unsafe mode enablement, unredacted history or actual power mutation.
7. Rerun regressions/builds and M6 performance measurement after changes. Mark any unexecuted case blocked; M4a PASS requires all applicable UX success criteria and no critical/high UX defects.

HIG PASS is not Apple certification or M1/M6 PASS. Real user research remains M7 after M6 approval.
