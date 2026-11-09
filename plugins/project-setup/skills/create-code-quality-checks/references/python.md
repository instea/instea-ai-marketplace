# Python checks

Load this file when the repo has a `pyproject.toml` or Python source files.

## Opinion set

| Area | Opinion |
|---|---|
| Package manager | **uv**, `uv.lock` committed, CI runs `uv sync --locked` |
| Python version | **Only** `requires-python` in `pyproject.toml`. Never create `.python-version` |
| Lint + format | Ruff: `ruff check`, `ruff format --check` |
| Rule sets | `E`, `F`, `W`, `I`, `C90`, `PL`, `B`, `SIM`, `UP`, `PERF`, `RUF`; ignore `PLR2004` |
| Complexity | Ruff `C901` (max 10) and `PLR0911/0912/0913/0915` (`max-args` 4, others at Ruff defaults) |
| Cognitive complexity | complexipy, max 15 |
| Type check | mypy. Existing `[tool.mypy]` untouched; never add `strict` |
| Build | `uv build` for a package; for an app, `python -c "import <entry_module>"` |
| Code duplication | jscpd (`--format python`), shared `.jscpd.json` — see "jscpd and Node" |
| Dead code | vulture (`--min-confidence 60`, allowlist `vulture_allowlist.py`) + deptry |
| Vulnerabilities | pip-audit over `uv export --no-dev` |
| Task runner | poethepoet, `[tool.poe.tasks]`; `uv run poe check` runs everything |
| Monorepo | uv workspaces (`[tool.uv.workspace]`) |
| Git hook | Python-only repo: pre-commit framework (`ruff check --fix`, `ruff format`). Mixed repo: husky owns the hook (see `typescript.md`) |

vulture runs at 60, not higher: vulture rates every unused function, class and method at 60%
confidence, so a higher cutoff would only find unused imports and variables, which Ruff already
reports. False positives (framework entry points, Django/FastAPI hooks) go into `vulture_allowlist.py`.

## Assets

| Asset | Goes to | How |
|---|---|---|
| `assets/python/pyproject.<severity>.toml` | `pyproject.toml` | Merge (rules below). Set `PY_SRC` in `[tool.poe.env]` to the source dir |
| `assets/jscpd.json` | `.jscpd.json` | Copy if not already there. In warning mode, delete `threshold` |
| — | `vulture_allowlist.py` | Create empty |
| `assets/python/pre-commit-config.yaml` | `.pre-commit-config.yaml` | Python-only repo with hooks accepted. Add `pre-commit` to the dev group and run `uv run pre-commit install` |

**Merging into `pyproject.toml`:**

- `[dependency-groups] dev`: add the missing pinned packages. If a package is already present, keep the user's version.
- `[tool.ruff.lint]` exists: union the `select` lists. Never remove anything from the user's `ignore` or
  `per-file-ignores`. A user value for `max-complexity` / `max-args` wins; list the conflict in the summary.
- `[tool.poe.tasks]` exists: keep same-named tasks as the user wrote them, and add the rest. Add `check` last.
- `[tool.mypy]` exists: leave it; the `typecheck` task only passes the path.
- An app without a build backend: set `build` to `python -c "import <entry_module>"` (with `|| exit 0` in
  warning mode as a `shell` task).

## Severity

| Task | error | warning |
|---|---|---|
| `lint` | `ruff check` | `ruff check --exit-zero` |
| `complexity` | `complexipy ... --max-complexity-allowed 15` | add `--ignore-complexity` |
| `format-check`, `typecheck`, `deadcode`, `deps`, `build` | plain command | `shell` task ending in `\|\| exit 0` |
| `audit` | `exit $s` | `exit 0` |
| `duplication` | `.jscpd.json` with `threshold` 3 | `.jscpd.json` without `threshold` |
| `check` | sequence of all tasks | same |

`check` is a poe sequence; it stops at the first failing task.

## jscpd and Node

jscpd is a Node tool. In a repo that also has TS/JS, Node is there already. In a **Python-only** repo,
run `command -v node`:

- Node present: use the `duplication` task as is. CI installs Node for that job.
- No Node: ask the user to pick one option:
  1. Install Node for jscpd (local + CI).
  2. Pylint's duplicate-code check: add `pylint` to the dev group, and set `duplication` to
     `pylint --disable=all --enable=duplicate-code ${PY_SRC}` (plus `--exit-zero` in warning mode).
  3. Skip duplication checks: delete the `duplication` task and drop it from `check`.

## Audit exceptions

Add `--ignore-vuln <ID>` to the `pip-audit` call for each approved exception, with a TOML comment above
the task giving the reason and the date.

## No manifest

Python files exist but there is no `pyproject.toml`: run `uv init --bare`, then set `requires-python`
to the lowest version the code needs (default: the current Python minor, e.g. `>=3.12`). If a
`requirements.txt` exists, ask before importing it with `uv add -r requirements.txt`.

## Monorepo

A `[tool.uv.workspace]` means a uv workspace. Put the tool config and tasks in the root `pyproject.toml`,
and set `PY_SRC` to the space-separated member source dirs. `uv sync --all-packages` installs every member.

## User keeps a different tool

Build the same check categories with their tool.

| Kept tool | Replace |
|---|---|
| Poetry | `poetry run poe <task>`; `poetry install --sync` in CI; audit over `poetry export --without dev -f requirements.txt` |
| pip + `requirements.txt` | Install with `pip install -r requirements*.txt`; audit `pip-audit -r requirements.txt`; tasks still via poethepoet |
| Flake8 / Black / isort (instead of Ruff) | `lint` = `flake8` (`--max-complexity 10`), `format-check` = `black --check . && isort --check .`. Keep their configs. complexipy, vulture, deptry and jscpd stay |
| pyright (instead of mypy) | `typecheck` = `pyright` |
