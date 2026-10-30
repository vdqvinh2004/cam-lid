# Historical provider fixtures

These three versioned JSONL examples were captured from author-authored trivial QA jobs in
2026-10-05's Codex/OpenCode matrix. They contain benchmark commands/output, not user work.
They exercise legacy parser → `ProviderStream` → `RuntimeAgentStore` regressions, including
failed tool ≠ failed turn, OpenCode step finish ≠ completion, and EOF → Unknown for work.
They do not qualify current third-person product observation or restore disabled ingress.

The mandatory suite reads these committed files directly; no provider is launched or queried.
Do not replace them with copies of private transcripts.

The separate 40-run historical archive is not part of the checkout. To verify an existing
archive explicitly (no new provider work):

```sh
CAMLID_CAPTURED_MATRIX_DIRECTORY=/absolute/path/to/provider-matrix \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --package-path Packages/CamLidCore --no-parallel \
  --filter CapturedMatrixReplayTests
```

The directory must contain `codex/run-01.jsonl` … `run-20.jsonl` and the corresponding
`opencode` files. Opted-in replay fails if any file is missing or invalid; it never fills gaps
with synthetic captures. Without the variable, only the archive test is visibly skipped.
