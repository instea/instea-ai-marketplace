# Troubleshooting a red release run

Read the failing step's log first and match the symptom below. Each entry names the cause, because
several of these failures point at a step that is not the one at fault.

Pull the log with:

```bash
gh run list --workflow=release.yml --limit 5
gh run view <run-id> --log-failed
```

## Login and registry

**`unauthorized: authentication required` at the login step**
The secrets are missing or wrong. `gh secret list` shows repository secrets only — the credentials
may live at organization level and simply not be shared with this repo, which looks identical from
the repo's side. Check the org settings, or set them locally with `gh secret set DOCKER_REGISTRY_USERNAME`.

**`denied: requested access to the resource is denied` at the push step**
Login succeeded, so the credentials are valid; the account lacks push rights for this image path,
or the image name doesn't match what the registry expects. Compare the `tags:` value against images
already in the registry for a sibling project — the `<project>-<service>` prefix is a convention,
not something the registry creates on demand for every name.

**Login step skipped and the push fails**
Expected on pull requests from forks, and harmless there because `push:` is false too. If it happens
on `main`, the `if: github.event_name == 'push'` guard is matching the wrong event — check whether
the run was triggered by `workflow_dispatch` or a merge queue rather than a plain push.

## Build

**`failed to compute cache key: ... not found`**
The `context:` and the paths inside the Dockerfile disagree. Every `COPY` path is relative to the
build context, not to the Dockerfile's own directory. With `context: ./src/api` and
`dockerfile: ./src/api/docker/Dockerfile`, `COPY ./package.json` resolves to `src/api/package.json`.
Reproduce it locally — the same command CI runs:

```bash
docker build -f src/api/docker/Dockerfile src/api
```

**`Dockerfile not found`**
The `file:` path is relative to the repo root, unlike everything inside the Dockerfile. Both matrix
paths in the template start from the root for this reason.

**Tests fail in the image but pass locally**
Usually a dependency on something the container lacks: a database, a `.env` file excluded by
`.dockerignore`, or a timezone/locale difference. Either provide it in the build, or drop the
`RUN yarn test` line and run tests in a separate CI job where services can be attached.

**Build succeeds locally but OOMs or times out on the runner**
GitHub's hosted runners are smaller than a dev machine. Node builds with large bundles may need
`NODE_OPTIONS=--max-old-space-size=4096` as a build arg. Adding `cache-from: type=gha` also helps,
since it skips reinstalling dependencies on every run.

## Release

**No release appears, but the workflow is green**
The release job was skipped — check the run page for a greyed-out job. Its `if:` guard requires both
a `push` event and `refs/heads/main`; a repo whose default branch is `master` will skip it forever
while looking perfectly healthy.

**`Resource not accessible by integration`**
`permissions: contents: write` is missing from the release job, or the repository's default workflow
permissions are read-only under Settings → Actions → General. Both must allow writes.

**The release keeps landing on the same version**
`version` in the root `package.json` was never bumped. This is the expected behaviour of the
delete-and-recreate step, not a bug: it moves `v1.7.0` to the newest commit. If the team expects one
release per merge, they need a version bump in the PR, or an automated bump step ahead of the
release job.

**`tag already exists` from the create step**
The delete step failed for a reason other than "nothing to delete" — most often a protected tag rule,
which `|| true` will happily swallow while leaving the tag in place. Check the delete step's log
output rather than trusting its green checkmark.

## Getting a run without merging

The workflow only pushes on `main`, so testing the full path means merging. To rehearse first,
temporarily add `workflow_dispatch:` under `on:` and trigger it from a branch with
`gh workflow run release.yml --ref <branch>` — a manual dispatch is not a `push` event, so images
still won't be pushed and no release is cut, but every other step runs for real.
