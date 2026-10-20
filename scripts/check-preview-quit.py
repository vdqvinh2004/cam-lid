#!/usr/bin/env python3
"""Request quit over the preview CLI and prove the exact owned process exited."""
import argparse
import json
import os
import subprocess
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--pid", type=int, required=True)
p.add_argument("--executable", required=True)
p.add_argument("--cli", required=True)
p.add_argument("--control-directory", required=True)
p.add_argument("--already-requested", action="store_true")
a = p.parse_args()

def identity():
    r = subprocess.run(["/bin/ps", "-p", str(a.pid), "-o", "uid=,lstart=,comm="], capture_output=True, text=True, timeout=2)
    return r.stdout.strip()

initial = identity()
assert initial and initial.split()[0] == str(os.getuid()) and initial.endswith(a.executable), "Not the specified owned QA process"
env = dict(os.environ, CAMLID_CONTROL_DIRECTORY=a.control_directory)
if not a.already_requested:
    status = json.loads(subprocess.check_output([a.cli, "status", "--json"], env=env, timeout=2))
    assert status["preview"] and status["powerActuation"] is False, "Not a zero-actuation preview"
    reply = json.loads(subprocess.check_output([a.cli, "quit", "--json"], env=env, timeout=2))
    assert reply["accepted"] and reply["cleanupOutcome"] == "noPowerResourcesOwned"
start = time.monotonic()
while identity() == initial and time.monotonic() - start < 5:
    time.sleep(0.05)
assert identity() != initial, "Quit accepted but owned preview process did not exit within 5 seconds"
print(json.dumps({"quitConfirmed": True, "elapsedSeconds": time.monotonic() - start, "powerActuation": False}))
