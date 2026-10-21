---
name: best-practices-audit
description: Audit a project against best-practice rulesets (JavaScript project setup, testing guidelines, etc) and report violations with fixes. 
disable-model-invocation: true
---

# Best-practices audit

Scan a project against small, focused rulesets and report only violations.

## 1. Pick rulesets

Detect the stack from marker files in the project root (and workspace packages if it's a monorepo). Read **only** the matching reference files.

| Marker | Reference file |
|---|---|
| `package.json` | `references/js-project-setup.md` |
| `playwright.config.*`, `vitest.config.*`, `jest.config.*`, or `test`/`e2e` scripts in `package.json` | `references/testing.md` |

If the user names a scope ("only testing", "just `apps/web`"), restrict to it.

## 2. Check rules

Each rule has an ID, a severity, a check type and a "how to check" hint.

- `mechanical`: verify with file listings, grep or reading one config file. Don't open source files.
- `judgment`: open only the files the hint points to.

Never read the whole repo. Use glob/grep to find what a rule needs.

### Running with subagents

If a subagent tool is available **and** 2+ rulesets apply, spawn one subagent per ruleset in parallel. Give each only:
- the path to its reference file
- the project path and scope
- the output schema from section 3

Then merge results, dedupe by `file:line`, and sort by severity.

Otherwise run the rulesets one after another yourself, using the same schema.

## 3. Findings schema

Each subagent (or each inline pass) produces a list of:

```json
{"rule": "JS-01", "severity": "high|medium|low", "location": "path:line or path", "issue": "one line", "fix": "one line"}
```

Report violations only, never passes. Cap at 5 locations per rule; add a count if there are more.

## 4. Report

```
## Audit: <project> — <rulesets used>
<N> findings (<h> high, <m> medium, <l> low)

| Rule | Sev | Location | Issue | Fix |
|---|---|---|---|---|

Skipped: <rules that couldn't be checked and why>
```

If nothing is found, say so in one line.
