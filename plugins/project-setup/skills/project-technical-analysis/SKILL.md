---
name: technical-analysis
description: Onboard a developer to an unfamiliar project. Produces an interactive HTML overview and a short Markdown spec for agents. Run with /technical-analysis [path].
disable-model-invocation: true
argument-hint: "[project path, default: current dir]"
---

# Technical Analysis

Analyze the project at `$ARGUMENTS` (default: current directory). The goal is to introduce it to a new developer.

## Rules

- Cite a file path for every claim. If something is unknown, list it under Open questions. Do not guess.
- Report resolved versions from lockfiles, not ranges from manifests.
- Record env var names only. Never copy secret values.
- Stay read-only: no installs, builds, or pipeline triggers.
- Make sure to explain new concepts and shorthands that are project specific. Possibility for glossary section>
- Always use only informations that are writen in project.
- Use color to highlight important information in outputs.

## Collect

1. **Overview**: what the app does, who uses it, and its main components. Create hight level visualization of main components and connections between them.
2. **Functional spec**: detailed enough that another team could rebuild the same application from it. Find features in routes, UI pages, jobs, CLI commands, DB models, and tests. Describe behavior ("User can cancel unpaid order"), not files. Cover these layers:
   1. **Features by area**: every user-visible behavior, grouped by area (auth, each domain entity, exports, jobs, admin, ops).
   2. **Data model**: one table per entity: field, type, required, default, enum values, validation, and who sets it (client or server). Note where client and server validation disagree.
   3. **Roles and permission matrix**: one table of action × role (e.g. anonymous, pending, user, owner, admin, machine client). Each cell states what the UI allows and what the server enforces. Flag every mismatch.
   4. **Screens**: per route or page: URL, who can open it, fields with labels and defaults, validation messages, buttons and actions, empty/loading/error states, and where it navigates after success.
   5. **API contract**: every endpoint, query, mutation, or RPC: inputs, output shape, auth guard, status codes or error behavior, and side effects (emails, files, external calls).
   6. **Business rules**: calculations and decision rules written as formulas or tables with exact boundaries. Add worked examples, preferably taken from the tests.
   9. **Notifications and jobs**: each trigger, recipient, channel, content fields, and schedule.
   10. **Acceptance criteria**: Given/When/Then lines per feature for the main flows and edge cases.
3. **Tech stack**: languages, runtimes, frameworks, DBs, key libraries with versions divided by apps (if can be) and tooling used in project.
4. **Integrations**: third-party services, what each does, config env vars, and where code calls it.
5. **Deployment**: how code reaches production, and which environments exist.
6. **CI/CD**: pipelines and their triggers.
7. **Getting started**: local run commands taken from the repo.
8. **Risks and open questions**: outdated deps, failing CI, missing tests, and stale docs.

For multiple app in same repo or large apps split areas across parallel `Explore` subagents. Give each subagent the functional spec layers above as its output template, so its report comes back with the same headings, with file:line citations for every item. Spot-check high-severity findings in the code before writing them down.

Read templates and test files directly when they define behavior (for example xlsx/docx templates via their XML, email templates, fixtures, and test cases).

## Output

Make sure to include date of output creation and branch with commit hash that was output made from in them

Ask user where to write outputs, default to: `<project>/docs/technical-analysis/`:

Asks user what type output he/she wants (one or even all):

- `PROJECT_SPEC.md`: dense spec for agents, with the same 8 sections. Use bullets and tables. No prose padding. Include every functional spec layer in full.
- `PROJECT_OVERVIEW.html`: one self-contained file with inline CSS/JS and no CDN. Add a sidebar nav, a search box that filters content, collapsible feature areas, CI status badges, and light/dark mode.
- `PROJECT_OVERVIEW presentation`: project overview presentation with same content as `PROJECT_OVERVIEW.html`. Summarize the functional spec here (features, roles, key rules, lifecycles); point to `PROJECT_SPEC.md` for the full detail.

Finish with a summary for the user: what the app is, and are open questions.
