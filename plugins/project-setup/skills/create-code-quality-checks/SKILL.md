---
name: create-code-quality-checks
description: Set up non-AI code quality checks (lint, format, static analysis, type check, build, vulnerability audit) for TS/JS and Python projects, locally and in CI, using Instea house opinions. Run with /create-code-quality-checks [project path].
disable-model-invocation: true
argument-hint: "[project path, default: current dir]"
---

# Create Code Quality Checks

Set up deterministic quality checks in the repo at `$ARGUMENTS` (default: current directory):
lint, format check, static analysis (complexity, code smells, duplication, dead code, best
practices), type check, build check and dependency audit. Each stack gets one local `check` command,
and CI calls the same commands, so every CI failure reproduces locally.

Supported stacks: **TS/JS** (`references/typescript.md`) and **Python** (`references/python.md`).
CI: `references/ci.md`. Read only the references you need.

## Specification

House opinion per check and stack. The references hold the exact versions, thresholds and commands.

| Check               | TS/JS                                                                                                                         | Python                                                            |
|---------------------|-------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------|
| Package manager     | pnpm                                                                                                                          | uv                                                                |
| Lint                | ESLint flat config + typescript-eslint `recommendedTypeChecked`; framework rules for detected frameworks                      | Ruff (`ruff check`)                                               |
| Format              | Prettier (`prettier --check`) + `eslint-config-prettier`                                                                      | Ruff (`ruff format --check`)                                      |
| Complexity          | ESLint `complexity` 10, `max-depth` 4, `max-params` 4, `max-lines-per-function` 80, `max-nested-callbacks` 3, `max-lines` 300 | Ruff `C901` (max 10) + `PLR0911/0912/0913/0915`                   |
| Code smells         | `eslint-plugin-sonarjs` recommended, `sonarjs/cognitive-complexity` 15                                                        | complexipy (cognitive complexity, max 15), Ruff `PL`              |
| Duplication         | jscpd + sonarjs duplicate rules                                                                                               | jscpd (`--format python`)                                         |
| Dead code           | ESLint unused/unreachable rules + knip                                                                                        | vulture (`--min-confidence 60`) + deptry                          |
| Best practices      | `eslint-plugin-unicorn` curated subset                                                                                        | Ruff `B`, `SIM`, `UP`, `PERF`, `RUF`                              |
| Type check          | `tsc --noEmit`                                                                                                                | mypy                                                              |
| Build               | Repo's `build` script via `build:check`                                                                                       | `uv build` (package) or `python -c "import <entry_module>"` (app) |
| Vulnerability audit | `pnpm audit --prod --audit-level=high`                                                                                        | pip-audit                                                         |
| Git hook            | husky + lint-staged                                                                                                           | pre-commit framework; husky in a mixed repo                       |

All checks of a stack run through one `check` command: `pnpm check` (TS/JS), `uv run poe check`
(Python, poethepoet tasks).

## Rules

- Respect the tools project already uses. Switch a tool to the
  house opinion only when the user says yes to that tool.
- Extend existing config files in place. Never remove or loosen a user setting. When a house rule
  conflicts with a user setting, the user's setting wins; list each conflict in the summary.
- Never turn on TS `strict` or mypy `strict` in an existing config.
- Node version lives only in `package.json` `engines.node`. Python version lives only in
  `requires-python`. Never create `.nvmrc`, `.npmrc` or `.python-version`.
- One severity (`error` or `warning`) applies to **every** check. The user picks it.
- Fix configuration, never the code findings the checks report.
- Pin every tool version exactly, as the assets do.
- Leave all changes uncommitted.

## Step 0: Version check

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-plugin-version.sh"`. Exit code 3 means the plugin is
stale: show its output and ask whether to continue anyway.

## Step 1: Detect

Look at the repo (skip `node_modules`, `.venv`, `dist`, `build`, and similar folders):

| Signal | Means |
|---|---|
| `package.json`, `*.ts`/`*.tsx`/`*.js`/`*.jsx` | TS/JS stack |
| `pyproject.toml`, `requirements*.txt`, `*.py` | Python stack |
| Lockfile: `pnpm-lock.yaml` / `package-lock.json` / `yarn.lock` / `uv.lock` / `poetry.lock` | Package manager in use |
| `eslint.config.*`, `.eslintrc*`, `biome.json`, `.prettierrc*`, `[tool.ruff]`, `.flake8`, `[tool.black]`, `[tool.mypy]`, `pyrightconfig.json` | Linter / formatter / type checker in use |
| `pnpm-workspace.yaml`, `workspaces`, `turbo.json`, `nx.json`, `[tool.uv.workspace]` | Monorepo |
| `react`, `next`, `vue` dependencies | Frameworks (TS rules) |
| `.husky/`, `.pre-commit-config.yaml`, `lefthook.yml` | Existing git hooks |
| `.github/workflows/`, `.gitlab-ci.yml`, `bitbucket-pipelines.yml`, `azure-pipelines.yml`, `git remote get-url origin` | CI platform and existing pipeline |

Then branch:

- **No TS/JS or Python source files and no manifest** (empty repo): say so and exit. Change nothing.
- **Only other languages** (Go, Java, .NET...): say the skill supports only TS/JS and Python, and
  exit. Change nothing.
- **A supported stack next to an unsupported one**: set up the supported stack, and say in the
  summary which part was skipped.
- **Supported source files but no manifest**: plan to initialize one with the stack's package
  manager:

  | Stack | Init |
  |---|---|
  | TS/JS | `pnpm init` (see `typescript.md` → No manifest) |
  | Python | `uv init --bare` (see `python.md` → No manifest) |

## Step 2: Report

Show the user what you found: stacks, package managers, existing lint/format/type-check tools,
frameworks, monorepo layout, existing hooks, CI platform and existing pipeline. Also list what you
will init, if anything. Wait for the questions in Step 3 before changing anything.

## Step 3: Ask

Use AskUserQuestion. Ask one decision per question, in this order:

1. **Each tool that differs from the Specification table** gets its own question: switch or keep.
   A kept tool still gets the same check categories, built with that tool (mapping tables in the
   references).
2. **Severity** for every check: `error` (findings fail `check` and CI) or `warning` (findings are
   reported, nothing fails). Make no recommendation.
3. **Git hooks** (tool per the Specification table): yes or no. Default content: pre-commit formats
   and lints staged files, nothing else. In a mixed repo, lint-staged also runs
   `uv run ruff check --fix` + `uv run ruff format` for `*.py`. Use different content only if the
   user asks for it.
4. **Python-only repo with no `node` on PATH**: the duplication question from `python.md` → jscpd
   and Node.

## Step 4: Apply

1. Create working branch.
2. Init missing manifests (Step 1).
3. For each stack, follow its reference: copy and merge the assets for the chosen severity, add
   framework rules, and handle the monorepo layout.
4. Git hooks, if accepted, per the Specification table (files and wiring in the references).
   Append to existing hooks instead of replacing them. A mixed repo gets one hook manager only:
   two hook managers conflict.
5. CI per `ci.md`: add the jobs to the existing pipeline, or create the platform's file.
6. Warning mode only: write `docs/code-quality.md` (template in `typescript.md` → Warning → error
   note; keep only the sections for the stacks you set up).

## Step 5: Verify

Install dependencies (e.g. `pnpm install`, `uv sync`). Run every individual command of app that worked before and it should still work, then `check`.

Sort each failure into one of two kinds:

- **Finding**: the tool ran and reports problems in the code. That is acceptable. Record the count.
- **Config failure**: the tool didn't run properly. Examples: `Cannot find module`,
  `Error while loading rule`, `ERR_PNPM`, `Invalid option`, `command not found`, `No module named`,
  `unknown field`, `Unknown task`, `Failed to parse`, a wrong path, or a tool scanning
  `node_modules`/`.venv`.

Fix every config failure and run again. You are done when every remaining failure is a finding.
In warning mode, `check` must exit 0.

## Step 6: Summarize

Tell the user:

- A table with each decision they made and what it led to (tool kept/switched, severity, hooks,
  duplication option).
- Each command: passes / N findings / config fixed (and what was fixed).
- Conflicts where their existing setting won over a Instea opinion, and existing CI steps you replaced.
- Skipped stacks, and any init you ran.
- Warning mode: point to `docs/code-quality.md` for switching checks to error.
- That all changes are uncommitted and ready for review.
