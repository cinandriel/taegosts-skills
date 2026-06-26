#!/usr/bin/env bash
# verify-scripts.sh — Pre-commit gate for scripts
# Runs all validation checks in one pass. Use before committing.
#
# Usage:
#   verify-scripts.sh [dir]           # verify all .sh and .py in dir
#   verify-scripts.sh --file path     # verify a single file
#   verify-scripts.sh --all           # verify scripts/ and skills/*/scripts/
#   verify-scripts.sh --help
#
# Checks per file:
#   .sh files: bash -n, control chars, --help flag, executable
#   .py files: python3 -m py_compile, control chars, --help flag, executable
#
# Exit codes: 0 (all pass), 1 (one or more failures)

set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: verify-scripts.sh [dir|--file path|--all]"
  echo ""
  echo "Pre-commit gate for scripts. Runs all validation checks."
  echo ""
  echo "Checks: syntax, control characters, --help flag, executable bit"
  echo "Exit codes: 0 (all pass), 1 (failures)"
  exit 0
fi

total_files=0
total_failures=0
failures=()

check_file() {
  local f="$1"
  local name=$(basename "$f")
  local file_failures=0

  if [[ "$f" == *.sh ]]; then
    # bash -n syntax check
    if ! bash -n "$f" 2>/dev/null; then
      failures+=("$name: bash syntax error")
      file_failures=$((file_failures + 1))
    fi
  elif [[ "$f" == *.py ]]; then
    # Python syntax check
    if ! python3 -m py_compile "$f" 2>/dev/null; then
      failures+=("$name: Python syntax error")
      file_failures=$((file_failures + 1))
    fi
  else
    # Unsupported extension — skip
    return
  fi

  # Control character check (both .sh and .py)
  # cat -A outputs caret notation (^A for \x01, ^H for \x08, etc.)
  if cat -A "$f" | grep -qE '\^[A-H\]'; then
    failures+=("$name: control characters found")
    file_failures=$((file_failures + 1))
  fi

  # Executable check
  if [[ ! -x "$f" ]]; then
    failures+=("$name: not executable")
    file_failures=$((file_failures + 1))
  fi

  # --help flag check
  if ! grep -q '\-\-help' "$f" 2>/dev/null; then
    failures+=("$name: missing --help flag")
    file_failures=$((file_failures + 1))
  fi

  total_files=$((total_files + 1))
  total_failures=$((total_failures + file_failures))
}

# Determine what to check
if [[ "${1:-}" == "--all" ]]; then
  # Use script location as repo root, not CWD
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

  files=()
  [[ -d "$REPO_ROOT/scripts" ]] && while IFS= read -r f; do files+=("$f"); done < <(find "$REPO_ROOT/scripts" -name "*.sh" -o -name "*.py" | sort)
  [[ -d "$REPO_ROOT/skills" ]] && while IFS= read -r f; do files+=("$f"); done < <(find "$REPO_ROOT/skills" -path "*/scripts/*.sh" -o -path "*/scripts/*.py" | sort)
elif [[ "${1:-}" == "--file" ]]; then
  files=("$2")
elif [[ -d "${1:-.}" ]]; then
  files=()
  while IFS= read -r f; do files+=("$f"); done < <(find "${1:-.}" \( -name "*.sh" -o -name "*.py" \) | sort)
else
  echo "verify-scripts.sh: no files to check" >&2
  exit 1
fi

echo "=== verify-scripts.sh: checking ${#files[@]} files ==="

for f in "${files[@]}"; do
  check_file "$f"
done

echo ""
echo "=== Results: $total_files files checked, ${#failures[@]} failures ==="

if [[ ${#failures[@]} -gt 0 ]]; then
  for f in "${failures[@]}"; do
    echo "  FAIL: $f"
  done
  exit 1
fi

echo "All checks passed."
exit 0
