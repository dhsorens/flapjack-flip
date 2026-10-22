#!/usr/bin/env bash
# Check criteria 1-4 of PROMPT.md. Exit code 0 iff all of them hold.
set -uo pipefail
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $*"; exit 1; }

echo "== 4. frozen files"
shasum -a 256 --quiet -c FROZEN.sha256 || fail "frozen files changed"

echo "== 1. build"
log=$(lake build 2>&1) || { echo "$log" | tail -30; fail "lake build failed"; }
if echo "$log" | grep -q "warning:"; then
  echo "$log" | grep -A3 "warning:"; fail "build has warnings"
fi

echo "== 2. axioms"
axioms=$(lake env lean Acceptance.lean 2>&1) || { echo "$axioms"; fail "Acceptance.lean"; }
echo "$axioms"
used=$(echo "$axioms" | tr -d '[],\n' | sed 's/.*depends on axioms://')
for ax in $used; do
  case "$ax" in
    propext|Classical.choice|Quot.sound) ;;
    *) fail "axiom not allowed: $ax" ;;
  esac
done

echo "== 3. visible tests"
lake exe flip-check tests || fail "not every visible test passes"

echo "ALL CRITERIA 1-4 PASS"
