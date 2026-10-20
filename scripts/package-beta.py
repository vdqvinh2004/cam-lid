#!/usr/bin/env python3
"""Read-only bundle audit or local archive creation. Never signs, installs or publishes."""
import argparse
import base64
import hashlib
import json
import plistlib
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlsplit


def run(argv):
    result = subprocess.run(argv, capture_output=True, text=True, timeout=90)
    return result.returncode, result.stdout + result.stderr


def audit(bundle, mode, expected_team=None, gates=None):
    bundle = bundle.resolve()
    failures = []
    try:
        info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    except (OSError, plistlib.InvalidFileException):
        return {"mode": mode, "checksPassed": False, "betaEligible": False, "failures": ["invalidBundleInfo"]}
    executable = info.get("CFBundleExecutable")
    if (info.get("CFBundlePackageType") != "APPL" or executable != "CamLid"
            or not (bundle / "Contents/MacOS/CamLid").is_file()
            or info.get("CFBundleIdentifier") != "com.camlid.CamLid"):
        failures.append("invalidApplicationMetadata")
    if not info.get("CFBundleVersion") or not info.get("CFBundleShortVersionString"):
        failures.append("missingVersion")
    for path in bundle.rglob("*"):
        if path.is_symlink() and not path.resolve().is_relative_to(bundle):
            failures.append("bundleSymlinkEscapes"); break
    framework = bundle / "Contents/Frameworks/Sparkle.framework"
    try:
        sparkle = plistlib.loads((framework / "Resources/Info.plist").read_bytes())
        if sparkle.get("CFBundleShortVersionString") != "2.10.0": failures.append("sparkleVersionMismatch")
    except (OSError, plistlib.InvalidFileException):
        failures.append("sparkleNotEmbedded")
    for key in ["SUEnableAutomaticChecks", "SUAutomaticallyUpdate", "SUAllowsAutomaticUpdates", "SUSendProfileInfo"]:
        if info.get(key) is not False: failures.append("unsafeUpdaterDefault:" + key)
    if mode == "beta":
        try:
            feed = urlsplit(info.get("SUFeedURL", ""))
            valid_feed = feed.scheme == "https" and feed.hostname and not feed.username and not feed.password and not feed.fragment
            valid_key = len(base64.b64decode(info.get("SUPublicEDKey", ""), validate=True)) == 32
        except (ValueError, TypeError):
            valid_feed = valid_key = False
        if not valid_feed: failures.append("trustedFeedRequired")
        if not valid_key: failures.append("updateSigningKeyRequired")
        if not expected_team or info.get("CamLidUpdateTeamID") != expected_team:
            failures.append("expectedTeamRequired")
        verify_code, _ = run(["codesign", "--verify", "--deep", "--strict", str(bundle)])
        _, signature = run(["codesign", "-d", "--verbose=4", str(bundle)])
        signature_fields = dict(line.split("=", 1) for line in signature.splitlines() if "=" in line)
        requirement = 'anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'
        developer_id_code, _ = run(["codesign", "--verify", "-R", requirement, str(bundle)])
        if verify_code or developer_id_code or not expected_team or signature_fields.get("TeamIdentifier") != expected_team:
            failures.append("developerIDSignatureRequired")
        if not any(line.startswith("CodeDirectory ") and "(runtime)" in line for line in signature.splitlines()):
            failures.append("hardenedRuntimeRequired")
        if run(["xcrun", "stapler", "validate", str(bundle)])[0]: failures.append("stapledNotarizationRequired")
        if run(["spctl", "--assess", "--type", "execute", str(bundle)])[0]: failures.append("gatekeeperAssessmentFailed")
        required = ["m1Passed", "m2Passed", "m3Passed", "m4Passed", "m4aPassed"]
        if not gates or any(gates.get(key) is not True for key in required): failures.append("predecessorGatesRequired")
        manifest = gates.get("sourceSHA256", {}) if gates else {}
        root = Path(__file__).resolve().parent.parent
        required_sources = {str(p.relative_to(root)) for p in (root / "Packages/CamLidCore/Sources").rglob("*.swift")}
        required_sources.update(["CamLidApp/AppMain.swift", "CamLidApp/Info.plist", "project.yml", "CamLid.xcodeproj/project.pbxproj",
                                 "Packages/CamLidCore/Package.swift", "Packages/CamLidCore/Package.resolved",
                                 "scripts/package-beta.py", "Config/Beta.xcconfig"])
        if not isinstance(manifest, dict) or not required_sources.issubset(manifest) or any(not (root / p).is_file() or hashlib.sha256((root / p).read_bytes()).hexdigest() != value
                               for p, value in manifest.items()): failures.append("currentSourceEvidenceRequired")
    return {"schemaVersion": 1, "mode": mode, "checksPassed": not failures,
            "betaEligible": mode == "beta" and not failures,
            "powerActuation": False, "installationPerformed": False,
            "version": info.get("CFBundleShortVersionString"), "failures": failures}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--mode", choices=["preview", "beta"], default="preview")
    parser.add_argument("--team-id")
    parser.add_argument("--gates", type=Path)
    parser.add_argument("--output-directory", type=Path, help="Create a local archive in a NEW directory; omission audits only")
    args = parser.parse_args()
    try:
        gates = json.loads(args.gates.read_text()) if args.gates else None
        if gates is not None and not isinstance(gates, dict): raise ValueError("gate evidence must be an object")
        report = audit(args.app, args.mode, args.team_id, gates)
        if args.output_directory and report["checksPassed"]:
            destination = args.output_directory.resolve()
            destination.mkdir(parents=True, exist_ok=False)
            archive = destination / ("CamLid-" + args.mode + ".zip")
            code, _ = run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(args.app.resolve()), str(archive)])
            if code: raise RuntimeError("archive creation failed; output retained for diagnosis")
            report["archiveSHA256"] = hashlib.sha256(archive.read_bytes()).hexdigest()
            (destination / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))
        return 0 if report["checksPassed"] else 4
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(json.dumps({"checksPassed": False, "betaEligible": False, "reason": type(error).__name__}))
        return 4


if __name__ == "__main__":
    sys.exit(main())
