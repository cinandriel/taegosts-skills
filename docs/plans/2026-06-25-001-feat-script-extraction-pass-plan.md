---
title: "feat: Script extraction pass — maximize token savings across all skills"
type: feat
status: pending
date: 2026-06-25
---

# Script Extraction Pass Implementation Plan

## Summary

Convert repeatable mechanical steps across all skills into single-use helper scripts. Scripts consume zero tokens, run identically every time, and never hallucinate. Each script does one thing well (single-use principle). An orchestrator script may compose multiple helpers when the task is "run these checks and aggregate results."

## Problem Frame

The skills currently ask the LLM to perform mechanical tasks — grepping files, parsing YAML, checking API responses, classifying documents by content signals. These tasks burn tokens on every invocation and produce inconsistent results (the LLM might miss a file, format output differently, or hallucinate a grep pattern). The 10 findings from the Honcho deployment and the PR 3 feedback both identified steps that should be scripted.

## Requirements

| ID | Requirement |
|----|-------------|
| R1 | Every script is single-purpose — one clear input, one clear output |
| R2 | Scripts output structured text (JSON or TSV) that skills can parse without interpretation |
| R3 | Scripts are self-contained — no shared state, no temp files between runs |
| R4 | Each script has a `--help` flag describing usage, inputs, and outputs |
| R5 | Scripts exit 0 on success/findings, exit 1 on error, exit 2 on no-findings (for grep-based scripts) |
| R6 | Scripts are placed in the skill's `scripts/` directory (not a global scripts dir) |
| R7 | Skills reference scripts by relative path from the skill directory |
| R8 | Scripts that call the GitHub API accept `--repo` and `--pr` arguments |

## Key Technical Decisions

### KTD1: Script language — bash for grep/parse, python for API/JSON

Bash scripts for file-scanning tasks (grep, find, diff). Python scripts for GitHub API calls and JSON processing. Bash is faster for simple file operations; Python handles JSON serialization and API pagination cleanly.

### KTD2: Output format — JSON for structured data, plain text for grep results

Scripts that return structured findings (lists of issues, match results) output JSON. Scripts that return file paths or simple matches output newline-delimited plain text. This keeps the skill's consumption logic simple — either `jq` for JSON or line-by-line for text.

### KTD3: Convention cross-check uses the solutions index, not raw grep

Instead of grepping all `docs/solutions/` files on every run, the convention cross-check script reads a pre-built index (generated once, stored as a temp file). The index maps resource types to solution doc paths. This is faster and more reliable than raw grep.

### KTD4: Scripts are tested by running them against the homelab-k8s repo

The homelab-k8s repo has real solution docs, real NetworkPolicies, real ConfigMaps. Scripts are validated by running them against that repo and checking output. No synthetic test fixtures needed.

## Implementation Units

### U1: git-state.sh — unified git state snapshot

**Goal:** Provide a single script that outputs branch, base branch, dirty files, untracked files, and recent commits. Multiple skills currently derive this independently.

**Files:**
- Create: `skills/ce-work/scripts/git-state.sh`

**Approach:**
```bash
#!/bin/bash
# Output JSON with: current_branch, default_branch, dirty_files[], untracked_files[], recent_commits[]
```

**Verification:** Run against any git repo, verify JSON output parses cleanly.

---

### U2: cross-check-conventions.sh — grep solutions for matching patterns

**Goal:** Given a list of keywords (resource types, components), grep `docs/solutions/` for matching docs and return paths + relevant excerpts.

**Files:**
- Create: `skills/ce-work/scripts/cross-check-conventions.sh`

**Approach:**
```bash
#!/bin/bash
# Input: keywords as arguments (e.g., "valkey" "networkpolicy" "rabbitmq")
# Output: JSON array of {keyword, path, excerpt} matches
# Searches: docs/solutions/ recursively, case-insensitive
```

**Verification:** Run against homelab-k8s with keywords "valkey", "networkpolicy", "rabbitmq". Expect matches in solutions/conventions/ and solutions/runtime-errors/.

---

### U3: detect-missing-artifacts.sh — diff plan files against reference app

**Goal:** Given a plan's file list and a reference app directory, output files present in the reference but absent from the plan.

**Files:**
- Create: `skills/ce-work/scripts/detect-missing-artifacts.sh`

**Approach:**
```bash
#!/bin/bash
# Input: --plan-files <file> (newline-delimited list) --reference-dir <path>
# Output: JSON array of {file, status} where status is "missing" or "present"
```

**Verification:** Run with a partial file list against `apps/plane/` in homelab-k8s.

---

### U4: find-precommit-hook.sh — locate validation scripts

**Goal:** Find the pre-commit hook and list available validation scripts.

**Files:**
- Create: `skills/ce-work/scripts/find-precommit-hook.sh`

**Approach:**
```bash
#!/bin/bash
# Output: JSON with {hook_path, scripts[]}
# Checks: .git/hooks/pre-commit, .githooks/pre-commit, then follows symlinks
```

**Verification:** Run in homelab-k8s, expect to find the validation suite.

---

### U5: classify-document.sh — detect document type from content signals

**Goal:** Classify a document as `requirements` or `plan` based on content signals (frontmatter fields, section headings, ID patterns). Saves the LLM from reading the entire document just to classify it.

**Files:**
- Create: `skills/ce-doc-review/scripts/classify-document.sh`

**Approach:**
```bash
#!/bin/bash
# Input: document path
# Output: JSON with {type: "requirements"|"plan", signals: [...], confidence: "high"|"medium"|"low"}
# Checks: frontmatter fields, section headings, ID patterns (R1/U1/etc.)
```

**Verification:** Run against a plan doc and a brainstorm doc in homelab-k8s.

---

### U6: check-credentials-in-configmaps.sh — grep ConfigMap YAML for secrets

**Goal:** Scan ConfigMap YAML files for patterns that look like credentials (passwords, API keys, tokens).

**Files:**
- Create: `skills/ce-doc-review/scripts/check-credentials-in-configmaps.sh`

**Approach:**
```bash
#!/bin/bash
# Input: directory path (default: current directory)
# Output: JSON array of {file, line, match, severity}
# Patterns: password, secret, key, token, api_key, credential
# Excludes: comments, documentation references
```

**Verification:** Run against homelab-k8s ConfigMaps, expect to catch the Valkey auth pattern incident.

---

### U7: check-networkpolicy-selectors.sh — detect namespaceSelector issues

**Goal:** Parse NetworkPolicy files for `namespaceSelector` usage and flag potential MetalLB hairpin issues.

**Files:**
- Create: `skills/ce-doc-review/scripts/check-networkpolicy-selectors.sh`

**Approach:**
```bash
#!/bin/bash
# Input: directory path
# Output: JSON array of {file, issue, selector_type, recommendation}
# Checks: namespaceSelector for external services, ipBlock for MetalLB IPs,
#          missing egress rules for DNS
```

**Verification:** Run against homelab-k8s NetworkPolicies.

---

### U8: detect-diff-scope.sh — determine what changed and which reviewers apply

**Goal:** Analyze a git diff and output which code-review personas are relevant based on file types and change patterns.

**Files:**
- Create: `skills/ce-code-review/scripts/detect-diff-scope.sh`

**Approach:**
```bash
#!/bin/bash
# Input: base ref (default: main)
# Output: JSON with {files: [], personas: [], has_migrations: bool, has_tests: bool}
# Persona selection: security (auth files), performance (DB queries), etc.
```

**Verification:** Run in homelab-k8s, check persona recommendations against known patterns.

---

### U9: validate-findings-json.sh — validate review output against schema

**Goal:** Validate that a JSON findings file conforms to `findings-schema.json`.

**Files:**
- Create: `skills/ce-code-review/scripts/validate-findings-json.sh`

**Approach:**
```bash
#!/bin/bash
# Input: findings JSON file path
# Output: validation result (pass/fail + errors)
# Uses: python3 json.schema or jq for validation
```

**Verification:** Run against a valid and invalid findings file.

---

### U10: detect-overlap.sh — grep existing solutions for similar content

**Goal:** Given a proposed solution title and tags, search existing solutions for overlap.

**Files:**
- Create: `skills/ce-compound/scripts/detect-overlap.sh`

**Approach:**
```bash
#!/bin/bash
# Input: --title <string> --tags <comma-separated> --solutions-dir <path>
# Output: JSON with {matches: [{path, overlap_score, matching_dimensions}]}
```

**Verification:** Run against homelab-k8s solutions with a title similar to an existing doc.

---

### U11: detect-file-status.sh — missing vs awaiting manual step

**Goal:** Given a file path, determine if it exists on disk, is gitignored, or is truly missing.

**Files:**
- Create: `skills/verify-implementation/scripts/detect-file-status.sh`

**Approach:**
```bash
#!/bin/bash
# Input: file path
# Output: JSON with {path, status: "committed"|"on_disk_gitignored"|"missing"}
```

**Verification:** Run against a gitignored file and a missing file.

---

### U12: fetch-issue-comments.sh — fetch PR issue-level comments

**Goal:** Fetch comments posted directly on a PR (not threaded inline review comments).

**Files:**
- Create: `skills/pr-fix-findings/scripts/fetch-issue-comments.sh`

**Approach:**
```bash
#!/bin/bash
# Input: --repo owner/repo --pr number
# Output: JSON array of {id, user, body, created_at}
# Uses: gh api repos/{owner}/{repo}/issues/{pr}/comments
```

**Verification:** Run against a PR with known issue-level comments.

---

### U13: check-thread-resolution.sh — check PR review thread resolution status

**Goal:** Check which review threads on a PR are resolved vs unresolved.

**Files:**
- Create: `skills/pr-fix-findings/scripts/check-thread-resolution.sh`

**Approach:**
```bash
#!/bin/bash
# Input: --repo owner/repo --pr number
# Output: JSON array of {thread_id, is_resolved, comments: [...]}
# Uses: gh api graphql with reviewThreads query
```

**Verification:** Run against a PR with both resolved and unresolved threads.

---

## Scope Boundaries

- **Not in this PR:** Config personas (PR 7) or the rename (PR 8). Those are separate PRs.
- **Not in this PR:** Modifying skills to call the scripts. This PR creates the scripts only. A follow-up PR wires them into the skills.
- **Not in this PR:** Tests for the scripts. The homelab-k8s repo is the test bed — scripts are validated by running them against real data.

## Verification

After all scripts are created:
1. Run each script against the homelab-k8s repo (or a test repo) and verify output
2. Verify all scripts have `--help` flags
3. Verify all scripts exit with correct exit codes
4. Verify output is valid JSON (for JSON-outputting scripts)
