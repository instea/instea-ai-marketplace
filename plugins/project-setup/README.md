# project-setup

Instea house standards for bootstrapping project infrastructure — CI, Docker, release pipelines
and sandboxed dev environments — so every repo ends up with the same shape instead of a
hand-rolled variant.

## Install

```
/plugin marketplace add instea/instea-ai-marketplace
/plugin install project-setup@instea-ai-marketplace
```

## Skills

| Skill | Invocation | What it does |
|---|---|---|
| `docker-release-workflow` | ⌨️ explicit | GitHub Actions workflow that builds and publishes each service's Docker image and cuts a GitHub release |
| `devcontainer-claude-sandbox` | ⌨️ explicit | `.devcontainer/` that runs Claude Code sandboxed inside the project's own container, with the agent's config on a named volume instead of the host's `~/.claude` |

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

### `devcontainer-claude-sandbox` ⌨️

Scaffolds a `.devcontainer/` so that every development command — the agent, the app, the tests, the
database — runs inside a container instead of on the developer's machine.

The point is blast radius. An agent running on the host can read `~/.ssh`, `~/.aws`, browser
profiles and every other repo you have checked out; so can a postinstall script in a freshly added
dependency, with or without an agent involved. Inside a container it sees the workspace and little
else, which is what makes running with loosened permissions a defensible choice rather than a gamble.

**Invoke it explicitly:**

```
/project-setup:devcontainer-claude-sandbox
```

Anything you type after the command name is treated as a deliberate instruction and overrides the
defaults — a per-project config volume, a particular base image, "we don't need docker-in-docker".

**What you get**

`.devcontainer/` containing `devcontainer.json`, a thin `Dockerfile`, and `postCreateCommand.sh`
(plus `postStartCommand.sh` when the project runs services). The `devcontainer.json` pulls in the
`claude-code` feature, a language feature, and `docker-in-docker` where the project needs it.

Plus `.claude/settings.json`, declaring `instea-ai-marketplace` and enabling `project-setup` for
the repo. The container's `~/.claude` is a fresh volume, so nothing installed on the developer's
laptop crosses into it — without the committed settings file the sandbox has none of the house
skills. Both keys are required: an `enabledPlugins` entry whose marketplace the container has
never heard of is dropped silently, with no error to search for.

The security core is the config volume:

```jsonc
"mounts": ["source=claude-code-config,target=/home/vscode/.claude,type=volume"]
```

Mounting the host's `~/.claude` into the container would hand back the credentials you just went to
the trouble of isolating — and that directory has been a target of real supply-chain attacks. A
named volume keeps the login across rebuilds without exposing the host. `target` must be the remote
user's home, which is why the skill establishes that up front. Choose the source deliberately:

- **Shared `claude-code-config`** (default) — one login covers every project on the machine.
- **Per-project** `source=${localWorkspaceFolderBasename}-claude-config` — a compromised dependency
  in one repo cannot read another's agent credentials. Prefer it for client work. Costs a login
  per project.

**What it protects, and what it does not**

Protected: the host home directory and its credentials, other checkouts, host-level packages and
daemons. *Not* protected: the repo itself (the workspace is bind-mounted, so uncommitted work is
what's at risk), network egress unless you add the optional firewall, and anything passed through
`remoteEnv`. The skill states this in its handover on purpose — a sandbox people over-trust is
worse than none.

**How it runs**

1. *Survey* — detects an existing `.devcontainer/` (patched, never overwritten), the stack and
   package manager from the lockfile, whether docker-in-docker is needed, the ports, and the base
   image's remote user; confirms before writing anything.
2. *Write the files* — from the bundled templates, adapted to what it found, plus the repo's
   `.claude/settings.json` so the house plugins reach every container. Checks the file is not
   git-ignored, since that would make the whole step a silent no-op.
3. *Decide how services run* — compose siblings, or docker-in-docker. This is where the skill
   earns its keep: a rebuild destroys the inner daemon's `/var/lib/docker`, taking the database
   with it, so it either binds data into the workspace or persists the volume, and says which.
4. *Make the app reachable* — bind `0.0.0.0` rather than `localhost`, set `forwardPorts`, and flag
   that the devcontainer CLI ignores `forwardPorts` instead of papering over it.
5. *Build it* — runs the bundled checker, then an actual `devcontainer build`. A container that has
   never been built is a guess.
6. *Hand over* — how to get in and rebuild, the one-time login, ports, what was verified, what the
   sandbox does not cover, and what a rebuild will cost.

**Bundled files** (`skills/devcontainer-claude-sandbox/`)

| File | Use |
|---|---|
| `assets/devcontainer.json` | Features, the config volume, ports, extensions |
| `assets/Dockerfile` | Only what the features don't cover |
| `assets/postCreateCommand.sh` | The four fixes that make the container usable |
| `assets/postStartCommand.sh` | Brings services up on every start (docker-in-docker only) |
| `assets/claude-settings.json` | The repo's `.claude/settings.json` — marketplace + `project-setup` |
| `assets/notify.sh` | Optional — host notifications for long agent runs, via apprise |
| `scripts/check-devcontainer.py` | Validates the result in step 5 |

`check-devcontainer.py` catches the failures that are invisible in a diff: a mount target that
doesn't match `remoteUser`, a config volume declared under a compose-based setup (where it is
silently ignored), a missing postCreate fix, a deprecated top-level `extensions` key, house
plugins the repo never declares. It exits
non-zero on real failures and prints `WARN` for judgment calls — read those, don't just check the
exit code. It keeps `assets/postCreateCommand.sh` honest by grepping for the three fixes that script
implements, so those two files must be edited together.

**When something doesn't work**

`skills/devcontainer-claude-sandbox/references/troubleshooting.md` covers the failures this setup
actually produces — credsStore errors, `~/.claude` permission denials, logins that don't persist,
the app not being reachable from the host, and rebuilds that wipe the database.

## Adding a skill to this plugin

Drop it in `skills/<skill-name>/SKILL.md` (kebab-case dir, `name` and `description` in the
frontmatter; supporting `assets/` and `references/` files live alongside it), bump `version` in
`.claude-plugin/plugin.json` and in the marketplace entry, and add it to the table above — mark it
⌨️ explicit if it sets `disable-model-invocation: true`, 🤖 automatic otherwise. Then validate:

```
claude plugin validate ./plugins/project-setup --strict
```
