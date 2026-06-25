---
title: "feat: Script extraction pass — maximize token savings across all skills"
type: feat
status: pending
date: 2026-06-25
origin: docs/plans/2026-06-23-006-chore-skill-improvements-from-honcho-deployment.md
---

# Script Extraction Pass Implementation Plan

## Summary

Convert repeatable mechanical steps across all skills into single-use helper scripts organized in two tiers: shared utilities (repo root) and skill-specific scripts (per-skill). Scripts consume zero tokens, run identically every time, and never hallucinate. Each script does one thing well (single-use principle).

## Problem Frame

A systematic audit of all 12 skills found 143 mechanical steps currently performed by the LLM. Of these, 138 are scriptable and ~65 are high token savings. Many steps are duplicated across skills — git context gathering appears in 6 skills, default branch resolution in 5, PR metadata fetching in 3. Extracting these into shared scripts eliminates both the token cost and the duplication.

## Requirements

| ID | Requirement |
|----|-------------|
| R1 | Every script is single-purpose — one clear input, one clear output |
| R2 | Scripts output structured text (JSON or TSV) that skills can parse without interpretation |
| R3 | Scripts are self-contained — no shared state, no temp files between runs |
| R4 | Each script has a `--help` flag describing usage, inputs, and outputs |
| R5 | Scripts exit 0 on success, exit 1 on error, exit 2 on no-findings (grep-based scripts) |
| R6 | Shared scripts live in `scripts/` at the repo root |
| R7 | Skill-specific scripts live in `skills/<name>/scripts/` |
| R8 | Scripts that call the GitHub API accept `--repo` and `--pr` arguments |
| R9 | Skills reference shared scripts via relative path from repo root |
| R10 | All scripts validate inputs and reject values containing shell metacharacters or path traversal sequences |
| R11 | All tests follow drift-detection philosophy (see Testing section) |

## Key Technical Decisions

### KTD1: Two-tier directory structure

Shared utilities go in `scripts/` at the repo root. Skill-specific scripts go in `skills/<name>/scripts/`. Skills reference shared scripts via `../../scripts/` relative paths. This eliminates duplication — one `git-context.sh` serves 6 skills instead of 6 copies.

### KTD2: Script language — bash for grep/parse, python for API/JSON

Bash scripts for file-scanning tasks (grep, find, diff). Python scripts for GitHub API calls and JSON processing. Bash is faster for simple file operations; Python handles JSON serialization and API pagination cleanly.

### KTD3: Output format — JSON for structured data, plain text for grep results

Scripts that return structured findings (lists of issues, match results) output JSON. Scripts that return file paths or simple matches output newline-delimited plain text. This keeps the skill's consumption logic simple.

### KTD4: Convention cross-check uses a pre-built index

Instead of grepping all `docs/solutions/` files on every run, the `solutions-search.sh` script reads frontmatter from candidate files and returns structured results. Faster and more reliable than raw grep.

### KTD5: API error handling — check auth before calling

All scripts that call the GitHub API must check `gh auth status` before making calls and produce a clear error message on auth failure. No retry logic needed (single-use scripts), but failures must be surfaced, not swallowed.

### KTD6: Git context script is the foundation

`git-context.sh` outputs a single JSON blob with current_branch, default_branch, is_detached, dirty_files, untracked_files, staged_files, recent_commits, has_unpushed, and repo_root. Every skill that currently derives git state independently consumes this instead.

## Implementation Units

### Dependency Graph and Build Order

```
U5 (run-id.sh) ──────────────────────────────┐
U2 (default-branch.sh) ──┐                    │
                          ├── U1 (git-context.sh) ── U7 (detect-diff-scope.sh)
                          │                    │              │
U6 (classify-document.sh) │                    │              └── U13 (select-reviewers.sh)
                          │                    │
U3 (solutions-search.sh) ─┤                    │
U8 (validate-findings-json.sh)                │
                          │                    │
                          └── U4 (pr-metadata.sh)
```

Build order: U5, U2 → U1 → U3, U6, U7, U8 → U4 → U13

### Tier 1: Shared Utilities (scripts/)

These scripts serve multiple skills. They are the foundation — skill-specific scripts may call them.

#### U1: git-context.sh — unified git state snapshot

**Goal:** Single script that outputs all git state as JSON. Replaces inline derivation in 6 skills.

**Files:**
- Create: `scripts/git-context.sh`

**Output:**
```json
{
  "current_branch": "feat/my-branch",
  "default_branch": "main",
  "is_detached": false,
  "dirty_files": ["file1.md"],
  "untracked_files": ["new-file.sh"],
  "staged_files": [],
  "recent_commits": ["abc1234 last commit message"],
  "has_unpushed": true,
  "repo_root": "/path/to/repo"
}
```

**Consumers:** ce-work, ce-commit, ce-commit-push-pr, ce-code-review, ce-debug, verify-implementation

**Note:** U1 calls U2 internally for default_branch resolution. U2 exists as a standalone script for cases that only need the branch name without the full context blob.

---

#### U2: default-branch.sh — resolve default branch with fallbacks

**Goal:** Resolve the default branch using cascading fallbacks. Replaces inline logic in 5 skills.

**Files:**
- Create: `scripts/default-branch.sh`

**Logic:**
1. `git symbolic-ref refs/remotes/origin/HEAD`
2. `git rev-parse --verify origin/main`
3. `git rev-parse --verify origin/master`
4. `gh repo view --json defaultBranchRef`

**Output:** Branch name on stdout (e.g., `main`)

**Consumers:** ce-work, ce-commit, ce-commit-push-pr, ce-code-review (via U1), ce-debug, verify-implementation

---

#### U3: solutions-search.sh — search docs/solutions/ for matching conventions

**Goal:** Given keywords, search `docs/solutions/` frontmatter for matching docs. Returns paths and relevant excerpts.

**Files:**
- Create: `scripts/solutions-search.sh`

**Input:** Keywords as arguments (e.g., `solutions-search.sh valkey networkpolicy rabbitmq`)

**Output:**
```json
[
  {
    "keyword": "valkey",
    "path": "docs/solutions/conventions/honcho-deployment-patterns.md",
    "title": "Honcho Deployment Patterns",
    "excerpt": "Run Valkey/Redis without auth, use NetworkPolicy..."
  }
]
```

**Consumers:** ce-work (Finding 1), ce-doc-review (Finding 8), ce-plan (learnings-researcher), ce-code-review (learnings-researcher)

**Exit codes:** 0 (matches found), 1 (error), 2 (no matches found)

**Excerpt bounds:** Max 200 characters per excerpt, truncated at word boundary

---

#### U4: pr-metadata.sh — fetch PR state and metadata

**Goal:** Fetch PR metadata and state as JSON. Replaces inline `gh pr view` calls in 3 skills.

**Files:**
- Create: `scripts/pr-metadata.sh`

**Input:** `--repo owner/repo --pr number` or `--branch branch-name`

**Output:**
```json
{
  "number": 42,
  "title": "feat: something",
  "state": "OPEN",
  "base": "main",
  "head": "feat/something",
  "head_sha": "abc123",
  "is_cross_repo": false,
  "url": "https://github.com/...",
  "files_count": 5,
  "has_conflicts": false,
  "review_comments": 3,
  "issue_comments": 1
}
```

**Implementation notes:** `--pr` mode uses `gh pr diff --repo` and parses unified diff output. `--branch`/`--base` modes use local `git diff`. `has_migrations` checks for files matching migration path patterns. `has_tests` checks for files matching test/spec patterns.

**Consumers:** ce-code-review, pr-review, pr-fix-findings

---

#### U5: run-id.sh — generate unique run identifier

**Goal:** Generate a timestamped run ID for artifact directories.

**Files:**
- Create: `scripts/run-id.sh`

**Output:** `20260625-143052-a1b2` (date-time-4hex)

**Consumers:** ce-code-review, ce-compound

---

#### U6: classify-document.sh — detect document type from content signals

**Goal:** Classify a document as `requirements` or `plan` based on frontmatter fields, section headings, and ID patterns.

**Files:**
- Create: `scripts/classify-document.sh`

**Input:** Document path

**Output:**
```json
{
  "type": "plan",
  "signals": ["has_implementation_units", "has_u_ids", "frontmatter_type_feat"],
  "confidence": "high"
}
```

**Consumers:** ce-doc-review

---

#### U7: detect-diff-scope.sh — compute diff and determine reviewer scope

**Goal:** Resolve base ref, produce diff, detect scope mode (PR/branch/standalone), and list changed files.

**Files:**
- Create: `scripts/detect-diff-scope.sh`

**Input:** `--base ref` or `--pr number` or `--branch name`

**Output:**
```json
{
  "mode": "pr-remote",
  "base": "main",
  "head": "feat/something",
  "files_changed": ["src/auth.py", "tests/test_auth.py"],
  "has_migrations": false,
  "has_tests": true,
  "diff_line_count": 142
}
```

**Implementation notes:** `--pr` mode uses `gh pr diff --repo` and parses unified diff output. `--branch`/`--base` modes use local `git diff`. `has_migrations` checks for files matching migration path patterns. `has_tests` checks for files matching test/spec patterns.

**Consumers:** ce-code-review

---

#### U8: validate-findings-json.sh — validate findings against schema

**Goal:** Validate that a JSON findings file conforms to `findings-schema.json`.

**Files:**
- Create: `scripts/validate-findings-json.sh`

**Input:** Findings JSON file path

**Output:** Validation result (pass/fail + errors)

**Consumers:** ce-code-review, ce-doc-review

---

### Tier 2: Skill-Specific Scripts (skills/<name>/scripts/)

These scripts serve a single skill. They may call shared scripts from Tier 1.

#### U9: skills/ce-work/scripts/detect-missing-artifacts.sh

**Goal:** Given a plan's file list and a reference app directory, output files present in reference but absent from plan.

**Input:** `--plan-files <file> --reference-dir <path>`

**Output:** JSON array of `{file, status}` where status is `missing` (in reference but not in plan) or `in_plan` (in both). Only `missing` files require action.

---

#### U10: skills/ce-work/scripts/find-precommit-hook.sh

**Goal:** Find the pre-commit hook and list available validation scripts.

**Output:** JSON with `{hook_path, scripts[]}`

---

#### U11: skills/ce-doc-review/scripts/check-credentials-in-configmaps.py

**Goal:** Scan ConfigMap YAML files for patterns that look like credentials.

**Input:** Directory path (default: current directory)

**Output:** JSON array of `{file, line, pattern_type, severity, redacted}` where matched values are masked (e.g., `password: ****`)

**Patterns:** password, secret, key, token, api_key, credential

**Language:** Python (YAML-aware parsing to exclude comments reliably, redact matched values)

**Exit codes:** 0 (credentials found), 1 (error), 2 (no credentials found)

---

#### U12: skills/ce-doc-review/scripts/check-networkpolicy-selectors.sh

**Goal:** Parse NetworkPolicy files for `namespaceSelector` usage and flag potential MetalLB hairpin issues.

**Input:** Directory path

**Output:** JSON array of `{file, issue, selector_type, recommendation}`

---

#### U13: skills/ce-code-review/scripts/select-reviewers.sh

**Goal:** Given a diff scope (from detect-diff-scope.sh), determine which code-review personas are relevant.

**Input:** Files changed list (stdin or file)

**Output:** JSON with `{always_on: [], conditional: [], rationale: {}}`

---

#### U14: skills/ce-compound/scripts/detect-overlap.py

**Goal:** Given a proposed solution title and tags, search existing solutions for overlap.

**Input:** `--title <string> --tags <comma-separated> --solutions-dir <path>`

**Output:** JSON with `{matches: [{path, overlap_score, matching_dimensions}]}`

**Language:** Python (fuzzy string matching for title similarity, tag intersection scoring)

**Scoring algorithm:** (1) Read all solution frontmatter for title + tags. (2) Title similarity via substring/word overlap (0-1). (3) Tag intersection count / total unique tags (0-1). (4) Composite score = 0.6 * title_sim + 0.4 * tag_overlap. (5) Report matches with score > 0.3.

**Exit codes:** 0 (matches found), 1 (error), 2 (no matches found)

---

#### U15: skills/verify-implementation/scripts/detect-file-status.sh

**Goal:** Given a file path, determine if it exists on disk, is gitignored, or is truly missing.

**Input:** File path

**Output:** JSON with `{path, status: "committed"|"on_disk_gitignored"|"missing"}`

---

#### U16: skills/pr-fix-findings/scripts/fetch-issue-comments.sh

**Goal:** Fetch comments posted directly on a PR (not threaded inline).

**Input:** `--repo owner/repo --pr number`

**Output:** JSON array of `{id, user, body, created_at}`

---

#### U17: skills/pr-fix-findings/scripts/check-thread-resolution.sh

**Goal:** Check which review threads on a PR are resolved vs unresolved.

**Input:** `--repo owner/repo --pr number`

**Output:** JSON array of `{thread_id, is_resolved, comments: [...]}`

---

#### U18: skills/pr-review/scripts/post-review.sh [DEFERRED — write-side action]

**Status:** Deferred to PR 6c (write-side automation). U18 is a write action that posts reviews to GitHub — categorically different from the read/compute scripts in this PR.

**Goal:** Build and post a PR review with inline comments.

**Input:** `--repo owner/repo --pr number --review-json <file>`

**Output:** Review URL or error

**Auth:** Uses `gh api` (handles auth internally). Does NOT accept raw token arguments.

---

#### U19: skills/ce-plan/scripts/generate-plan-filename.sh

**Goal:** Generate the next plan filename for today's date by globbing `docs/plans/` and incrementing the sequence number.

**Input:** `--type feat|fix|chore --slug <string>`

**Output:** `2026-06-25-002-feat-my-plan.md`

---

#### U20: skills/ce-plan/scripts/scan-repo-structure.sh

**Goal:** Scan repo root for manifests, config files, and ecosystem indicators. Outputs structured repo profile.

**Output:** JSON with `{ecosystem, monorepo, languages[], frameworks[], config_files[]}`

---

## Consumption Pattern

Skills invoke scripts via relative path from the skill directory:

```bash
# From a skill directory (e.g., skills/ce-work/):
result=$(../../scripts/git-context.sh)
if [ $? -eq 1 ]; then
  echo "Script failed: $result" >&2
fi
```

**Error handling:** Skills must check exit codes. Exit 0 = success, exit 1 = error (log and fall back to inline logic), exit 2 = no-findings (grep-based scripts, not an error). Skills should NOT halt on script failure — they fall back to the inline LLM logic the script was meant to replace.

## Scope Boundaries

- **PR 6a (this PR):** Tier 1 shared utilities only (U1-U8). No dependencies on Tier 2.
- **PR 6b (follow-up):** Tier 2 skill-specific scripts (U9-U20). Depends on Tier 1 being merged.
- **In this PR:** Scripts directory structure and shared utility conventions
- **Not in this PR:** Wiring scripts into skills (follow-up PR)
- **Not in this PR:** Config personas (PR 7) or the rename (PR 8)
- **Not in this PR:** Formal test suites — scripts are validated against homelab-k8s real data

## Testing

Every script has a corresponding test that validates its behavior against known inputs. Tests live in `tests/scripts/` mirroring the script directory structure.

### Test structure

```
tests/
  scripts/
    test-git-context.sh        # tests scripts/git-context.sh
    test-default-branch.sh     # tests scripts/default-branch.sh
    test-solutions-search.sh   # tests scripts/solutions-search.sh
    ...
  skills/
    ce-work/
      test-detect-missing-artifacts.sh
    ...
```

### Drift detection philosophy

When a test fails, the correct response is **investigation, not reflexive repair**:

1. **Read the failure.** What did the script output vs what did the test expect?
2. **Determine the cause.** Three possibilities:
   - **The script is wrong.** It changed behavior or has a bug. Fix the script.
   - **The test is wrong.** The test assumed behavior that was never correct, or the test fixture is stale. Fix the test.
   - **The world changed.** The script's input environment changed (new file format, new API response shape, new git behavior). Update both script AND test to match the new reality.
3. **Document the decision.** The commit message must state WHY the fix targets the script, the test, or both. "Fixed the test" is not acceptable. "Test assumed exit code 2 for empty results but script convention changed to exit 0 — updated test to match" is.
4. **Never auto-fix.** Do not run a script, see a test fail, and immediately change the test to make it pass. That defeats the purpose of drift detection.

### Test conventions

- Tests are bash scripts that run the target script with known inputs and assert on exit code + output structure
- Each test has a `# Given` / `# When` / `# Then` comment structure
- Tests use temporary directories for isolation (`mktemp -d`)
- Tests clean up on exit (`trap cleanup EXIT`)
- Tests that need a git repo create one in the temp dir
- Tests that need GitHub API use mock responses (fixture files), not live API calls

## Verification

After all scripts are created:
1. Run each shared script against a git repo and verify JSON output
2. Run skill-specific scripts against homelab-k8s where applicable
3. Verify all scripts have `--help` flags
4. Verify all scripts exit with correct exit codes
5. Verify output is valid JSON (for JSON-outputting scripts)
6. Verify shared scripts are callable from skill script directories via relative path (path resolves, not that skills invoke them)
7. Verify every script has a corresponding test in `tests/scripts/`
8. Run all tests and verify they pass

## Token Savings Estimate

| Tier | Scripts | Estimated tokens saved per invocation |
|------|---------|--------------------------------------|
| Shared (U1-U8) | 8 | ~2000-4000 tokens (git context alone saves ~500 per skill, used by 6 skills) |
| Skill-specific (U9-U20) | 12 | ~500-1500 tokens per skill invocation |
| **Total** | **20** | **~5000-8000 tokens per full skill workflow** |
