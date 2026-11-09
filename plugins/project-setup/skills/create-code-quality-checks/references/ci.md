# CI

## Platform

Read `git remote get-url origin` and pick the template by host:

| Remote host contains | Platform | Template | Target file |
|---|---|---|---|
| `github` / no remote | GitHub Actions | `assets/ci/github-quality.yml` | `.github/workflows/quality.yml` |
| `gitlab` | GitLab CI | `assets/ci/gitlab-ci.yml` | `.gitlab-ci.yml` |
| `bitbucket` | Bitbucket Pipelines | `assets/ci/bitbucket-pipelines.yml` | `bitbucket-pipelines.yml` |
| `dev.azure.com` / `visualstudio.com` | Azure Pipelines | `assets/ci/azure-pipelines.yml` | `azure-pipelines.yml` |

A self-hosted host whose name doesn't tell (e.g. `git.company.com`): look for an existing pipeline file. If there is none, ask
the user which platform to use.

## Fitting the template

1. Keep the `# --- ts ---` ... `# --- end ts ---` and `# --- python ---` ... `# --- end python ---`
   blocks for the detected stacks. Delete the others and the marker comments.
2. Replace `main` with the repo's default branch (`git symbolic-ref refs/remotes/origin/HEAD`, else `main`).
3. Node image / version: match the major of `engines.node` (GitHub reads `package.json` itself).
4. Python image: a `requires-python`-compatible tag; uv downloads another interpreter if needed.
5. Paths: if `package.json` / `pyproject.toml` are not at the repo root, set `working-directory`
   (GitHub), `cd` in `before_script`/`script` (GitLab, Bitbucket, Azure), and prefix the path filters.
6. Kept tools (npm, yarn, Poetry...): swap the install and run commands per `typescript.md` / `python.md`.
7. Duplication skipped or done with Pylint: remove the Node setup from the Python static-analysis job.

## Existing pipeline

If the repo already has a pipeline for that platform, **add the quality jobs to it**. Don't create a
second file. On GitHub, use the workflow that runs on `pull_request`. If several do, use the one
that already runs lint or tests. If that still leaves more than one, ask the user which one to use.

- Keep every existing job and step.
- If an existing job already runs one of the checks (e.g. `npm run lint`), switch that step to the
  script/task and don't add a duplicate job. Report each such change in the summary.
- Keep the existing triggers. Add the audit job with the PR/MR-only guard.

## Rules every template follows

- Triggers: PR/MR and pushes to the default branch. No schedules.
- **Audit runs on PR/MR only**, never on push. GitHub `if: github.event_name == 'pull_request'`;
  GitLab `rules: - if: $CI_PIPELINE_SOURCE == "merge_request_event"`; Bitbucket only under
  `pull-requests:`; Azure `condition: eq(variables['Build.Reason'], 'PullRequest')`.
- Every job calls the repo's scripts/tasks. Severity lives in those scripts, so CI needs no
  `continue-on-error` / `allow_failure`.
- Path filters skip a stack's jobs when a change doesn't touch it. Azure has no per-job path filter.
- Every action and image is pinned to an exact version, never `latest` or `@main`.
- Never reference `.nvmrc`, `.npmrc` or `.python-version`.
- GitHub: Ruff runs with `--output-format=github`, so its findings show as PR annotations.
