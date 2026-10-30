#!/usr/bin/env python3
"""Stage an uninstalled, locally pinned QA bundle. Never registers or executes it."""
import argparse
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BUILD_ROOT = ROOT / ".pi" / "qa-builds"
APP_ID = "com.camlid.PowerCandidate"
HELPER_ID = "com.camlid.power-helper"


def cdhash(text):
    values = re.findall(r"^CDHash=([0-9a-f]{40})$", text, re.MULTILINE)
    if len(values) != 1:
        raise ValueError("missing or ambiguous CDHash")
    return values[0]


def within_build_root(path, exists=True):
    path = Path(path).resolve(strict=exists)
    if path == BUILD_ROOT or BUILD_ROOT not in path.parents:
        raise ValueError("all stage inputs/outputs must be inside repository .pi/qa-builds")
    return path


def sign(path, identifier):
    subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--options", "runtime",
                    "--timestamp=none", "--identifier", identifier, str(path)], check=True)
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "--deep", str(path)], check=True)
    result = subprocess.run(["/usr/bin/codesign", "--display", "--verbose=4", str(path)],
                            check=True, capture_output=True, text=True)
    if "runtime" not in result.stderr or f"Identifier={identifier}\n" not in result.stderr:
        raise ValueError("unexpected signature flags or identifier")
    return cdhash(result.stderr)


def stage(helper, client, output, lid_specific=False, best_effort=False):
    helper, client = within_build_root(helper), within_build_root(client)
    output = within_build_root(output, exists=False)
    if not helper.is_file() or not client.is_file():
        raise ValueError("compiled helper and QA client required")
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    app = output / "CamLid Power Candidate.app"
    contents = app / "Contents"
    for directory in ["MacOS", "Library/LaunchServices"]:
        (contents / directory).mkdir(parents=True, exist_ok=True)
    app_binary = contents / "MacOS" / "CamLidPowerQA"
    helper_binary = contents / "Library/LaunchServices" / "camlid-power-helper"
    shutil.copy2(client, app_binary)
    shutil.copy2(helper, helper_binary)
    daemon = plistlib.loads((Path(__file__).parent / f"{HELPER_ID}.local.plist").read_bytes())
    helper_mode = "--standard-v1"
    daemon["ProgramArguments"] = [daemon["Program"], helper_mode]
    if best_effort:
        helper_mode = "--lid-specific-best-effort-v1"
        daemon["ProgramArguments"] = [daemon["Program"], helper_mode]
    elif lid_specific:
        helper_mode = "--lid-specific-v1"
        daemon["ProgramArguments"] = [daemon["Program"], helper_mode]
    with (output / f"{HELPER_ID}.plist").open("wb") as handle:
        plistlib.dump(daemon, handle)
    info = {"CFBundleIdentifier": APP_ID, "CFBundleName": "CamLid Power Candidate",
            "CFBundleExecutable": "CamLidPowerQA", "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1", "CFBundleShortVersionString": "0.1",
            "LSMinimumSystemVersion": "14.0", "LSUIElement": True}
    with (contents / "Info.plist").open("wb") as handle:
        plistlib.dump(info, handle)
    helper_hash = sign(helper_binary, HELPER_ID)
    app_hash = sign(app, APP_ID)
    if helper_hash == app_hash:
        raise ValueError("role identities must be distinct")
    pins = {"version": 1, "appCDHash": app_hash, "helperCDHash": helper_hash}
    (output / "identity.json").write_text(json.dumps(pins, indent=2) + "\n")
    files = {str(p.relative_to(output)): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in output.rglob("*") if p.is_file()}
    manifest = {"disposition": "STAGED_ONLY_NOT_INSTALLED_NOT_QUALIFIED", "rootIdentityInstalled": False,
                "registered": False, "powerActuation": False, "deployment": "root-installed local LaunchDaemon, not SMAppService",
                "mechanismFamily": "lid-specific-v1" if (lid_specific or best_effort) else "pmset-global-v1",
                "helperMode": helper_mode,
                "maximumSessionSeconds": 900 if best_effort else (24 if lid_specific else 14400),
                "pins": pins, "sha256": files}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"stagedApp": str(app), "manifest": str(output / "manifest.json"),
                      "note": "No registration, root installation, app launch or power change performed."}, indent=2))


def self_test():
    expected = "a" * 40
    assert cdhash("Identifier=test\nCDHash=" + expected + "\n") == expected
    for invalid in ["", "CDHash=bad", "CDHash=" + expected + "\nCDHash=" + expected]:
        try:
            cdhash(invalid)
        except ValueError:
            pass
        else:
            raise AssertionError("invalid signature metadata accepted")
    for unsafe in [ROOT, ROOT / "Packages", Path("/Applications/Existing.app")]:
        try:
            within_build_root(unsafe, exists=False)
        except ValueError:
            pass
        else:
            raise AssertionError("unsafe staging path accepted")
    assert within_build_root(BUILD_ROOT / "candidate-self-check", exists=False).parent == BUILD_ROOT
    daemon = plistlib.loads((Path(__file__).parent / f"{HELPER_ID}.local.plist").read_bytes())
    assert daemon["Label"] == HELPER_ID
    assert daemon["Program"] == f"/Library/PrivilegedHelperTools/{HELPER_ID}"
    assert daemon["ProgramArguments"] == [daemon["Program"], "--standard-v1"]
    assert daemon["MachServices"] == {HELPER_ID: True}
    assert "BundleProgram" not in daemon
    for mode in ("--lid-specific-v1", "--lid-specific-best-effort-v1"):
        variant = plistlib.loads((Path(__file__).parent / f"{HELPER_ID}.local.plist").read_bytes())
        variant["ProgramArguments"] = [variant["Program"], mode]
        assert variant["ProgramArguments"] != daemon["ProgramArguments"] and variant["Label"] == HELPER_ID
    print("PASS: stage paths, CDHash parser and fixed local daemon plan; no signing/install/power calls")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--helper")
    parser.add_argument("--client")
    parser.add_argument("--output")
    parser.add_argument("--lid-specific", action="store_true")
    parser.add_argument("--lid-specific-best-effort", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    elif args.helper and args.client and args.output:
        stage(args.helper, args.client, args.output,
              lid_specific=args.lid_specific, best_effort=args.lid_specific_best_effort)
    else:
        parser.error("use --self-test or supply --helper, --client and --output")
