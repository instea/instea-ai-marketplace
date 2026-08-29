# project-setup

Instea house standards for bootstrapping project infrastructure — CI, Docker and release
pipelines — so every repo ends up with the same shape instead of a hand-rolled variant.

## Install

```
/plugin marketplace add instea/instea-ai-marketplace
/plugin install project-setup@instea-ai-marketplace
```

## Skills

| Skill | Invocation | What it does |
|---|---|---|
| `docker-release-workflow` | ⌨️ explicit | GitHub Actions workflow that builds and publishes each service's Docker image and cuts a GitHub release |

- ⌨️ **explicit** — you start it yourself with a slash command; Claude never runs it on its own
  (the skill sets `disable-model-invocation: true`).
- 🤖 **automatic** — Claude invokes it when the task calls for it.

### `docker-release-workflow` ⌨️

Sets up a GitHub Actions release workflow that builds each service's Docker image, publishes it
to `registry.instea.co`, and cuts a GitHub release from the root `package.json` version. Scaffolds
a Dockerfile and `.dockerignore` for services that don't have one yet.

**Invoke it explicitly:**

```
/project-setup:docker-release-workflow
```

Anything you type after the command name is treated as a deliberate instruction and overrides the
defaults — a target directory, a subset of services, "skip the release job".

**What you get**

`.github/workflows/release.yml` with two jobs, triggered on push to the default branch and on PRs:

1. **Build & push** — a matrix job builds each service with Buildx and pushes
   `registry.instea.co/<project>-<service>:latest`.
2. **Release** — reads `version` from the root `package.json` and (re)creates the `v<version>`
   GitHub release with auto-generated notes, pointing at the pushed commit.

On pull requests images are **built but not pushed**, and the release job is skipped. PRs still get a
real signal that the Dockerfile builds, without an unmerged branch overwriting `:latest` or moving a
published release.

**How it runs**

1. *Survey* — works out the service list from `docker-compose.yml` (or `apps/*`, `packages/*`,
   `src/*/package.json`), the image-name prefix from the repo name, and the version source; then
   confirms all three with you before writing anything.
2. *Scaffold missing Dockerfiles* — only for services that have none; an existing Dockerfile is never
   rewritten. New files land at `<service>/docker/Dockerfile` with a `.dockerignore` at the service
   root, adapted to the detected package manager, Node version, port and build output dir.
3. *Write the workflow* — from the bundled template, with the matrix and image prefix filled in.
4. *Verify and hand over* — lints the YAML (`actionlint` when available), checks `gh secret list`,
   and closes with the secrets checklist, the resulting image names, the tag the first release will
   carry, and anything it skipped or replaced.

**Bundled templates** (`skills/docker-release-workflow/assets/`)

| File | Use |
|---|---|
| `release.yml` | The GitHub Actions workflow template |
| `Dockerfile.node-service` | Node API / worker / GraphQL server — single stage, alpine, runs the test suite then prunes to production deps |
| `Dockerfile.spa-nginx` | React / Vite SPA — multi-stage build served by nginx |
| `nginx.conf` | Companion config for the SPA image |
| `dockerignore` | Copied to the service root as `.dockerignore` |

The Node templates run `yarn test` inside the build on purpose: a failing test fails the image build,
so a broken image can never reach the registry.

**Required secrets**

`DOCKER_REGISTRY_USERNAME` and `DOCKER_REGISTRY_PASSWORD` must exist as repository or organization
secrets — most Instea repos in the org already have them. Without them the first push to the default
branch fails at the registry login step:

```
gh secret set DOCKER_REGISTRY_USERNAME
gh secret set DOCKER_REGISTRY_PASSWORD
```

**When a run comes back red**

`skills/docker-release-workflow/references/troubleshooting.md` lists the symptoms and causes this
workflow actually produces — auth failures, missing build context, wrong Dockerfile path, releases
that never appear.

## Adding a skill to this plugin

Drop it in `skills/<skill-name>/SKILL.md` (kebab-case dir, `name` and `description` in the
frontmatter; supporting `assets/` and `references/` files live alongside it), bump `version` in
`.claude-plugin/plugin.json` and in the marketplace entry, and add it to the table above — mark it
⌨️ explicit if it sets `disable-model-invocation: true`, 🤖 automatic otherwise. Then validate:

```
claude plugin validate ./plugins/project-setup --strict
```
