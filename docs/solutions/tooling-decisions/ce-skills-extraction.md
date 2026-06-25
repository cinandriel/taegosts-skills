# CE Skills Extraction — 2026-06-24

## Decision

Extract 9 skills from [EveryInc/compound-engineering-plugin](https://github.com/EveryInc/compound-engineering-plugin) into our own repo for customization.

## Context

The homelab-k8s plan (2026-06-23-006) identified 10 findings against the CE plugin that require skill-level changes. We can't PR those changes upstream yet — they're specific to our DevOps/k8s workflow. Extracting the skills lets us iterate locally while tracking upstream for future convergence.

## Motivating Findings (from homelab-k8s plan)

1. ce-work doesn't cross-check conventions before dispatching
2. ce-work artifact detection is fragile (looks for specific filenames)
3. ce-work no pre-commit validation before claiming done
4. ce-doc-review missing domain-specific security/networking personas
5. ce-doc-review no convention cross-check during review
6. ce-compound subagent contract violation (passes wrong args to /ce-work)
7. ce-code-review has platform-specific personas not relevant to k8s workflow
8. ce-plan includes Slack-specific agents we don't use
9. ce-brainstorm includes visual probe server we don't need
10. ce-compound includes session historian scripts we don't need

## Skills Extracted

| Skill | Purpose | Dependencies |
|-------|---------|-------------|
| ce-work | Plan execution and implementation | ce-plan, ce-debug |
| ce-plan | Planning and architecture | ce-brainstorm |
| ce-doc-review | Document review with persona lenses | None |
| ce-code-review | Code review with dynamic personas | None |
| ce-compound | Solution documentation capture | ce-work, ce-debug |
| ce-debug | Debugging workflow | None |
| ce-brainstorm | Requirements brainstorming | None |
| ce-commit | Commit workflow | None |
| ce-commit-push-pr | Commit + PR creation | None |

## Dependency Chain

```
ce-brainstorm -> ce-plan -> ce-work -> ce-compound
                       \\            /
                       ce-debug
```

- ce-brainstorm feeds requirements into ce-plan
- ce-plan produces plans consumed by ce-work
- ce-work uses ce-debug for error investigation
- ce-compound captures solutions using ce-work + ce-debug
- ce-doc-review, ce-code-review, ce-commit, ce-commit-push-pr are independent

## What Was Removed

### From ce-code-review (3 persona files)
- `references/personas/swift-ios-reviewer.md` — iOS-specific, not relevant to k8s
- `references/personas/julik-frontend-races-reviewer.md` — Frontend race conditions, not relevant
- `references/personas/agent-native-reviewer.md` — Claude Code meta-reviewer, platform-specific

### From ce-plan (2 agent files)
- `references/agents/slack-researcher.md` — No Slack integration in our workflow
- `references/agents/agent-native-planning-strategist.md` — Platform meta-agent, not needed

### From ce-brainstorm (3 files)
- `references/agents/slack-researcher.md` — No Slack integration
- `scripts/visual-probe-server.js` — Node.js visual probe, not needed
- `references/visual-probes.md` — Companion to the visual probe server

### From ce-compound (1 file)
- `references/agents/session-historian.md` — Session history scripts, Claude Code specific

### NOT removed from ce-doc-review
All 7 personas in ce-doc-review are relevant to Mike's DevOps/k8s workflow and were kept.

## PR Plan

1. **PR 1 (this)** — Pure extraction with unused parts removed, no behavior changes
2. **PR 2** — ce-work fixes (convention cross-check, artifact detection, pre-commit validation)
3. **PR 3** — ce-doc-review fixes (domain-specific security/networking, convention cross-check at review)
4. **PR 4** — ce-compound fix (subagent contract violation)
5. **PR 5** — Existing skill fixes (verify-implementation, pr-fix-findings)

## Status

- [x] Skills extracted
- [x] Unused files removed
- [ ] Platform fallback scaffolding removed (PR 2+)
- [ ] Homelab-specific fixes applied (PR 2-4)
- [ ] Upstream convergence plan drafted
