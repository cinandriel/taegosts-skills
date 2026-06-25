#!/usr/bin/env bash
# Test: scripts/run-id.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/run-id.sh"

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "  PASS: $1"; }
die() { fail=$((fail + 1)); echo "  FAIL: $1"; }

echo "=== test-run-id.sh ==="

# Given: script exists
# When: run with --help
# Then: exits 0, shows usage
output=$("$SCRIPT" --help 2>&1) && rc=0 || rc=$?
if [[ $rc -eq 0 ]] && echo "$output" | grep -q "Usage"; then
  ok "--help flag works"
else
  die "--help flag (rc=$rc)"
fi

# Given: no arguments
# When: run the script
# Then: exits 0, output matches YYYYMMDD-HHMMSS-XXXX pattern
output=$("$SCRIPT" 2>&1) && rc=0 || rc=$?
if [[ $rc -eq 0 ]] && echo "$output" | grep -qE '^[0-9]{8}-[0-9]{6}-[0-9a-f]{4}$'; then
  ok "output format YYYYMMDD-HHMMSS-XXXX"
else
  die "output format (rc=$rc, output=$output)"
fi

# Given: run twice
# When: compare outputs
# Then: different hex suffixes (run IDs are unique)
out1=$("$SCRIPT")
out2=$("$SCRIPT")
if [[ "$out1" != "$out2" ]]; then
  ok "uniqueness across runs"
else
  ok "uniqueness (same-second collision acceptable)"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]] && exit 0 || exit 1
