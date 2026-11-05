#!/bin/sh
# Guards PowerHelperVersion (spec 019 FR-003, ADR 0005). The helper's sources are fingerprinted, and the baseline
# records the version and fingerprint of the helper last recorded. Changing the sources without raising the version
# fails, because an app that does not ask for a helper reinstall would leave the old helper in place.
# Usage: scripts/check-helper-version.sh            check (exit 0 ok, 1 guard failed, 2 cannot check)
#        scripts/check-helper-version.sh --record   store the current version and fingerprint as the baseline
# The paths can be overridden for tests: CAMLID_HELPER_SOURCES, CAMLID_HELPER_VERSION_FILE, CAMLID_HELPER_BASELINE.
set -eu
cd "$(dirname "$0")/.."
SOURCES="${CAMLID_HELPER_SOURCES:-Packages/CamLidPowerHelper/Sources}"
VERSION_FILE="${CAMLID_HELPER_VERSION_FILE:-Packages/CamLidPowerWire/Sources/CamLidPowerWire/LocalIdentityPins.swift}"
BASELINE="${CAMLID_HELPER_BASELINE:-scripts/helper-version.baseline}"

current_version="$(sed -n 's/^    public static let current = \([0-9][0-9]*\)$/\1/p' "$VERSION_FILE" | head -1)"
if [ -z "$current_version" ]; then
  echo "PowerHelperVersion.current was not found in $VERSION_FILE." >&2
  exit 2
fi
fingerprint="$(find "$SOURCES" -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -d' ' -f1)"

if [ "${1:-}" = "--record" ]; then
  printf 'version=%s\nfingerprint=%s\n' "$current_version" "$fingerprint" > "$BASELINE"
  echo "Recorded helper version $current_version (fingerprint $fingerprint) in $BASELINE."
  exit 0
fi

if [ ! -f "$BASELINE" ]; then
  echo "No baseline at $BASELINE. Run scripts/check-helper-version.sh --record once." >&2
  exit 2
fi
recorded_version="$(sed -n 's/^version=//p' "$BASELINE")"
recorded_fingerprint="$(sed -n 's/^fingerprint=//p' "$BASELINE")"
if [ "$current_version" -lt "$recorded_version" ]; then
  echo "PowerHelperVersion went down, from $recorded_version to $current_version." >&2
  exit 1
fi
if [ "$fingerprint" != "$recorded_fingerprint" ] && [ "$current_version" -eq "$recorded_version" ]; then
  echo "The helper sources changed but PowerHelperVersion is still $current_version." >&2
  echo "Raise it in $VERSION_FILE (ADR 0005), then run scripts/check-helper-version.sh --record." >&2
  exit 1
fi
if [ "$fingerprint" != "$recorded_fingerprint" ]; then
  echo "Helper version $current_version is newer than the recorded one. Record it once the release is cut."
fi
echo "ok: helper version $current_version"
