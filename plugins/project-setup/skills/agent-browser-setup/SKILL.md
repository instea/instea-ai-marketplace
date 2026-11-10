---
name: agent-browser-setup
description: Set up agentic browser control in the current repo's dev container, so Claude Code there can drive the separate agent Brave (or Chrome) on the Windows host through the chrome-devtools MCP server and the browser's consent-based remote debugging. Copies the bridge kit into .devcontainer/chrome-bridge/, registers the chrome-devtools MCP server (committed in .mcp.json, or personal in Claude's local config), checks the connection and says what to do on Windows if the browser is not reachable. Use when the user asks to set up, add, enable or copy browser control, the agentic or agent browser, agent Brave, the chrome-devtools MCP or the Chrome bridge into this repo, project or dev container, or asks why Claude has no browser tools in a dev container.
disable-model-invocation: true
---

# Agent browser setup

Claude Code runs sandboxed in a dev container; the agent browser runs on the
Windows host as its own Brave (or Chrome) instance with a separate user data dir,
remote debugging turned on at `127.0.0.1:9333`. The kit in
`assets/chrome-bridge/` connects the two:

- `mcp-server.sh` is what the `chrome-devtools` MCP server runs. It starts a
  relay from container `127.0.0.1:9333` to `host.docker.internal:9333` (socat if
  installed, otherwise Node), writes a stand-in `DevToolsActivePort`, and runs
  `chrome-devtools-mcp --autoConnect` against it.
- `check.sh` tests each hop.
- `start-agent-brave.bat` starts the agent Brave on Windows.
- `README.md` explains why each piece is needed, plus setup, security and
  troubleshooting. It goes into the repo next to the scripts. Read it when a step
  below fails instead of guessing.

The Windows side is once per machine and shared by every container. If the user
already uses the agent browser from another container, there is nothing to do
on Windows.

## 1. Pick the repo and the scope

- Repo root: `git rev-parse --show-toplevel` from the current directory.
- Check that this is a container (`/.dockerenv` exists, or
  `host.docker.internal` resolves). If Claude runs directly on the machine that
  has the browser, this kit is not needed; plain `chrome-devtools-mcp
  --autoConnect` works there. Say so and stop.
- Scope:
  - **project** (default): the kit and the `.mcp.json` entry are meant to be
    committed. Anyone who opens the repo in Claude gets a
    one-time prompt to approve the server.
  - **local**: personal. The kit is git-ignored through `.git/info/exclude` and
    the server is registered in Claude's local config for this checkout; nothing
    shows up for others.

  If other people commit to the repo (`git shortlog -sne HEAD | wc -l` is more
  than 1), ask which scope the user wants. Committing it proposes a path from
  every teammate's agent into a logged-in browser, which is the team's call.
  Otherwise use project.

## 2. Install

```bash
bash <this skill's directory>/scripts/install.sh --scope <project|local> <repo root>
```

It is safe to re-run, and leaves identical files alone. Go through the output;
lines marked `!!` need you:

| Output | What to do |
|---|---|
| `<file> differs from the kit — kept` | Someone changed the file, or it is from an older kit. Show the user the diff (the line prints the command) and ask before re-running with `--force`. |
| `.mcp.json: differs: …` | The repo already has a different `chrome-devtools` server (maybe a headless Chrome for tests). Show it and ask; `--force` replaces it. Don't rename ours to sneak around it. |
| `node … not found` / `too old` | chrome-devtools-mcp needs Node ^20.19, ^22.12 or 23+. Add `"ghcr.io/devcontainers/features/node:1": {"version": "lts"}` to `features` in `devcontainer.json` and tell the user to rebuild the container. Nothing else works before that. |
| `host.docker.internal does not resolve` | Docker Desktop provides it, so this is an unusual setup. Ask before adding `"runArgs": ["--add-host=host.docker.internal:host-gateway"]` (merge into existing `runArgs`); it needs a rebuild. |
| `egress firewall likely` | Add a rule in the firewall script that allows outbound TCP to `host.docker.internal`'s address on port 9333. Also allow the npm registry if it is not allowed yet, for the first `npx` download. Show the user the change. |

No Dockerfile change is needed: without socat the relay runs on Node.

## 3. Check the path to the browser

`check.sh` opens a real debugging connection, so the browser asks for
permission. Tell the user before running it: *"Click **Allow** in the agent
browser when it asks. The dialog is in its last active window."* Then run:

```bash
<repo root>/.devcontainer/chrome-bridge/check.sh
```

It waits up to 60 s for the click. Success is OK on every step, with step 3
ending in `HTTP/1.1 101`. Step 4 saying the relay is not running yet is normal.

If it fails, the step number names the broken hop; see Troubleshooting in
`assets/chrome-bridge/README.md`. The common case is **step 2, Connection
refused**: the agent browser isn't running or remote debugging is off. Ask the
user to start it on Windows with `start-agent-brave.bat`. Any copy works, and
the one in this repo is at `\\wsl.localhost\<distro>\<path>\.devcontainer\chrome-bridge\`
when the repo is in WSL. On a machine where the agent browser has never been
set up, its first run opens `brave://inspect/#remote-debugging`. There the user
turns remote debugging on (it should say `127.0.0.1:9333`) and logs in to the
sites the agent needs. Run `check.sh` again only after the user says it's done,
because every run brings up another dialog.

## 4. Hand over

Claude loads MCP servers when it starts, so the browser tools only appear in a
new session. Tell the user to:

1. Exit Claude and start it again **from the repo root**. `claude --continue`
   resumes this conversation.
2. Approve the `chrome-devtools` server when asked (project scope only). To skip
   that prompt, add `"enabledMcpjsonServers": ["chrome-devtools"]` to
   `.claude/settings.local.json`.
3. Run `/mcp`; `chrome-devtools` should be connected. Then ask Claude to *"list
   the open pages in the browser"* and click Allow. Check that the tabs are the
   agent browser's.

Finally, list what changed. Don't commit unless asked. For project scope, offer a
README line that points to `.devcontainer/chrome-bridge/README.md`, and add it
only if the user wants it.

## Notes

- One relay per container, shared by all Claude sessions in it. State is in
  `/tmp/chrome-bridge/` (`relay.log`, the stand-in `DevToolsActivePort`).
- Every container uses port 9333, the port `start-agent-brave.bat` pins
  (`AGENT_BRAVE_PORT`). A different port goes into `CHROME_DEBUG_PORT`, in the
  shell that starts `claude` or under `env` in `.claude/settings.local.json`.
- chrome-devtools-mcp is pinned in `mcp-server.sh`. When you update the kit,
  re-running `install.sh` in a repo reports which files are out of date.
