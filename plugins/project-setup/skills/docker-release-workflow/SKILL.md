---
name: docker-release-workflow
description: Set up a GitHub Actions release workflow that builds each service's Docker image, publishes it to registry.instea.co, and cuts a GitHub release from the package.json version. Scaffolds any missing Dockerfile and .dockerignore.
disable-model-invocation: true
---

# Docker release workflow (Instea house standard)

This sets up one workflow file, `.github/workflows/release.yml`, that does two things on
every push to `main`:

1. **Build & push** — a matrix job builds each service's image with Buildx and pushes it to
   `registry.instea.co/<project>-<service>:latest`.
2. **Release** — a follow-up job reads `version` from the root `package.json` and (re)creates
   the `v<version>` GitHub release with auto-generated notes pointing at the pushed commit.

On pull requests the images are **built but not pushed**. That is the one deliberate departure
from older Instea repos: it gives PRs a real signal that the Dockerfile still builds, without
letting an unmerged branch overwrite `:latest` in the registry or move a published release.

This skill is invoked explicitly, so anything the user typed after the command name is a
deliberate instruction — a target directory, a subset of services, "skip the release job". Honour
it, and let it override the defaults below rather than re-asking about it in step 1.

Work through the four steps below in order. Steps 1 and 2 are where the judgment lives; steps
3 and 4 are mostly mechanical.

## Step 1 — Survey the project

Before writing anything, figure out what you are actually publishing. Gather:

**The services.** Start from what already exists:

```bash
find . -name Dockerfile -not -path '*/node_modules/*' -not -path './.git/*'
ls docker/ 2>/dev/null && cat docker/docker-compose*.yml 2>/dev/null
```

An existing `docker-compose.yml` is the best source of truth in an Instea repo — its `build.context`
and `build.dockerfile` pairs are exactly the matrix entries you need, and its service names usually
match the intended image names. If there is no compose file, look for `src/*/package.json`,
`packages/*`, or `apps/*`; a directory with its own `package.json` and a `start` script is a service.
A repo with a single `package.json` at the root is a single-service repo — still use the matrix, with
one entry, so adding a second service later is a two-line diff.

**The image name prefix.** Conventionally the GitHub repo name: `gh repo view --json name -q .name`,
falling back to the directory name. Images become `registry.instea.co/<repo>-<service>:latest`.
For a single-service repo where `<repo>-<service>` would stutter (`retros-retros`), just use
`registry.instea.co/<repo>:latest`.

**The version source.** The release job reads the root `package.json` `version` field. Verify that
this is the field the team actually bumps, because a stale root version silently republishes the
same release forever:

```bash
node -p "require('./package.json').version"
git tag --list 'v*' | tail -5
head -20 CHANGELOG.md 2>/dev/null
```

If the root version disagrees with the tags or the CHANGELOG, say so and ask which one is
authoritative rather than guessing — this is a common leftover in repos migrating off Jenkins.

**Confirm before proceeding.** Tell the user the service list, the resulting image names, and the
version you read, in three or four lines. Getting the matrix wrong means a broken first run on
`main`, which is annoying to unwind.

## Step 2 — Scaffold any missing Dockerfile

Only for services that have no Dockerfile. Never rewrite one that exists — a working Dockerfile
encodes deployment details (nginx config, env injection, build args) that are invisible from the
outside.

Place new files at `<service>/docker/Dockerfile`, the house location, and add a `.dockerignore`
at the service root. Two templates in `assets/` cover almost every service Instea builds:

| Service shape | Template | Notes |
|---|---|---|
| Node API / worker / GraphQL server | `assets/Dockerfile.node-service` | Single stage, alpine, runs `yarn test` then prunes to production deps |
| React / Vite SPA served by nginx | `assets/Dockerfile.spa-nginx` | Multi-stage build → nginx; pair with `assets/nginx.conf` |

Copy the template, then adapt it to the service rather than leaving placeholders:

- **Package manager** — a `yarn.lock` means yarn, `package-lock.json` means npm, `pnpm-lock.yaml`
  means pnpm. Copying the wrong lockfile makes the install step fail with a confusing error.
- **Node version** — read `engines.node` or `.nvmrc` if present; otherwise use the current LTS.
- **Port** — read it from the service's own code or compose entry, not from the template default.
- **Build output directory** — CRA and Vite disagree (`build/` vs `dist/`); check the actual build
  script before wiring the nginx `COPY --from`.

The templates run the test suite inside the build (`RUN yarn test`), which is the Instea convention:
a failing test then fails the image build, so a broken image can never reach the registry. If the
project has no tests, or its tests need a live database, drop that line and mention that you did.

Then check the Dockerfile actually builds before wiring CI around it — a 30-second local failure
beats a red first run on `main`:

```bash
docker build -f <service>/docker/Dockerfile <service>
```

If Docker isn't available in the environment, say so explicitly instead of silently skipping.

## Step 3 — Write the workflow

Copy `assets/release.yml` to `.github/workflows/release.yml` and fill in the matrix entries and the
image prefix. The template is short enough to read in full — do that before editing it, because a
few of its details look wrong out of context and are explained in "Why the template looks like this"
below.

Adjustments the project may call for:

- **Default branch** — if the repo uses `master` or `develop`, change both trigger branches and the
  `if` guard on the release job. Check with `git symbolic-ref refs/remotes/origin/HEAD`.
- **No root `package.json`** — for non-Node repos, replace the version step with whatever the project
  uses (`VERSION` file, `Cargo.toml`, `pyproject.toml`). Keep the rest of the release job identical.
- **Releases not wanted** — some internal services only need images. Delete the whole `release` job
  rather than leaving it disabled; a commented-out job rots.

## Step 4 — Verify, then hand over the secrets checklist

Validate the YAML. `actionlint` is the real check if it's installed; otherwise parse it, which at
least catches indentation damage:

```bash
actionlint .github/workflows/release.yml \
  || python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('YAML OK')"
```

Then check whether the registry credentials are already configured — most Instea repos in the same
org already have them, and the answer changes what you tell the user:

```bash
gh secret list 2>/dev/null
```

Close with a short handover that covers exactly these points:

1. **Secrets** — `DOCKER_REGISTRY_USERNAME` and `DOCKER_REGISTRY_PASSWORD` must exist as repository
   or organization secrets. If `gh secret list` showed them, say they're already there; if not, give
   the command: `gh secret set DOCKER_REGISTRY_USERNAME`. Without them, the first push to `main`
   fails at the login step.
2. **Images** — the exact image names that will appear in the registry.
3. **Release** — the tag the first release will carry, so a wrong version gets caught before it ships.
4. **Anything you replaced or skipped** — a removed `yarn test`, an unverified Docker build, a
   Dockerfile you left alone.
5. **Superseded CI** — if the repo still has a `Jenkinsfile`, `.gitlab-ci.yml`, or publish scripts in
   `scripts/`, point out that they now overlap with this workflow. Don't delete them; retiring the old
   pipeline is a deployment decision that belongs to whoever owns the server.

## Why the template looks like this

Each of these has bitten someone before. If you find yourself wanting to "fix" one, re-read the
reason first — and if the project genuinely calls for something different, change it and say why.

**The release is deleted and recreated on every push.** Instea bumps `version` in `package.json` by
hand, so many commits share one version. `gh release delete --cleanup-tag ... || true` followed by a
fresh release keeps `v1.7.0` pointing at the newest `main` commit instead of failing on "tag already
exists". The `|| true` is what makes the very first run work, when there is nothing to delete.

**`push:` is an expression, not a literal.** `push: ${{ github.event_name == 'push' }}` is what makes
PRs build-only. Setting it to a plain `true` restores the old behaviour where any PR overwrites
`:latest`. The login step carries the same guard, so PRs from forks — which cannot read secrets —
don't fail on a login they never needed.

**The release job is guarded too.** Without `if: github.event_name == 'push'` the release job runs on
pull requests and republishes the GitHub release from an unmerged branch. This one is easy to miss
because it fails silently in the sense that nothing errors — the release just quietly moves.

**`DOCKER_BUILD_SUMMARY: false`** suppresses a large build summary that otherwise dominates every
run's page in the Actions UI.

**Actions are pinned to major versions** (`@v4`, `@v6`) rather than commit SHAs. That matches the
rest of the org's repos; a project with stricter supply-chain requirements should pin to SHAs, but
don't do that unasked, since it makes updates a manual chore.

## Optional additions

Offer these when they fit; don't add them by default, because the plain template is what the team
already reviews at a glance.

**Layer caching.** Now that PRs build images too, CI time roughly doubles. Adding to the
`build-push-action` step recovers most of it:

```yaml
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

**Version tags alongside `latest`.** If the team wants to roll back to a specific image rather than
whatever `latest` happens to be, publish both. This needs the version read before the build job, so
move the version step into its own job that the docker job `needs`:

```yaml
          tags: |
            registry.instea.co/<project>-${{ matrix.image }}:latest
            registry.instea.co/<project>-${{ matrix.image }}:${{ needs.version.outputs.version }}
```

**Multi-arch builds.** Only if the deploy target isn't amd64. `platforms: linux/amd64,linux/arm64`
on the build step, at a real cost in build time.

## Reference

`references/troubleshooting.md` — symptoms and causes for the failures this workflow actually
produces (auth failures, missing context, wrong Dockerfile path, releases that don't appear). Read it
when a run comes back red, rather than guessing from the log.
