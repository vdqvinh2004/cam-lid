#!/bin/sh
# Checks scripts/check-helper-version.sh on throwaway inputs, so the repository's own helper version is untouched
# (spec 019 FR-003). Run: sh scripts/test-check-helper-version.sh
set -eu
cd "$(dirname "$0")/.."
SCRIPT="scripts/check-helper-version.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/src"
echo "let helper = 1" > "$work/src/main.swift"
printf 'public enum PowerHelperVersion {\n    public static let current = 1\n}\n' > "$work/version.swift"
export CAMLID_HELPER_SOURCES="$work/src" CAMLID_HELPER_VERSION_FILE="$work/version.swift"
export CAMLID_HELPER_BASELINE="$work/baseline"
status=0
check() { # check <wanted exit code> <description> [script arguments...]
  want="$1"; what="$2"; shift 2
  set +e
  out="$(sh "$SCRIPT" "$@" 2>&1)"
  got=$?
  set -e
  if [ "$got" -eq "$want" ]; then
    echo "ok    $what"
  else
    echo "FAIL  $what (exit $got, wanted $want): $out"
    status=1
  fi
}
check 0 "records a baseline" --record
check 0 "unchanged sources pass"
echo "let helper = 2" > "$work/src/main.swift"
check 1 "changed sources without a version bump fail"
printf 'public enum PowerHelperVersion {\n    public static let current = 2\n}\n' > "$work/version.swift"
check 0 "changed sources with a version bump pass"
check 0 "recording the bumped version" --record
printf 'public enum PowerHelperVersion {\n    public static let current = 1\n}\n' > "$work/version.swift"
check 1 "a lower version than recorded fails"
exit $status
