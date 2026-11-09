# TS/JS checks

Load this file when the repo has a `package.json` or TS/JS source files.

## Opinion set

| Area | Opinion |
|---|---|
| Package manager | **pnpm**, version pinned in `package.json` `packageManager` |
| Node version | **Only** `package.json` `engines.node`. Never create `.nvmrc` or `.npmrc` |
| CI install | `pnpm install --frozen-lockfile`; Node read from `package.json` |
| Lint | ESLint flat config + typescript-eslint `recommendedTypeChecked` |
| Framework rules | Only for detected frameworks (see below) |
| Format | Prettier, `prettier --check`; `eslint-config-prettier` disables conflicting rules |
| Type check | `tsc --noEmit` as its own script |
| Build | The repo's `build` script via `build:check`; with no `build` script, `build:check` runs `pnpm typecheck` |
| TS strictness | Never changed. With no `tsconfig.json`, create one with `pnpm exec tsc --init` and keep its defaults |
| Complexity | `complexity` 10, `max-depth` 4, `max-params` 4, `max-lines-per-function` 80, `max-nested-callbacks` 3, `sonarjs/expression-complexity` 3 |
| File size | `max-lines` 300 per file (blank lines and comments not counted) |
| Cognitive complexity + smells | `eslint-plugin-sonarjs` recommended, `sonarjs/cognitive-complexity` 15 |
| Best practices | `eslint-plugin-unicorn`, curated subset (in `assets/ts/eslint.config.js`) |
| Code duplication (DRY) | jscpd, `minTokens` 30, `threshold` 3 in error mode. ESLint: `sonarjs/no-duplicate-string` (threshold 3), `no-duplicate-imports`, plus the sonarjs preset's `no-identical-functions` and `no-duplicated-branches` |
| Dead code | ESLint (`no-unused-vars`, `no-unreachable`, `no-unused-private-class-members`) + knip |
| Vulnerabilities | `pnpm audit --prod --audit-level=high` |
| Monorepo | pnpm workspaces, `pnpm -r`. Turborepo/Nx only if already present |
| Git hook | husky; pre-commit runs `lint-staged` (`eslint --fix` + `prettier --write` on staged files). Nothing else |

The unicorn subset only flags clear bugs and outdated APIs (`throw-new-error`, `prefer-node-protocol`,
`no-instanceof-builtins`...). Style-only rules from the full preset (`filename-case`,
`prevent-abbreviations`, `no-null`) are left out on purpose: they produce hundreds of findings in an
existing codebase and say nothing about quality.

## Assets

| Asset | Goes to | How |
|---|---|---|
| `assets/ts/eslint.config.js` | `eslint.config.js` | Copy. Set `const SEVERITY = "error";` or `"warn"`. Uncomment the framework blocks you detected |
| `assets/jscpd.json` | `.jscpd.json` | Copy. In warning mode, delete `threshold` |
| `assets/ts/package.scripts.<severity>.json` | `package.json` | Merge `scripts`, `lint-staged`, `devDependencies` (rules below) |
| `assets/ts/husky-pre-commit` | `.husky/pre-commit` | Only if the user accepted hooks. Also add `"prepare": "husky"` to `scripts` |

**Merging into `package.json`:**

- A script name that already exists stays as the user wrote it. Report this in the summary, and wire
  `check` to the existing script.
- Never edit the user's `build` script. `build:check` wraps it.
- `devDependencies`: add the pinned versions. If a package is already present, keep the user's version.
- `lint-staged`: only with hooks. Merge with an existing `lint-staged` block, keeping existing globs.

**Existing `eslint.config.*`:** do not replace it. Add the missing imports, presets and rule blocks
from the asset into the user's array. A rule the user set explicitly (including `"off"`) keeps the
user's value; list each such conflict in the summary. Wrap the exported array with `withSeverity`.
A legacy `.eslintrc*` config: ask the user before migrating it to flat config.

## Severity

| Script | error | warning |
|---|---|---|
| `lint` | `eslint . --max-warnings=0` | `eslint .`, `SEVERITY = "warn"` |
| `format:check` | `prettier --check .` | `... \|\| exit 0` |
| `typecheck` | `tsc --noEmit` | `... \|\| exit 0` |
| `build:check` | `pnpm build` | `pnpm build \|\| exit 0` |
| `knip` | `knip` | `knip --no-exit-code` |
| `duplication` | `jscpd --format typescript,javascript,tsx,jsx .`, `threshold` 3 | same, without `threshold` |
| `audit` | `pnpm audit --prod --audit-level=high` | `... \|\| exit 0` |
| `check` | all of the above, chained with `&&` | same |

`check` calls `pnpm run audit`, never `pnpm audit`: the bare form runs pnpm's built-in command and
skips the script.

## Frameworks

| Detected by (dependency) | Add devDependency | Uncomment in `eslint.config.js` |
|---|---|---|
| `react` | `eslint-plugin-react-hooks` | React block |
| `next` | `@next/eslint-plugin-next` (+ React block) | Next.js block |
| `vue` | `eslint-plugin-vue` | Vue block; add `vue-tsc` and set `typecheck` to `vue-tsc --noEmit` |

Pin each added plugin to an exact version (`pnpm view <pkg> version`).

## Monorepo

A `pnpm-workspace.yaml` (or `workspaces` in `package.json`) means a monorepo. Put the configs and
scripts at the root. Lint, format, knip and jscpd run once from the root. Use `pnpm -r typecheck` and
`pnpm -r build` for packages that have those scripts. If Turborepo/Nx is present, use `turbo run` /
`nx run-many` for typecheck and build instead.

## Audit exceptions

`pnpm audit --ignore <GHSA-id>` records an exception in `pnpm-workspace.yaml` under
`auditConfig.ignoreGhsas`. Add a YAML comment next to each entry giving the reason and the date. Only
add exceptions the user approves.

## No manifest

TS/JS files exist but there is no `package.json`: run `pnpm init`, then set `packageManager`
(`pnpm@<pnpm --version>`) and `engines.node` (`>=<current node major>`).

## User keeps a different tool

Build the same check categories with their tool. Never install pnpm when the user keeps npm/yarn.

| Kept tool | Replace |
|---|---|
| npm | `npm run <script>`; `npm ci` in CI; audit `npm audit --omit=dev --audit-level=high`; hook `npx lint-staged` |
| yarn Berry (v2+) | `yarn <script>`; `yarn install --immutable`; audit `yarn npm audit --environment production --severity high` |
| yarn v1 | `yarn <script>`; `yarn install --frozen-lockfile`; audit `yarn audit --groups dependencies --level high`. `check` and `audit` are built-in yarn v1 commands: chain `yarn run audit`, and tell the user to run `yarn run check` |
| Biome (instead of ESLint + Prettier) | `lint` = `biome lint`, `format:check` = `biome format`, CI uses `biome ci`. Enable `complexity/noExcessiveCognitiveComplexity` (max 15) in `biome.json`. sonarjs/unicorn don't apply. knip and jscpd stay |
| Existing Prettier config | Keep it as is |

## Warning → error note

In warning mode, write `docs/code-quality.md` in the target repo (stacks not set up: drop their
section):

```markdown
# Code quality checks

All checks currently run in **warning** mode: they report findings but never fail locally or in CI.
Run them with `pnpm check` (TS/JS) and `uv run poe check` (Python).

## Switching a check to error

### TS/JS (`package.json`, `eslint.config.js`, `.jscpd.json`)
- ESLint: set `const SEVERITY = "error";` in `eslint.config.js` and use `eslint . --max-warnings=0`.
- format:check, typecheck, build:check, audit: remove `|| exit 0` from the script.
- knip: remove `--no-exit-code`.
- jscpd: add `"threshold": 3` to `.jscpd.json`.

### Python (`pyproject.toml` `[tool.poe.tasks]`)
- Ruff: remove `--exit-zero` from the `lint` task.
- Every task ending in `|| exit 0`: remove it.
- complexity: remove `--ignore-complexity`.
- audit: change the final `exit 0` back to `exit $s`.
- duplication: add `"threshold": 3` to `.jscpd.json`.
```
