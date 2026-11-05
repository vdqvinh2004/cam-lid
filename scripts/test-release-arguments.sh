#!/bin/sh
# Checks the refusal paths of scripts/release.sh (spec 017, T030). Each case exits before any build starts, so this
# is quick and never touches dist/. Run: sh scripts/test-release-arguments.sh
set -u
cd "$(dirname "$0")/.."
status=0
check() { # check <wanted exit code> <description> <command...>
  want="$1"; what="$2"; shift 2
  out="$("$@" 2>&1)"; got=$?
  if [ "$got" -eq "$want" ]; then
    echo "ok    $what"
  else
    echo "FAIL  $what (exit $got, wanted $want)"
    echo "$out" | sed 's/^/      /'
    status=1
  fi
}
check 1 "an ad-hoc build is refused without --adhoc" env -u CAMLID_SIGN_IDENTITY sh scripts/release.sh
check 2 "--adhoc conflicts with an identity" env CAMLID_SIGN_IDENTITY=test sh scripts/release.sh --adhoc
check 2 "an unknown option is rejected" env -u CAMLID_SIGN_IDENTITY sh scripts/release.sh --bogus
check 2 "a bad version is rejected" env CAMLID_SIGN_IDENTITY=test sh scripts/release.sh not-a-version
exit $status
