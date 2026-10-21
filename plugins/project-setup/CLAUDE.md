# CLAUDE.md

Guidance for Claude Code when working in the `project-review` plugin.

## Rulesets (`skills/*/references/*.md`)

- **Append new rules at the end** of a ruleset table, with the next free ID, whatever their
  severity. Table order is not severity order — the report sorts by severity.
- **Don't change existing rules** (wording, severity, position or ID) unless explicitly asked.
  Rule IDs are stable references that findings and past reports point to; never renumber.
