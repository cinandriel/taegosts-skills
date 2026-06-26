#!/usr/bin/env bash
# verify-fix.sh — Confirm that a file edit actually landed
# Solves the #1 cause of carry-over findings: silent str.replace/sed failures.
#
# Usage:
#   verify-fix.sh --file path --should-contain "text"       # must be present
#   verify-fix.sh --file path --should-not-contain "text"   # must be absent
#   verify-fix.sh --file path --should-match "regex"        # regex match
#   verify-fix.sh --file path --no-control-chars            # control char check
#   verify-fix.sh --file path --valid-bash                  # bash -n syntax check
#   verify-fix.sh --file path --valid-json                  # python3 -m json.tool
#   verify-fix.sh --file path --is-executable               # chmod +x check
#   verify-fix.sh --help
#
# Exit codes: 0 (all checks pass), 1 (one or more failures)

set -euo pipefail

failures=()

usage() {
  echo "Usage: verify-fix.sh --file <path> [checks...]"
  echo ""
  echo "Checks:"
  echo "  --should-contain TEXT      File must contain TEXT"
  echo "  --should-not-contain TEXT  File must NOT contain TEXT"
  echo "  --should-match REGEX       File must match REGEX"
  echo "  --no-control-chars         No control characters"
  echo "  --valid-bash               bash -n syntax check"
  echo "  --valid-json               python3 -m json.tool check"
  echo "  --is-executable            File must be executable"
  echo ""
  echo "Exit codes: 0 (pass), 1 (failure)"
  exit 0
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
fi

filepath=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) filepath="$2"; shift 2 ;;
    --should-contain)
      text="$2"
      if ! grep -qF "$text" "$filepath" 2>/dev/null; then
        failures+=("should-contain: '$text' not found in $filepath")
      fi
      shift 2 ;;
    --should-not-contain)
      text="$2"
      if grep -qF "$text" "$filepath" 2>/dev/null; then
        failures+=("should-not-contain: '$text' still present in $filepath")
      fi
      shift 2 ;;
    --should-match)
      pattern="$2"
      if ! grep -qE "$pattern" "$filepath" 2>/dev/null; then
        failures+=("should-match: pattern '$pattern' not found in $filepath")
      fi
      shift 2 ;;
    --no-control-chars)
      # cat -A outputs caret notation (^A for \x01, ^H for \x08, etc.)
      # Search for caret-notation control chars, not raw bytes
      if cat -A "$filepath" | grep -qE '\^[A-H\]'; then
        failures+=("no-control-chars: control characters found in $filepath")
      fi
      shift ;;
    --valid-bash)
      if ! bash -n "$filepath" 2>/dev/null; then
        failures+=("valid-bash: syntax error in $filepath")
      fi
      shift ;;
    --valid-json)
      if ! python3 -m json.tool "$filepath" > /dev/null 2>&1; then
        failures+=("valid-json: invalid JSON in $filepath")
      fi
      shift ;;
    --is-executable)
      if [[ ! -x "$filepath" ]]; then
        failures+=("is-executable: $filepath is not executable")
      fi
      shift ;;
    *)
      echo "verify-fix.sh: unknown flag '$1'" >&2
      echo "Run 'verify-fix.sh --help' for usage" >&2
      exit 1
      ;;
  esac
done

if [[ ${#failures[@]} -eq 0 ]]; then
  echo "PASS: all checks passed for $filepath"
  exit 0
else
  echo "FAIL: ${#failures[@]} check(s) failed for $filepath"
  for f in "${failures[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
