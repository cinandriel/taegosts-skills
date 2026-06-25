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

## Key Technical Decisions

### KTD1: Two-tier directory structure

Shared utilities go in `scripts/` at the repo root. Skill-specific scripts go in `skills/<name>/scripts/`. Skills reference shared scripts via `../../scripts/` relative paths. This eliminates duplication — one `git-context.sh` serves 6 skills instead of 6 copies.

### KTD2: Script language — bash for grep/parse, python for API/JSON

Bash scripts for file-scanning tasks (grep, find, diff). Python scripts for GitHub API calls and JSON processing. Bash is faster for simple file operations; Python handles JSON serialization and API pagination cleanly.

### KTD3: Output format — JSON for structured data, plain text for grep results

Scripts that return structured findings (lists of issues, match results) output JSON. Scripts that return file paths or simple matches output newline-delimited plain text. This keeps the skill's consumption logic simple.

### KTD4: Convention cross-check uses a pre-built index

Instead of grepping all `docs/solutions/` files on every run, the `solutions-search.sh` script reads frontmatter from candidate files and returns structured results. Faster and more reliable than raw grep.

### KTD5: Git context script is the foundation

`git-context.sh` outputs a single JSON blob with branch, default_branch, dirty_files, untracked_files, recent_commits, staged_files, and has_unpushed. Every skill that currently derives git state independently consumes this instead.

## Implementation Units

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

**Consumers:** ce-work, ce-commit, ce-commit-push-pr, ce-debug, verify-implementation

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

**Output:** JSON array of `{file, status}` where status is `missing` or `present`

---

#### U10: skills/ce-work/scripts/find-precommit-hook.sh

**Goal:** Find the pre-commit hook and list available validation scripts.

**Output:** JSON with `{hook_path, scripts[]}`

---

#### U11: skills/ce-doc-review/scripts/check-credentials-in-configmaps.sh

**Goal:** Scan ConfigMap YAML files for patterns that look like credentials.

**Input:** Directory path (default: current directory)

**Output:** JSON array of `{file, line, match, severity}`

**Patterns:** password, secret, key, token, api_key, credential (excluding comments)

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

#### U14: skills/ce-compound/scripts/detect-overlap.sh

**Goal:** Given a proposed solution title and tags, search existing solutions for overlap.

**Input:** `--title <string> --tags <comma-separated>`

**Output:** JSON with `{matches: [{path, overlap_score, matching_dimensions}]}`

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

#### U18: skills/pr-review/scripts/post-review.sh

**Goal:** Build and post a PR review with inline comments.

**Input:** `--repo owner/repo --pr number --review-json <file>`

**Output:** Review URL or error

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

## Scope Boundaries

- **In this PR:** All 20 scripts (8 shared + 12 skill-specific)
- **In this PR:** Scripts directory structure and shared utility conventions
- **Not in this PR:** Wiring scripts into skills (follow-up PR)
- **Not in this PR:** Config personas (PR 7) or the rename (PR 8)
- **Not in this PR:** Formal test suites — scripts are validated against homelab-k8s real data

## Verification

After all scripts are created:
1. Run each shared script against a git repo and verify JSON output
2. Run skill-specific scripts against homelab-k8s where applicable
3. Verify all scripts have `--help` flags
4. Verify all scripts exit with correct exit codes
5. Verify output is valid JSON (for JSON-outputting scripts)
6. Verify shared scripts are callable from skill script directories via relative path

## Token Savings Estimate

| Tier | Scripts | Estimated tokens saved per invocation |
|------|---------|--------------------------------------|
| Shared (U1-U8) | 8 | ~2000-4000 tokens (git context alone saves ~500 per skill, used by 6 skills) |
| Skill-specific (U9-U20) | 12 | ~500-1500 tokens per skill invocation |
| **Total** | **20** | **~5000-8000 tokens per full skill workflow** |
