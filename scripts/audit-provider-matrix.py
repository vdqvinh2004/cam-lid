#!/usr/bin/env python3
"""Read-only audit of saved benchmark metadata; never prints content/argv."""
import collections
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
report = {"scope": "captured-provider-streams", "liveBridgeAcceptance": False, "providers": {}}
for provider in ["codex", "opencode"]:
    directory = ROOT / "docs/qa/preview-evidence/provider-matrix" / provider
    rows = []
    for number in range(1, 21):
        metadata = directory / f"run-{number:02d}.meta.json"
        stream = directory / f"run-{number:02d}.jsonl"
        meta = json.loads(metadata.read_text())
        types = collections.Counter()
        tool_failures = 0
        malformed = 0
        for line in stream.read_text().splitlines():
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                malformed += 1
                continue
            types[event.get("type", "unknown")] += 1
            item = event.get("item") or {}
            if item.get("type") == "command_execution" and item.get("status") == "failed":
                tool_failures += 1
        rows.append({"run": number, "profile": meta.get("profile"), "producerExit": meta.get("exit_code"),
                     "eventTypes": dict(types), "toolFailures": tool_failures, "malformedLines": malformed,
                     "recorded": metadata.exists() and stream.exists()})
    report["providers"][provider] = {"recordedRuns": len(rows), "runs": rows}
report["limits"] = ["Recorded runs are not all passing lifecycle acceptance cases.",
    "A nonzero tool result inside a completed turn is not agent failure.",
    "OpenCode step_finish is not session completion.",
    "Approval redirects and background-child prompts do not prove denied/detached tracking.",
    "No network fault, installed hook, other vendor, or hardware acceptance inferred."]
print(json.dumps(report, indent=2, sort_keys=True))
