#!/usr/bin/env python3
"""Reproducible preview QA; cannot pass the physical/signing/user gates."""
import argparse
import hashlib
import json
import os
import plistlib
import re
from pathlib import Path
import subprocess
import tempfile
from datetime import datetime, timezone

parser = argparse.ArgumentParser()
parser.add_argument("--output", default="docs/qa/preview-evidence")
parser.add_argument("--build-directory", help="Reuse an isolated QA build directory; never deletes it")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
output = (root / args.output).resolve()
output.mkdir(parents=True, exist_ok=True)
scratch = Path(args.build_directory).resolve() if args.build_directory else Path(tempfile.mkdtemp(prefix="camlid-verify-"))
spm = scratch / "spm"
xcode = scratch / "xcode"
env = os.environ.copy()
report = {"schemaVersion": 1, "startedAt": datetime.now(timezone.utc).isoformat(),
          "scope": "preview-only", "m1Passed": False, "m6Passed": False, "steps": []}
def source_manifest():
    files = sorted(list((root / "Tests/Packaging").glob("*.py")) + list((root / "Packages/CamLidCore").glob("Sources/**/*.swift")) + list((root / "Packages/CamLidCore").glob("Tests/**/*.swift")) + [root / "CamLidApp/AppMain.swift", root / "CamLidApp/Info.plist", root / "Packages/CamLidCore/Package.swift", root / "project.yml", root / "CamLid.xcodeproj/project.pbxproj", root / "scripts/verify-preview.py", root / "scripts/hardware-preflight.py", root / "scripts/package-beta.py", root / "Config/Beta.xcconfig", root / "Packages/CamLidCore/Package.resolved"])
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
initial_manifest = source_manifest()
commands = [
    # Native suites share AppKit state and assert short wall-clock deadlines.
    # Suite-level .serialized does not isolate unrelated Swift Testing suites.
    ("swift-tests", ["swift", "test", "--no-parallel", "--scratch-path", str(spm)], root / "Packages/CamLidCore", "clt"),
    ("debug-build", ["xcodebuild", "-project", "CamLid.xcodeproj", "-scheme", "CamLid", "-configuration", "Debug", "-destination", "platform=macOS,arch=arm64", "-derivedDataPath", str(xcode), "CODE_SIGNING_ALLOWED=NO", "build"], root, "xcode"),
    ("release-build", ["xcodebuild", "-project", "CamLid.xcodeproj", "-scheme", "CamLid", "-configuration", "Release", "-destination", "platform=macOS,arch=arm64", "-derivedDataPath", str(xcode), "CODE_SIGNING_ALLOWED=NO", "build"], root, "xcode"),
    ("binary-integration", ["swift", "test", "--scratch-path", str(spm), "--filter", "ControlIntegrationTests"], root / "Packages/CamLidCore", "clt"),
    ("packaging-tests", ["python3", "-m", "unittest", "discover", "-s", "Tests/Packaging"], root, "read-only"),
    ("preview-package-audit", ["python3", str(root / "scripts/package-beta.py"), "--app", str(xcode / "Build/Products/Debug/CamLid.app")], root, "read-only"),
    ("hardware-preflight", ["python3", str(root / "scripts/hardware-preflight.py")], root, "read-only"),
]
for name, command, cwd, toolchain in commands:
    step_env = env.copy()
    if toolchain == "clt": step_env["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
    if toolchain == "xcode": step_env["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
    step_env["CAMLID_LIVE_ORCA_PROBE"] = "0"
    step_env["CAMLID_INSTALLED_PROVIDER_QA"] = "0"
    if name == "binary-integration": step_env["CAMLID_CLI_PATH"] = str(xcode / "Build/Products/Debug/camlid")
    with (output / (name + ".log")).open("w") as log:
        completed = subprocess.run(command, cwd=cwd, env=step_env, stdout=log, stderr=subprocess.STDOUT)
    if name in {"debug-build", "release-build"} and completed.returncode == 0:
        configuration = "Debug" if name == "debug-build" else "Release"
        bundle = xcode / "Build/Products" / configuration / "CamLid.app"
        info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
        executable = info.get("CFBundleExecutable", "")
        valid = (info.get("CFBundlePackageType") == "APPL" and executable == "CamLid"
                 and (bundle / "Contents/MacOS" / executable).is_file())
        report.setdefault("bundleChecks", {})[configuration] = valid
        if not valid: completed.returncode = 1
    report["steps"].append({"name": name, "exitCode": completed.returncode, "evidence": name + ".log"})
    print(name + ": " + ("PASS" if completed.returncode == 0 else "FAIL"), flush=True)
    if completed.returncode: break
report["previewChecksPassed"] = len(report["steps"]) == len(commands) and all(s["exitCode"] == 0 for s in report["steps"])
counts = [int(x) for x in re.findall(r"Test run with (\d+) tests?", (output / "swift-tests.log").read_text())]
report["testCountsByRun"] = counts
report["testCount"] = sum(counts)
report["previewChecksPassed"] = report["previewChecksPassed"] and report["testCount"] >= 154 and all(name in (output / "swift-tests.log").read_text() for name in ["Policy hazards (T007)", "CLI contract checks (007-T001)", "Preview coordinator integration"])
report["finishedAt"] = datetime.now(timezone.utc).isoformat()
report["buildDirectory"] = str(scratch)
report["sourceSHA256"] = source_manifest()
report["sourceUnchangedDuringVerification"] = initial_manifest == report["sourceSHA256"]
report["previewChecksPassed"] = report["previewChecksPassed"] and report["sourceUnchangedDuringVerification"]
(output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
raise SystemExit(0 if report["previewChecksPassed"] else 1)
