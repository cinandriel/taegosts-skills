#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/pr-metadata.sh"
pass=0 fail=0

echo "=== U4: pr-metadata.sh ==="

# Test: --help
output=$("$SCRIPT" --help 2>&1)
if echo "$output" | grep -q "Usage:"; then echo "PASS: --help"; pass=$((pass + 1))
else echo "FAIL: --help"; fail=$((fail + 1)); fi

# Test: missing args
output=$("$SCRIPT" 2>&1 || true)
if echo "$output" | grep -q "required"; then echo "PASS: rejects missing args"; pass=$((pass + 1))
else echo "FAIL: should reject missing args"; fail=$((fail + 1)); fi

# Test: missing --pr
output=$("$SCRIPT" --repo owner/repo 2>&1 || true)
if echo "$output" | grep -q "required"; then echo "PASS: rejects missing --pr"; pass=$((pass + 1))
else echo "FAIL: should reject missing --pr"; fail=$((fail + 1)); fi

echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]] && exit 0 || exit 1
