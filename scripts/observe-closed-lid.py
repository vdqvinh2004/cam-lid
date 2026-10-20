#!/usr/bin/env python3
"""Read-only evidence collector. Never acquires/releases power resources.

No backend owner is inferred; observations do not qualify CamLid.
Public display readings are uncalibrated; no built-in display means Unknown.
Duration bounds intended collection, not a stalled OS read. JSONL is whitelisted.
"""
import argparse, ctypes, datetime, json, os, plistlib, subprocess, time
from pathlib import Path


def display_snapshot(api=None):
    started = time.monotonic()
    result = {"internalDisplay": "unknown", "externalOnlineDisplays": None,
              "displayAvailability": "error", "displayReason": "sourceUnavailable",
              "displaySource": "CoreGraphics.CGDisplayIsAsleep",
              "displaySampledAtMonotonic": started, "panelCalibrated": False}
    try:
        if api is None:
            api = ctypes.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
            api.CGGetOnlineDisplayList.argtypes = [ctypes.c_uint32,
                ctypes.POINTER(ctypes.c_uint32), ctypes.POINTER(ctypes.c_uint32)]
            api.CGGetOnlineDisplayList.restype = ctypes.c_int32
            for name in ("CGDisplayIsBuiltin", "CGDisplayIsOnline", "CGDisplayIsAsleep"):
                function = getattr(api, name)
                function.argtypes = [ctypes.c_uint32]
                function.restype = ctypes.c_uint32
        displays = (ctypes.c_uint32 * 32)()
        count = ctypes.c_uint32()
        if api.CGGetOnlineDisplayList(32, displays, ctypes.byref(count)) != 0:
            result["displayReason"] = "enumerationFailed"
            return result
        identifiers = list(displays[:count.value])
        if not 0 < count.value < 32 or len(set(identifiers)) != count.value:
            result["displayReason"] = "invalidOrTruncatedDisplayList"
            return result
        builtins, external = [], 0
        for display in identifiers:
            online = api.CGDisplayIsOnline(display)
            builtin = api.CGDisplayIsBuiltin(display)
            asleep = api.CGDisplayIsAsleep(display)
            if online != 1 or builtin not in (0, 1) or asleep not in (0, 1):
                result["displayReason"] = "invalidOrOfflineDisplay"
                return result
            if builtin:
                builtins.append(asleep)
            else:
                external += 1
        after = (ctypes.c_uint32 * 32)()
        after_count = ctypes.c_uint32()
        if (api.CGGetOnlineDisplayList(32, after, ctypes.byref(after_count)) != 0
                or after_count.value != count.value
                or sorted(after[:after_count.value]) != sorted(identifiers)):
            result["displayReason"] = "topologyChanged"
            return result
        result["externalOnlineDisplays"] = external
        if len(builtins) != 1:
            result["displayReason"] = "internalDisplayMissing" if not builtins else "internalDisplayAmbiguous"
            return result
        result.update(internalDisplay="asleep" if builtins[0] else "awake",
                      displayAvailability="available", displayReason="uncalibratedPublicReading")
        return result
    except (OSError, AttributeError):
        return result
    finally:
        elapsed = time.monotonic() - started
        result["displayReadElapsedSeconds"] = elapsed
        if not 0 <= elapsed <= 0.2:
            result.update(internalDisplay="unknown", externalOnlineDisplays=None,
                          displayAvailability="error", displayReason="slowOrInvalidRead")


def snapshot():
    result = {"utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "monotonic": time.monotonic(), "powerActuation": False,
              "backendOwner": "notEstablished", "lid": None}
    result.update(display_snapshot())
    try:
        data = subprocess.check_output(["/usr/sbin/ioreg", "-a", "-r", "-n", "IOPMrootDomain", "-d", "1"], timeout=2)
        rows = plistlib.loads(data)
        value = rows[0].get("AppleClamshellState") if rows else None
        result["lid"] = "closed" if value is True else "open" if value is False else "unknown"
        result["source"] = "IOPMrootDomain.AppleClamshellState"
    except (subprocess.SubprocessError, OSError, ValueError, plistlib.InvalidFileException):
        result["lid"] = "unknown"
        result["availability"] = "error"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--duration", type=float, default=7200)
    parser.add_argument("--interval", type=float, default=30)
    args = parser.parse_args()
    if not 1 <= args.duration <= 28800 or not 1 <= args.interval <= 300:
        parser.error("duration must be 1…28800s; interval 1…300s")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    end = time.monotonic() + args.duration
    with os.fdopen(descriptor, "w") as stream:
        while True:
            stream.write(json.dumps(snapshot(), sort_keys=True) + "\n")
            stream.flush()
            remaining = end - time.monotonic()
            if remaining <= 0:
                break
            time.sleep(min(args.interval, remaining))


if __name__ == "__main__":
    main()
