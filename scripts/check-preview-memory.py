#!/usr/bin/env python3
"""Assert the strict preview RSS budget over an entire recorded observation."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("sample", type=Path)
parser.add_argument("--limit-mib", type=float, default=100)
args = parser.parse_args()
rows = [json.loads(line) for line in args.sample.read_text().splitlines()]
samples = [row for row in rows if row.get("kind") == "sample"]
assert samples and len({row["pid"] for row in samples}) == 1, "Missing or mixed-process samples"
assert rows[-1].get("kind") == "summary", "Observation incomplete"
peak = max(row["rssKiB"] for row in samples) / 1024
assert peak == rows[-1]["rssMaxMiB"], "Summary does not match raw samples"
print(f"Peak RSS {peak:.2f} MiB; strict limit {args.limit_mib:.2f} MiB", flush=True)
raise SystemExit(0 if peak < args.limit_mib else 1)
