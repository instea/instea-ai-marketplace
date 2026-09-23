---
name: devcontainer-claude-sandbox
description: Scaffold a .devcontainer/ that runs Claude Code sandboxed inside the project's own container — the claude-code and docker-in-docker features, a named volume for the agent's config instead of the host's ~/.claude, and the postCreate fixes that make login, Docker auth, and volume permissions actually work.
disable-model-invocation: true
---

# Claude Code devcontainer sandbox (Instea house standard)

This sets up `.devcontainer/` so that every development command — the agent, the app, the
tests, the database — runs inside a container instead of on the developer's machine.

The point is blast radius. An agent running on the host can read `~/.ssh`, `~/.aws`, browser
profiles, and every other repo you have checked out; a postinstall script in a freshly added
dependency can do the same, with or without an agent involved. Inside a container it sees the
workspace and little else, which is what makes running with loosened permissions a defensible
choice rather than a gamble.

The one piece people get wrong is the agent's own config directory. Mounting the host's
`~/.claude` into the container hands back the credentials you just went to the trouble of
isolating — and that directory has been a target of real supply-chain attacks. So this setup
gives the container a **named Docker volume** for `~/.claude` instead. It never touches the
host's home directory, and it survives rebuilds.

This skill is invoked explicitly, so anything the user typed after the command name is a
deliberate instruction — a target directory, a language, "no docker-in-docker", "add the
firewall". Honour it, and let it override the defaults below rather than re-asking in step 1.

Run the version check in step 0 first, then work through the six steps in order. Steps 1 to 3
carry the judgment; 4 to 6 are mostly mechanical but catch the failures that would otherwise show
up as a broken container on someone else's machine.

## What this protects, and what it does not

Say this plainly in the handover, because a sandbox people over-trust is worse than none.

**Protected:** the host home directory and its credentials, other checkouts on the machine,
host-level packages and daemons. A destructive command or a malicious postinstall hits a
container that can be thrown away.

**Not protected:** the repo itself. The workspace is bind-mounted from the host, so the agent
writes to your real source tree — git is the undo button, so uncommitted work is the thing at
risk. Network egress is unrestricted unless you add the firewall (see Optional additions), so
anything in the container can still reach the internet. And any value passed through
`remoteEnv` is readable by the agent, by design.

## Step 0 — Check you are running the current house standard

You are running from whatever version of this plugin is in the user's cache, and nothing updates
that automatically. Months-old copies are the normal case, not the exception — so check before
scaffolding a standard that has since moved on:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-plugin-version.sh"
```

One line out, exit 3 when stale. It skips itself when the plugin root is a checkout of the
marketplace (working in the marketplace repo, or `claude --plugin-dir`), and treats being offline
as unknown rather than as a failure — never block a scaffold on it.

If it reports STALE, say so, give the user the update command it prints, and add that **a restart
is required** before the new version loads. Then ask whether to continue on the version you have
or stop and update — either answer is reasonable, and it is their call. Do not update the plugin
yourself.

One honest limitation to keep in mind: this check ships *with* a version, so a user still on an
older one will never run it. The first time it helps is the release after the one they install.

## Step 1 — Survey the project

**Check for an existing `.devcontainer/` first.** If one exists, do not overwrite it — read it,
tell the user what it already has and what is missing (usually the claude-code feature and the
config volume), and offer to patch those in. A working devcontainer encodes environment details
that are invisible from the outside.

```bash
ls -la .devcontainer/ 2>/dev/null && cat .devcontainer/devcontainer.json
```

Then gather five things:

**The stack and package manager.** The lockfile is the authority, not the README:
`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `package-lock.json` → npm. Node repos get
`ghcr.io/devcontainers/features/node:1`; read `engines.node` or `.nvmrc` for the version and
fall back to `lts`. For other stacks swap the feature — `features/python:1`, `features/go:1`,
`features/rust:1` — and keep everything else in this skill identical, since the Claude-specific
parts have nothing to do with the language.

**Whether it needs Docker inside.** A `docker-compose.yml`, a `Dockerfile`, or tests that spin
up Testcontainers all mean yes, and the `docker-in-docker` feature goes in. If nothing in the
repo runs containers, leave it out — it adds real build time and has known limitations on some
image architectures.

**The ports.** Read the dev script and any compose `ports:` entries rather than assuming the
framework default; these become `forwardPorts`.

**Whether the repo lives on GitHub.** `git remote -v` — if the remote is GitHub, the scaffold
gets the `github-cli` feature and a project-prefixed token variable (step 2 covers the naming and
why it is not the host's usual `GITHUB_TOKEN`). No GitHub remote, no feature.

**The remote user.** This one matters more than it looks. It comes from the base image —
`mcr.microsoft.com/devcontainers/base:ubuntu` gives you `vscode`, the Node images give you
`node` — and the config volume must be mounted at *that* user's home. Mount it at the wrong
path and nothing errors: Claude simply reads an empty `~/.claude` and the volume sits unused,
so logins stop persisting and nobody can see why.

**Confirm before writing.** This is the one place to ask, so cover everything you need in three
or four lines: the base image and remote user, the features you're adding, the ports, whether the
config volume is shared or per-project (step 2 explains the trade-off), the host variable name the
gh token will come from, and how the project's services will run if it has any (step 3). Getting
the remote user or the volume path wrong produces a container that looks fine and quietly loses
state, so it is worth the one round-trip.

## Step 2 — Write the devcontainer files

Copy what applies from `assets/`, then adapt:

| File | Purpose |
|---|---|
| `assets/devcontainer.json` | Features, the config volume, ports, extensions |
| `assets/Dockerfile` | Only what the features don't cover |
| `assets/postCreateCommand.sh` | The four fixes that make the container usable |
| `assets/postStartCommand.sh` | Bringing services up on every start (step 3, option B only) |
| `assets/claude-settings.json` | The repo's `.claude/settings.json` — the house plugins |
| `scripts/check-devcontainer.py` | Validates the result in step 5 |
| `../../scripts/check-plugin-version.sh` | Plugin-level; the staleness check from step 0 |

### The config volume

This is the security core, so get the mount right:

```jsonc
"mounts": ["source=claude-code-config,target=/home/vscode/.claude,type=volume"]
```

`target` must be `<remote user's home>/.claude` from step 1. Note that devcontainer variable
substitution won't help here — `${containerEnv:HOME}` isn't resolvable at container-creation
time, when mounts are applied — so this path is written out literally. That is exactly why
step 1 asks for the remote user.

`source` is a decision worth making deliberately:

- **A shared `claude-code-config`** (the default, and what our demo repo uses) means one login
  covers every project on the machine. Convenient, and still a large improvement over mounting
  the host home directory.
- **Per-project**, via `source=${localWorkspaceFolderBasename}-claude-config`, means a
  compromised dependency in one repo cannot read the agent credentials of another. Prefer this
  for client work, for repos with dependencies you don't control, or any time the projects on
  the machine shouldn't share a trust boundary. The cost is a login per project.

You raised this in step 1's confirmation — don't ask again here, just apply what was decided.

### The Dockerfile

Keep it thin. Features already install the language toolchain, Docker, and Claude Code, so this
file is only for things the team expects in every shell.

**Always install `jq`.** `postCreateCommand.sh` reads `.claude/settings.json` with it to install
the repo's plugins, and Claude Code hooks are shell scripts that parse a JSON payload from stdin,
so the first hook anyone adds needs it too — discovering that inside a container, from a hook that
fails silently, is a bad afternoon. This is why a new scaffold gets a Dockerfile rather than
pointing `"image"` straight at the base: one small layer now beats a rebuild later.

When you are *patching* an existing image-only devcontainer, converting it to a build purely for
`jq` is a bigger change than it looks — it moves the project onto a locally-built image. Either
add the small Dockerfile or install `jq` at the top of `postCreateCommand.sh`; both are fine,
just say in the handover which you did and why.

Combine the `apt-get` calls into one `RUN` with `rm -rf /var/lib/apt/lists/*` at the end;
separate `RUN apt-get install` lines each keep their own layer of package index, and a stale
`apt-get update` layer causes install failures weeks later that look like network errors.

### The GitHub CLI

A repo with a GitHub remote gets `ghcr.io/devcontainers/features/github-cli:1`. Almost everything
the agent wants to do with GitHub — reading an issue, checking why CI is red, looking at a PR
diff — goes through `gh`, and without it the agent falls back to scraping the web or asking you.

How the token gets in is the part worth thinking about:

```jsonc
"remoteEnv": { "GH_TOKEN": "${localEnv:<PROJECT>_GH_TOKEN}" }
```

Three deliberate choices in that one line:

- **A fine-grained token, read-only, scoped to this repository.** Contents, Metadata, Issues and
  Pull requests at *Read*. Write access turns "the agent can look things up" into "the agent can
  push, merge and close things" — offer it only if the user asks, and say plainly what it buys
  and costs. A classic PAT is the wrong instrument here: its `repo` scope covers every repo the
  user can reach, which is precisely what the project prefix exists to prevent.
- **A project-prefixed host variable**, not the `GITHUB_TOKEN` the developer already has exported.
  Everything in `remoteEnv` is readable by the agent by design, so the token's scope is the only
  real control — and a shared variable means the token in this container is a key to every other
  repo on the machine. `<PROJECT>_GH_TOKEN` keeps one project's blast radius to one project.
- **`GH_TOKEN`, not `GITHUB_TOKEN`, as the container-side name.** `gh` reads both, but
  `GITHUB_TOKEN` is also what Actions injects, and reusing it makes the local value hard to tell
  apart from CI's later.

Two things to warn about, because both fail quietly:

`${localEnv:FOO}` on a variable the host has not exported expands to an empty string — no error,
no warning, and `gh` is simply not logged in. `gh auth status` inside the container is the check;
put it in the handover.

And be honest about what this does *not* isolate: opened through VS Code, the Dev Containers
extension installs a git credential helper into the container's `/etc/gitconfig` that proxies to
the host's credential store, so `git push` already runs as the developer's full GitHub identity no
matter what `GH_TOKEN` says. A read-only gh token narrows what `gh` can do, not what `git` can do.
(The devcontainer CLI does not install that helper, so terminal-only users get the gh token and
nothing else — which also means `git push` will ask them for credentials.)

### Extensions

Put them under `customizations.vscode.extensions`. A top-level `"extensions"` key is the old
pre-`customizations` schema; it is deprecated, and tooling other than VS Code ignores it
outright — the extensions just never install and no error explains why. If you are patching an
existing devcontainer and find a top-level `extensions` or `settings` key, move it and mention
that you did.

### The repo's Claude settings

The container's `~/.claude` is a fresh, empty volume — that is the whole point of it. Nothing the
developer has installed on their laptop crosses that boundary, so unless the repo says otherwise
the agent inside the sandbox has none of the house skills. The repo's committed
`.claude/settings.json` is the only channel that reaches every developer's container, so **always**
write these two keys into it (`assets/claude-settings.json` is the same file, ready to copy):

```json
{
  "extraKnownMarketplaces": {
    "instea-ai-marketplace": {
      "source": { "source": "github", "repo": "instea/instea-ai-marketplace" }
    }
  },
  "enabledPlugins": { "project-setup@instea-ai-marketplace": true }
}
```

**Both keys, always.** `enabledPlugins` on its own names a marketplace the fresh volume has never
heard of; Claude Code drops it as an orphaned entry and starts with the plugin absent and no error
anywhere — the skills are simply not there, and the developer has nothing to search for.
`extraKnownMarketplaces` is what registers the source so the enable resolves. The two are a pair.

**Merge, never overwrite.** Plenty of repos already keep `permissions` or `hooks` here — the
notify.sh addition below writes hooks into this very file. Merge into the two objects and preserve
every existing member, the same way step 1 patches an existing `.devcontainer/` rather than
replacing it.

It must be `settings.json`, not `settings.local.json`: the local variant is personal and
git-ignored, so it reaches nobody. Check the file can actually be committed —

```bash
git check-ignore -v .claude/settings.json
```

A repo that ignores `.claude/` wholesale turns this step into a silent no-op for everyone but you.
Un-ignoring it takes two lines, not one:

```gitignore
.claude/*
!.claude/settings.json
```

The obvious fix — keeping `.claude/` and adding the negation — does nothing at all. Git never
descends into an excluded *directory*, so a negation for a file inside one is never even
consulted; the pattern has to exclude the contents (`.claude/*`) for the negation to be reachable.
`git check-ignore -v` names the line that decided, which is the quickest way to see this.

Tell the user to commit the file in the handover.

Fix 5 of `postCreateCommand.sh` then reads this same file at container creation and installs what
it declares, so the first session starts with the house skills already present instead of fetching
them halfway through your first request. It reads the file rather than hardcoding the two house
names, which is what keeps it correct for a repo that later adds a third plugin. Nothing in that
block is fatal — a container built without network is still a usable container, and Claude Code
falls back to fetching the marketplace on first start, which is the behaviour you get today.

The equivalent CLI is `claude plugin marketplace add instea/instea-ai-marketplace --scope project`
followed by `claude plugin install project-setup@instea-ai-marketplace --scope project`. It writes
the same shape, but it also clones the marketplace into the machine you happen to be running on,
so prefer editing the JSON.

## Step 3 — Decide how the project's services run

Skip this if the repo has no compose file and nothing to run alongside the app.

Everything here turns on one question: **does the agent itself need to run `docker`?** Building
images, Testcontainers, or a task that shells out to `docker` means yes. "The app needs a
database" means no — and that distinction decides whether the developer keeps their data.

### The trap worth knowing before you choose

With docker-in-docker, the inner daemon's entire state — images, containers, *and named volumes*
— lives inside the devcontainer's own filesystem under `/var/lib/docker`. Stopping and starting
the devcontainer keeps all of it. **Rebuilding destroys all of it.**

That matters because "Rebuild Container" is the move everyone reaches for the moment anything
looks wrong. It silently drops the developer's database and re-pulls every image, and nothing in
the UI suggests that is about to happen. Assume any project whose compose file holds real
development data will hit this, and choose accordingly.

### Option A — services as compose siblings (prefer this when the agent doesn't need Docker)

Instead of running compose *inside* the devcontainer, make the devcontainer one service in a
compose project and the database another, both on the outer daemon the IDE already uses. The
database volume then belongs to that compose project and survives every devcontainer rebuild,
there is no nested daemon to slow things down, and the sandbox is untouched — the devcontainer
gets no Docker socket, so it can reach postgres over the network but cannot drive the host
daemon.

`.devcontainer/docker-compose.yml` adds the devcontainer alongside the project's existing file:

```yaml
services:
  devcontainer:
    build:
      context: ..
      dockerfile: .devcontainer/Dockerfile
    volumes:
      - ..:/workspace:cached
      - claude-code-config:/home/vscode/.claude   # the agent config volume lives HERE now
    command: sleep infinity
    network_mode: service:postgres

volumes:
  claude-code-config:
```

```jsonc
{
  "dockerComposeFile": ["../docker-compose.yaml", "docker-compose.yml"],
  "service": "devcontainer",
  "workspaceFolder": "/workspace"
}
```

Two things about this shape are easy to get wrong and fail quietly:

- **`mounts` in devcontainer.json is not honoured for compose-based configs.** Leave the config
  volume there and it simply never mounts — the agent reads an empty `~/.claude` and logins stop
  persisting, with no error. It must move into the compose file's `volumes:`, as above.
- **`network_mode: service:postgres`** puts the devcontainer in the database's network namespace,
  which is what keeps `localhost:5432` working so `DATABASE_URL` needs no edit. The cost is that
  the devcontainer can no longer publish its own ports — they must be published on the `postgres`
  service instead. If that gets confusing, drop `network_mode`, let both services share the
  default network, and change the app's host from `localhost` to `postgres`. Say which you chose.

### Option B — docker-in-docker (when the agent genuinely needs Docker)

Keep the feature, and then deal with the data loss directly. Two ways, and they compose:

**Bind the service's data onto the host filesystem**, so it never lives in the inner daemon at
all. In the project's compose file, replace the named volume with a path inside the workspace:

```yaml
    volumes:
      - ./.data/postgres:/var/lib/postgresql/data   # instead of: postgres_data:/var/...
```

The workspace is bind-mounted from the host, so this survives anything. Add `.data/` to
`.gitignore`. Two caveats: the database runs as its own uid and may need the directory
pre-created with the right ownership, and this goes badly if the workspace sits on a Windows
drive mount rather than a native Linux filesystem — on WSL, keep the repo under `~`, not
`/mnt/c`.

**Persist the inner daemon's whole store** by mounting a volume at `/var/lib/docker`:

```jsonc
"source=${localWorkspaceFolderBasename}-dind,target=/var/lib/docker,type=volume"
```

This keeps the image cache too, which is the other thing rebuilds throw away. Be honest that the
docker-in-docker feature does not document this: it is a community workaround, it assumes a
consistent storage driver, an unclean shutdown can leave the store inconsistent, and the volume
grows without bound until someone prunes it. Offer it, explain the caveat, and let the user
decide rather than adding it silently.

### Never — the host Docker socket

`docker-outside-of-docker`, or bind-mounting `/var/run/docker.sock`, makes all of this go away:
the services run on the host daemon and nothing is ever lost. It is still the wrong answer here.
Access to that socket is effective root on the host — anything in the container can start a
privileged container mounting `/` — so it hands back exactly the isolation this whole setup
exists to create. If a project already does it, say so plainly and offer Option A instead.

### Lifecycle: postCreate versus postStart

`postCreateCommand` runs **once**, when the container is created. `postStartCommand` runs on
**every start**, including after a plain stop/start or a laptop reboot.

Bringing services up belongs in `postStartCommand`. Containers are not running after a restart
even though their data is still there, so a `docker compose up -d` in `postCreateCommand` leaves
the developer with a dead database on the second day and no clue why. Under Option B the inner
daemon also needs a moment before it accepts connections, so wait for it rather than racing it:

```bash
#!/bin/bash
set -e
timeout 60 bash -c 'until docker info >/dev/null 2>&1; do sleep 1; done'
docker compose up -d
```

One-time setup — dependency installs, `go-offline`, fetching a schema — stays in
`postCreateCommand`. Be careful adding a dependency install there: the script runs under
`set -e`, so a failed install aborts container creation and the error points at the container
rather than at the install.

## Step 4 — Make the app reachable from the host

Port forwarding is where a technically-correct container becomes unusable, and there are two
separate traps.

**The server must bind `0.0.0.0`, not `localhost`.** A process listening on `127.0.0.1` inside
the container is unreachable from outside it, so forwarding a port to it gets you a connection
refused. Some dev servers already bind all interfaces; Vite notably does not without `--host`.
Check the dev script and say what you changed if you changed it.

**`forwardPorts` only works in the IDE.** The devcontainer CLI ignores it
([devcontainers/cli#186](https://github.com/devcontainers/cli/issues/186)), so terminal-only
developers reach the app at the container's network IP rather than `localhost`. That in turn
trips framework origin checks that assume `localhost`. The fix is framework-specific and often
version-specific — Vite's `server.allowedHosts` only exists in 5.4.12+/6.x, and Next has its own
dev-origin allowlist — so check the installed version before writing a key that may not resolve,
and say so rather than guessing. Set `forwardPorts` for the IDE users regardless, and call out
the CLI limitation in the handover instead of trying to paper over it.

## Step 5 — Build it

Run the bundled checker, then actually build. A container that has never been built is a guess:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/devcontainer-claude-sandbox/scripts/check-devcontainer.py" .
devcontainer build --workspace-folder .
```

`check-devcontainer.py` covers the failures that are invisible in a diff: a mount target that
doesn't match `remoteUser`, a config volume declared in `devcontainer.json` under a compose-based
setup (where it is ignored), a missing fix in the postCreate script, a deprecated top-level
`extensions` key, docker-in-docker over a compose file with no persistence, a `github-cli` feature
with no token or a token taken from a shared host variable, and the two newer postCreate fixes —
the npm chown and the plugin warm-up — which are WARNs rather than FAILs so that devcontainers
generated by an earlier version of this skill don't start failing. It exits non-zero on
real failures and prints `WARN` for judgment calls that may be right for the project — read
those, don't just check the exit code.

Do not hand-roll the JSON check. `devcontainer.json` is JSONC, and the obvious one-liner —
stripping comments with `re.sub(r'//.*', '', s)` — corrupts every `"https://..."` string value
and reports a parse error in a file that is perfectly valid. The script strips comments while
tracking string state, which is the only way to get this right.

`devcontainer` is often not installed on the host, since the whole point is that the IDE
extension usually drives it. If the CLI or Docker is missing, say so explicitly and tell the
user to run it themselves — do not report success on a container you never built.

If the build succeeds, `devcontainer up --workspace-folder .` then
`devcontainer exec --workspace-folder . bash -lc 'claude --version && node --version && docker ps'`
is worth the extra minute: it is the only check that proves the postCreate script ran, the
volume is writable, and Docker-in-Docker actually came up.

## Step 6 — Hand over

Close with a short handover covering exactly these points:

1. **How to get in** — `devcontainer up` then `devcontainer exec bash`, or "Reopen in Container"
   in VS Code. Include how to rebuild, since that is the fix for most later confusion:
   `devcontainer up --remove-existing-container`, or the "Dev Containers: Rebuild Container"
   command.
2. **First login** — Claude Code needs an interactive login once; after that the volume keeps
   it across rebuilds. If it ever stops persisting, the symlink in fix 3 of the postCreate
   script is the thing to check.
3. **The house plugins** — `.claude/settings.json` must be committed or nobody else gets them.
   `postCreateCommand.sh` installs them at container creation, so they are there before the first
   prompt; Claude Code still asks once to trust `project-setup`. If the container was built
   without network, the first session fetches the marketplace instead — that run needs network.
4. **The gh token** — the host variable the container expects (`<PROJECT>_GH_TOKEN`), what it
   should be (a fine-grained, read-only, this-repo-only token), and that it must be exported in
   the host shell profile *before* reopening the container. Tell them to confirm with
   `gh auth status` inside, since an unset variable produces no error at all. Say in the same
   breath that this does not constrain `git` itself — VS Code forwards the host's git credentials
   separately.
5. **Ports** — what is forwarded, and the CLI caveat from step 4.
6. **What you verified** — the build result, or plainly that you could not build it here.
7. **What the sandbox does not cover** — the "Not protected" list above, in one line. People
   will run the agent with loosened permissions on the strength of this setup; they should know
   the repo is still live and egress is still open.
8. **What a rebuild will cost** — if the project ended up on docker-in-docker, state plainly
   whether a rebuild wipes the database and image cache, and what you did about it. This is the
   single most surprising behaviour in the whole setup, and the developer will hit it.
9. **Superseded setup** — if the repo has a `Vagrantfile`, an ad-hoc `docker-compose` dev
   service, or a README section telling people to install Node locally, point out the overlap.
   Don't delete it; retiring the old path is the team's call.

## Why the template looks like this

Each of these cost someone an afternoon. If you want to "clean one up", read the reason first.

**`sed -i '/credsStore/d' ~/.docker/config.json`.** With docker-in-docker the container can
inherit a Docker config that names a credential helper binary that isn't installed there. Every
pull then fails with `docker: error getting credentials - err: exit status 255, out: ``` — a
message that leads nowhere. Deleting the line falls back to plain config, which is fine inside
a throwaway container.

**`chown` on the config directory.** Docker creates named volumes owned by root. The remote
user cannot write to its own `~/.claude`, and Claude fails on first start with a permission
error that reads like a bug in Claude.

**The `.claude.json` symlink.** Claude keeps session and auth state in `~/.claude.json` — beside
the `.claude` directory, not inside it — so the volume alone does not persist your login. You
cannot bind-mount a file that doesn't exist yet, which rules out the obvious fix, so the script
creates the file inside the volume and symlinks it into the home directory. The `[ -f ... ] ||`
guard is what stops a rebuild from wiping an existing session.

**`chown` on `$(npm root -g)/@anthropic-ai`.** The claude-code feature installs the npm package
as root, so the remote user's auto-update fails with `Auto-update failed: no write permission to
npm prefix` and the container is stuck on whatever version the image shipped — a message that
reads like an npm misconfiguration and sends people off editing `.npmrc`. Only that one subtree is
root-owned; the npm prefix itself is already group-writable, so chowning the package is the whole
fix. `~/.claude/.last-update-result.json` records the outcome, which is the quickest confirmation.
The update lands in the container's filesystem rather than on the config volume, so a rebuild drops
back to the feature's version — that part is intended, since the image is what pins the baseline.

**Reading `.claude/settings.json` in fix 5 rather than hardcoding the plugin names.** The block
exists so the house skills are installed before the first prompt, and the committed settings file
is the one place that already knows which plugins a repo wants. Hardcoding the two house names
would work today and be wrong the moment a project adds a third. It also means the failure mode is
benign: no settings file, no jq, no network, and the script simply does nothing.

**`"moby": false` on docker-in-docker.** Installs upstream Docker CE rather than the Moby
build. Set it deliberately: the two differ in versioning and in which architectures they work
on, and switching after the fact invalidates the image cache for everyone.

**`$HOME` and `id -un` in the postCreate script, not `vscode`.** The script is the one file that
gets copied between projects with different base images. Hardcoding `vscode` makes it fail on a
Node-based image with a `chown: invalid user` that has nothing to do with what actually went
wrong.

**Features are pinned to a major version** (`node:1`, `docker-in-docker:3`). That matches the
rest of the org. The CLI writes a `devcontainer-lock.json` recording the exact resolved digests,
and it is what makes two developers' containers identical — so commit it when it exists. It is
generated during `devcontainer up`/`build`, which means you cannot produce one on a host without
the CLI. That is fine: note in the handover that the first person to bring the container up will
generate it and should commit it. Don't hand-write one.

**`extraKnownMarketplaces` beside `enabledPlugins`.** It looks redundant — the plugin id already
contains `@instea-ai-marketplace` — and it is the first thing someone deletes while tidying. It is
not redundant: the id is a name, and a container whose `~/.claude` is a fresh volume has no record
of what that name points at. Claude Code skips the enable as an orphaned entry, silently, and the
house skills never load. Deleting this key produces a repo that works on the machine where it was
written and nowhere else.

## Optional additions

Offer these when they fit. Don't add them unasked; the plain setup is what the team reviews at
a glance.

**Network firewall.** The biggest remaining gap: a container with unrestricted egress can still
exfiltrate whatever it can read. An egress allowlist belongs at the end of
`postCreateCommand.sh`, and Anthropic publishes a working example rather than something worth
reinventing:
[init-firewall.sh](https://github.com/anthropics/claude-code/blob/main/.devcontainer/init-firewall.sh).
It needs `"runArgs": ["--cap-add=NET_ADMIN"]` in `devcontainer.json`. Warn that it will break
any tooling reaching a host you forgot to list, which is the usual reason it gets ripped out —
`github.com` is one to get right, since the house plugins from step 2 are fetched from there on
the container's first start.

**Host notifications.** Notifications raised inside a container never reach the host desktop, so
long agent runs finish silently. `assets/notify.sh` sends them out through
[apprise](https://github.com/caronc/apprise) instead. It needs three things: `apprise` in the
Dockerfile (`pipx install apprise` as the remote user), the destination URL forwarded in with
`"remoteEnv": {"CLAUDE_NOTIFY_URL": "${localEnv:CLAUDE_NOTIFY_URL}"}`, and `Stop` plus
`Notification` hooks in `.claude/settings.json` pointing at the script. Mention that the URL is
readable by the agent, so use a channel you'd be comfortable with it seeing.

**A README section.** For a repo where the container is now the only supported way to develop,
the entry commands belong in the README rather than only in this conversation. Offer it; some
teams keep that in an internal wiki instead.

**Dotfiles.** `"dotfiles.repository"` in devcontainer.json lets each developer bring their own
shell setup without adding personal tooling to a shared Dockerfile. Good answer to "can I have
my zsh config in here".

## Reference

`references/troubleshooting.md` — symptoms and causes for the failures this setup actually
produces: credential errors, permission errors, logins that don't persist, unreachable ports,
Docker-in-Docker not starting. Read it when something comes back broken, rather than guessing
from the log.
