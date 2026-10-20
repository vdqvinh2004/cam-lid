#!/usr/bin/env python3
"""Read-only M1 preparation. Never changes power, fans, assertions, or settings."""
import json
import re
import subprocess


def read(args):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=10)
        return result.stdout if result.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def snapshot():
    hardware = read(["system_profiler", "SPHardwareDataType", "-json"])
    try:
        row = json.loads(hardware)["SPHardwareDataType"][0]
        model, chip = row.get("machine_model"), row.get("chip_type")
    except (TypeError, KeyError, ValueError, IndexError):
        model = chip = None
    custom = read(["pmset", "-g", "custom"])
    assertions = read(["pmset", "-g", "assertions"])
    counts = {}
    for key in ["PreventUserIdleSystemSleep", "PreventSystemSleep", "PreventUserIdleDisplaySleep", "UserIsActive", "BackgroundTask"]:
        match = re.search(r"^\s*" + key + r"\s+(\d+)\s*$", assertions or "", re.M)
        counts[key] = int(match.group(1)) if match else None
    disabled = re.findall(r"^\s*SleepDisabled\s+(\d+)\s*$", custom or "", re.M)
    return {
        "schemaVersion": 1, "readOnly": True, "powerMutated": False,
        "model": model, "chip": chip,
        "macOS": (read(["sw_vers", "-productVersion"]) or "").strip() or None,
        "osBuild": (read(["sw_vers", "-buildVersion"]) or "").strip() or None,
        "sleepDisabledValues": [int(x) for x in disabled],
        "sleepDisabledObserved": bool(disabled),
        "assertionCounts": counts,
        "backendVerified": False, "m1Gate": "pendingSupervisedPhysicalValidation",
        "note": "Assertion names, command lines, serial numbers, UUIDs, and agent content omitted. Unknown is not healthy."
    }

if __name__ == "__main__":
    print(json.dumps(snapshot(), indent=2, sort_keys=True))
