# Troubleshooting the Claude Code devcontainer sandbox

Symptoms in the order they tend to appear. Each entry names the failure the way the developer
sees it, since most of these error messages point somewhere other than the actual cause.

## Container build and start

### `docker: error getting credentials - err: exit status 255, out: ``

Any `docker pull` / `docker compose up` inside the container fails immediately.

The container inherited a Docker config naming a credential helper (`credsStore`) that is not
installed there. Fix 1 in `postCreateCommand.sh` deletes that line. If you're seeing this, the
postCreate script either didn't run or ran before `~/.docker/config.json` existed — check the
creation log, and if the file appears later, move the `sed` into `postStartCommand` instead.

### `chown: invalid user: 'vscode:vscode'`

The postCreate script was copied from a project on a different base image. Use
`"$(id -un):$(id -gn)"` rather than a hardcoded user — the shipped asset already does.

### The postCreate script never seems to run

`postCreateCommand` runs relative to the workspace folder, so the path must be
`bash .devcontainer/postCreateCommand.sh`, not `bash postCreateCommand.sh`. A failure there
aborts container creation; the output is in the Dev Containers creation log (VS Code:
"Dev Containers: Show Container Log"), not in the terminal you end up in.

### docker-in-docker doesn't start; `docker ps` says the daemon isn't running

Usually an architecture mismatch — the feature has
[known limitations](https://github.com/devcontainers/features/tree/main/src/docker-in-docker#limitations)
on some image/host architecture combinations, notably arm64 hosts running amd64 images. Try
flipping `"moby"`, and confirm the host isn't emulating.

## Claude Code

### Permission denied writing to `~/.claude` on first start

The named volume is root-owned and fix 2 (`chown`) didn't run — see "postCreate script never
seems to run" above. Confirm with `ls -ld ~/.claude`: it should be owned by the remote user,
not root.

### Login doesn't persist across a rebuild

Two causes, in order of likelihood:

1. **The `.claude.json` symlink is missing or broken.** Claude keeps session state in
   `~/.claude.json`, beside the `.claude` directory rather than inside it, so the volume alone
   does not cover it. Check with `ls -l ~/.claude.json` — it should point into `~/.claude/`.
2. **The volume is mounted at the wrong path.** This one is silent: Claude reads an empty
   `~/.claude`, the volume sits unused, and nothing errors. `target` in the mount must be the
   *remote user's* home. Verify from inside with
   `mount | grep claude` and compare against `echo $HOME`.

### `Auto-update failed: no write permission to npm prefix`

Claude Code says it cannot update itself, and stays on the version the image shipped.

The `claude-code` feature installs the npm package as root, so the remote user cannot overwrite
it. Confirm both halves:

```bash
cat ~/.claude/.last-update-result.json     # "path":"npm-global","status":"no_permissions"
ls -ld "$(npm root -g)/@anthropic-ai"      # owned by root, not by you
```

Fix 4 of `postCreateCommand.sh` chowns that subtree; if it is missing, the same command applies by
hand:

```bash
sudo chown -R "$(id -un):$(id -gn)" "$(npm root -g)/@anthropic-ai"
claude update
```

Note that the npm prefix itself is normally already group-writable — chowning the whole prefix is
not needed and is a bigger change than it looks. And the update lives in the container filesystem,
not on the config volume, so a rebuild goes back to the feature's version. That is intended.

### The house skills aren't there in a fresh container

`/project-setup:...` doesn't resolve, and `claude plugin list` is empty.

Work through it in this order:

1. **Is `.claude/settings.json` committed and un-ignored?** `git check-ignore -v .claude/settings.json`.
   A repo that ignores `.claude/` wholesale makes the whole mechanism a no-op for everyone but the
   person who wrote it.
2. **Does it have both keys?** `extraKnownMarketplaces` *and* `enabledPlugins`. An enable naming a
   marketplace the fresh volume has never heard of is dropped as an orphaned entry, silently.
3. **Did fix 5 run?** It is skipped without network, without `jq`, or when `claude` is not yet on
   the PATH at postCreate time. Re-run it by hand:
   `claude plugin marketplace add <owner>/<repo> && claude plugin install <plugin>@<marketplace> --scope project`.
   Both commands are safe to repeat — an already-installed plugin reports its version and exits 0.

### The skill scaffolded something that doesn't match the current standard

The plugin in the user's cache is not the one in the marketplace — installs do not refresh
themselves. `claude plugin list --json` shows the installed version;
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-plugin-version.sh"` compares it against the marketplace
and prints one line. `claude plugin update <plugin>@<marketplace>` fixes it, and **it only takes
effect after a restart** — a session that keeps running is still on the old copy.

### The volume exists but is empty after a rebuild

Check you didn't rebuild with a different `source=` name — changing it (for example switching to
`${localWorkspaceFolderBasename}-claude-config`) creates a fresh, empty volume and leaves the old
one behind. `docker volume ls | grep claude` shows both. Data is recoverable; the old volume is
still there.

## GitHub CLI

### `gh` is installed but not logged in

Most likely the host variable behind `remoteEnv` is not exported. `${localEnv:FOO}` on an unset
variable expands to an empty string — the container starts normally and nothing reports it:

```bash
echo "${GH_TOKEN:-<empty>}"   # inside the container
gh auth status
```

Export `<PROJECT>_GH_TOKEN` in the host shell profile (not just in one terminal — the IDE does not
inherit it from a shell you happened to have open) and **rebuild or restart the container**;
`remoteEnv` is read at container start, so an export made afterwards does not reach it.

### `gh` can read but every write is refused

That is the intended shape: the house standard uses a fine-grained token scoped to this repo with
read-only permissions. If the project genuinely needs the agent to open PRs or comment, raise the
specific permission on the token rather than swapping in a classic PAT — a classic PAT's `repo`
scope covers every repository the user can reach, which is exactly what the per-project token
exists to avoid.

### `git push` works even though the token is read-only

Not a bug, and worth understanding. Opened through VS Code, the Dev Containers extension installs
a git credential helper into the container's `/etc/gitconfig` that proxies to the host's credential
store, so git operations run as the developer's full GitHub identity independently of `GH_TOKEN`.
`git config --show-origin --get credential.helper` shows it. The gh token narrows `gh`, not `git`.

## Networking

### The app isn't reachable from the host

Work through these in order:

1. **Binding.** A server on `127.0.0.1` inside the container is unreachable from outside it. It
   must listen on `0.0.0.0`. Check from inside: `ss -tlnp` — the address column should not be
   `127.0.0.1`. Vite needs `--host`; check your framework's default rather than assuming.
2. **You're using the CLI.** `forwardPorts` is ignored by the devcontainer CLI
   ([devcontainers/cli#186](https://github.com/devcontainers/cli/issues/186)) — it only works
   through the IDE. Use the container's network IP (`hostname -I` inside) instead of
   `localhost`.
3. **Origin checks.** Reaching a dev server by IP rather than `localhost` trips framework
   origin/host allowlists, which usually present as a blocked request rather than a network
   error. The fix is framework-specific — a dev-origin allowlist entry, or an equivalent host
   check setting.

### Everything broke after adding the firewall

Expected, and usually one missing host. The egress allowlist blocks anything not listed — the
package registry, the git remote, the telemetry endpoint the IDE uses. Add the host rather than
removing the firewall. If you need to confirm that's the cause, restart without
`--cap-add=NET_ADMIN` and see if the failure goes away.

## Services and data

### The database is empty after a rebuild, and every image re-pulled

Working as designed, and the most expensive surprise in this setup. Under docker-in-docker the
inner daemon's whole store — images, containers, and named volumes — sits in the devcontainer's
own filesystem at `/var/lib/docker`. A rebuild replaces that filesystem, so all of it goes.
Stop/start is safe; "Rebuild Container" is not.

The data is not recoverable after the fact. What to change so it cannot happen again is step 3 of
SKILL.md: move the services to compose siblings on the outer daemon, bind the data directory onto
the host, or mount a volume at `/var/lib/docker`. If someone is about to rebuild and has data
they care about, `docker compose exec -T postgres pg_dump ...` out to the workspace first — the
workspace is a host bind mount and survives.

### The database is gone after a laptop reboot, but the volume still exists

Different problem, opposite cause: the containers simply are not running. Data is intact. This is
what `postStartCommand` is for — `postCreateCommand` ran once at creation and will not run again.
Check with `docker compose ps` inside the container.

### `docker compose up` fails at container start with "cannot connect to the Docker daemon"

A race, not a breakage: the inner dockerd takes a few seconds and `postStartCommand` got there
first. Wait for it rather than sleeping a fixed amount:

```bash
timeout 60 bash -c 'until docker info >/dev/null 2>&1; do sleep 1; done'
```

### Postgres won't start on a bind-mounted data directory

Permissions. The database runs as its own uid and needs to own its data directory. Pre-create it
with the right ownership, or go back to a volume. If the workspace is on a Windows drive mount
(`/mnt/c/...`) rather than a native Linux filesystem, use a volume — Postgres and that filesystem
disagree about locking and it will not work reliably.

### Compose services can't be reached at `localhost` from the devcontainer

Depends which shape you chose. Under docker-in-docker, compose publishes into the devcontainer's
own network namespace and `localhost` is correct. Under compose siblings, `localhost` only works
if the devcontainer service has `network_mode: service:<db>`; without it, the hostname is the
service name (`postgres`), not `localhost`.

## Things that look like devcontainer problems but aren't

- **Stale framework caches.** A container that builds fine but serves broken output is often a
  build cache written by a different Node version — for Next.js, `rm -rf .next`. These caches
  are in the bind-mounted workspace, so they survive every rebuild.
- **`node_modules` from the host.** Installed on the host before the container existed, they can
  contain platform-specific binaries compiled for the wrong target. Delete and reinstall inside
  the container. Adding `node_modules` to a volume avoids the whole class of problem at the cost
  of it no longer being visible from the host.
