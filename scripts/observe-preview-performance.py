#!/usr/bin/env python3
"""Passive resource evidence for one explicitly identified owned QA process.

Never launches/terminates an app, changes settings, or manipulates power.
CPU is measured from cumulative process CPU time, not ps's lifetime percentage.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import time


def ps(pid, field):
    return subprocess.run(["/bin/ps", "-p", str(pid), "-o", field + "="],
                          capture_output=True, text=True, check=True, timeout=2).stdout.strip()


def cpu_seconds(value):
    days, separator, clock = value.partition("-")
    if not separator:
        clock, days = days, "0"
    parts = clock.split(":")
    if len(parts) not in (2, 3):
        raise ValueError("Unsupported process CPU-time format")
    total = 0.0
    for part in parts:
        total = total * 60 + float(part)
    return int(days) * 86400 + total


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--expected-executable", required=True,
                        help="Exact owned QA executable path, checked before sampling")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--duration", type=int, default=600)
    parser.add_argument("--interval", type=int, default=10)
    args = parser.parse_args()
    if args.pid <= 0 or not 1 <= args.duration <= 3600 or not 1 <= args.interval <= 60:
        parser.error("Invalid PID, duration or interval")
    if ps(args.pid, "comm") != args.expected_executable:
        parser.error("PID is not the specified owned QA executable")
    birth = ps(args.pid, "lstart")
    if int(ps(args.pid, "uid")) != os.getuid():
        parser.error("QA process belongs to another user")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    samples = []
    start = time.monotonic()
    with os.fdopen(fd, "w") as output:
        while True:
            if ps(args.pid, "lstart") != birth or ps(args.pid, "comm") != args.expected_executable:
                raise RuntimeError("QA process changed; evidence stopped without acting on it")
            sample = {"kind": "sample", "utc": datetime.now(timezone.utc).isoformat(),
                      "monotonic": time.monotonic(), "pid": args.pid,
                      "cpuSeconds": cpu_seconds(ps(args.pid, "time")),
                      "rssKiB": int(ps(args.pid, "rss")), "powerActuation": False}
            samples.append(sample)
            output.write(json.dumps(sample, sort_keys=True) + "\n")
            output.flush()
            if sample["monotonic"] - start >= args.duration:
                break
            time.sleep(min(args.interval, max(0, args.duration - (time.monotonic() - start))))
        span = samples[-1]["monotonic"] - samples[0]["monotonic"]
        cpu = 100 * (samples[-1]["cpuSeconds"] - samples[0]["cpuSeconds"]) / span
        summary = {"kind": "summary", "samples": len(samples), "spanSeconds": span,
                   "cpuMeanPercentOneCore": cpu,
                   "rssMaxMiB": max(x["rssKiB"] for x in samples) / 1024,
                   "fullTenMinuteSample": span >= 599,
                   "powerActuation": False,
                   "scope": "passive process resources; no dashboard/power acceptance"}
        output.write(json.dumps(summary, sort_keys=True) + "\n")
        print(json.dumps(summary, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
