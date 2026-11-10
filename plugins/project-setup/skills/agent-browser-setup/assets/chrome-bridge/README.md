# Browser bridge: let Claude in the dev container drive the agent browser on Windows

Claude Code runs sandboxed in this repo's dev container. This folder lets it
use the [chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp)
server against a browser running on the Windows host: a separate **agent
Brave** (or Chrome) instance with its own profile, logins and tabs. The
container does not launch a throwaway browser. The browser asks you to **Allow**
every connection.

Requirements: Windows host, Docker Desktop (WSL2 backend), Brave or Chrome
based on Chromium **144+**, Node ^20.19, ^22.12 or 23+ in the container.

The Windows side is set up **once per machine**. Every dev container on that
machine can connect to the same agent browser.

## How it works

```
 dev container                                              Windows host
┌──────────────────────────────────────────────────┐       ┌──────────────────────────┐
│ claude                                           │       │ agent Brave / Chrome     │
│  └─ chrome-devtools MCP server                   │       │   own --user-data-dir    │
│      └─ mcp-server.sh                            │       │   remote debugging on in │
│          └─ chrome-devtools-mcp --autoConnect    │       │   brave://inspect        │
│             reads stand-in DevToolsActivePort    │       │                          │
│             ws://127.0.0.1:9333/devtools/browser │       │   127.0.0.1:9333         │
│                   │                              │       │    ▲                     │
│      relay 127.0.0.1:9333 ───────────────────────┼───────►│────┘ "Allow remote       │
│      (socat, or node)                            │       │      debugging?" dialog  │
│        → host.docker.internal:9333               │       │                          │
└──────────────────────────────────────────────────┘       └──────────────────────────┘
```

Plain `--autoConnect` cannot reach the browser from a container, for three
reasons:

1. **autoConnect only discovers a local browser.** It reads `DevToolsActivePort`
   (port, then websocket path) from the user data dir on the *same* machine. The
   real file is in the Windows profile, out of the container's reach.
2. **The browser listens on Windows `127.0.0.1` only, and checks the Host
   header.** Any request whose Host is not an IP or `localhost` gets HTTP 500
   (*"Host header is specified and is not an IP address or localhost"*), so
   `host.docker.internal:9333` is refused even when it can be reached.
3. **The chrome://inspect server only speaks the browser websocket.**
   `/json/version` returns 404, so `--browserUrl` does not work either.

The scripts here get around this:

- **[`mcp-server.sh`](mcp-server.sh)** is the command the `chrome-devtools` MCP
  server runs. It does three things:
  - Starts a **relay** from container `127.0.0.1:<port>` to
    `host.docker.internal:<port>`. Docker Desktop routes that to Windows, and the
    Host header stays `127.0.0.1`. The relay is `socat` when it is installed,
    otherwise a few lines of Node, so the container needs no extra package.
  - Writes a **stand-in `DevToolsActivePort`** (`<port>` and `/devtools/browser`)
    into `/tmp/chrome-bridge`. A server started from chrome://inspect does not
    need the per-launch UUID in the path, so this static file survives browser
    restarts and nothing has to be synced from Windows.
  - Runs `chrome-devtools-mcp --autoConnect --userDataDir /tmp/chrome-bridge`.
- **[`check.sh`](check.sh)** tests each hop and tells you which one is broken.
- **[`start-agent-brave.bat`](start-agent-brave.bat)** starts the agent Brave on
  Windows.

## One-time setup on Windows

Remote debugging covers a **whole browser instance**, not one profile. Turned on
in your everyday browser, it would let the agent read your mail, chat and
everything else you are logged into. So the agent gets its own instance with a
separate user data dir.

**Brave:** run [`start-agent-brave.bat`](start-agent-brave.bat) on Windows. A
repo in WSL is visible there at `\\wsl.localhost\<distro>\<path>`; a desktop
shortcut to the script works well. cmd's "UNC paths are not supported" warning
is harmless, because the script doesn't use the current folder.

1. The script starts Brave with `--user-data-dir=%LOCALAPPDATA%\BraveAgent`.
   Override this with `AGENT_BRAVE_DIR`.
2. It pins the debugging port to **9333** (override with `AGENT_BRAVE_PORT`). It
   does this by writing the port into `DevToolsActivePort` before launch,
   because Brave starts its server on the port it finds there.
3. On the first run it opens `brave://inspect/#remote-debugging`. Turn remote
   debugging on there; the page should say `127.0.0.1:9333`. Then log in to the
   sites the agent needs, in that window only. The setting stays on after
   restarts until you turn it off.
4. Keep remote debugging **off** in your everyday browser.

**Chrome:** do the same by hand. Make a shortcut to
`chrome.exe --user-data-dir="%LOCALAPPDATA%\ChromeAgent"`, enable remote
debugging in `chrome://inspect/#remote-debugging` in that window, and set
`CHROME_DEBUG_PORT` to the first line of
`%LOCALAPPDATA%\ChromeAgent\DevToolsActivePort`.

## Container side

| File | Purpose |
|---|---|
| `.mcp.json` (or Claude's local config) | Registers the `chrome-devtools` server |
| [`mcp-server.sh`](mcp-server.sh) | Relay, stand-in file, server |
| [`check.sh`](check.sh) | Diagnostics |
| [`start-agent-brave.bat`](start-agent-brave.bat) | Windows: starts the agent Brave on port 9333 |

Start `claude` from the repo root: `.mcp.json` points at the script with a
relative path. The first time, Claude asks you to approve the project MCP
server. To skip that question, add `"enabledMcpjsonServers": ["chrome-devtools"]`
to `.claude/settings.local.json`.

## Verify

1. In the container, run `.devcontainer/chrome-bridge/check.sh`. When it says
   so, click **Allow** in the agent browser. Every step should print OK, and
   step 3 should end with `HTTP/1.1 101`.
2. In Claude, run `/mcp`. `chrome-devtools` should show as connected.
3. Ask Claude to *"list the open pages in the browser"* and click **Allow**.
   Check that the tabs listed are the agent browser's.

## Daily use

- Start the agent browser before you need it.
- Each new MCP connection shows the **Allow** dialog: one per Claude session,
  and again after the browser restarts. It appears in the browser's last active
  window, which may be behind other windows.
- While connected, the browser shows the *"controlled by automated test
  software"* bar.
- Several containers can be connected to the agent browser at the same time.

## Configuration

`mcp-server.sh` and `check.sh` read these environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `CHROME_DEBUG_PORT` | `9333` | Port the browser listens on; the container relay uses the same port |
| `CHROME_DEBUG_HOST` | `host.docker.internal` | Where the relay forwards to |
| `CHROME_DEBUG_TARGET_PORT` | `$CHROME_DEBUG_PORT` | Port on the host side, if it differs (netsh fallback below) |

Set them in the shell you start `claude` from, or under `env` in
`.claude/settings.local.json` (not committed).

To pass extra flags to chrome-devtools-mcp, append them to the server's `args`.
The defaults turn off Google usage statistics (`--no-usage-statistics`) and stop
page URLs from performance traces being sent to the CrUX API
(`--no-performance-crux`).

The package version is pinned in `mcp-server.sh`. To upgrade, check
`npm view chrome-devtools-mcp version` and edit that line.

## Security

The container is a sandbox. This setup deliberately opens a door out of it to a
browser that is logged into your accounts. Once you click Allow, the agent can
read and act on any page in that browser instance. Keep the door narrow:

- Only click Allow when you started something that needs the browser. An
  unexpected dialog means something else is connecting.
- Log the agent browser in only to what the agent needs.
- Turn remote debugging off when you are not using it.
- If you need tighter limits, add these flags to the server's `args`:
  - `--allowedUrlPattern` or `--blockedUrlPattern` limits which sites the agent
    can reach.
  - `--no-javascript-evaluation` removes the tools that run arbitrary script.

## Troubleshooting

Start with `check.sh`. The step that fails tells you which hop is broken.

**Step 1: does not resolve.** Docker Desktop provides `host.docker.internal`.
On plain Docker Engine add `"runArgs": ["--add-host=host.docker.internal:host-gateway"]`
to `devcontainer.json` and rebuild.

**Step 2: "Connection refused".** Nothing is listening on the Windows side.
Check that the agent browser is running, that remote debugging is enabled in its
`brave://inspect/#remote-debugging`, and that the port is right. The port is in
the first line of the `DevToolsActivePort` file; in PowerShell:
`Get-Content "$env:LOCALAPPDATA\BraveAgent\DevToolsActivePort"`.

**Step 2: timeout.** Docker Desktop is not reaching Windows loopback, or an
egress firewall in the container blocks it (allow `host.docker.internal` on the
port). As a fallback, expose the port on another interface. In an **admin**
PowerShell:

```powershell
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=9334 connectaddress=127.0.0.1 connectport=9333
New-NetFirewallRule -DisplayName "Agent browser debug relay" -Direction Inbound -Protocol TCP -LocalPort 9334 -Action Allow
```

Then set `CHROME_DEBUG_TARGET_PORT=9334`. `listenaddress=0.0.0.0` also exposes
the port to your LAN. The browser still asks for Allow, but if you can, narrow
the listen address or the firewall rule to the WSL/Docker vEthernet adapter. To
remove it later, run
`netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=9334`.

**Step 3: HTTP 500.** The browser rejected the Host header. Something is dialing
`host.docker.internal` directly instead of going through the `127.0.0.1` relay.

**Step 3: HTTP 404.** You are not talking to a chrome://inspect debugging
server. Either the browser is older than Chromium 144, or another process holds
the port.

**Step 3: no answer, or connection closed.** The Allow dialog was not answered
or was denied. It appears in the last active window of the agent browser.

**`/mcp` shows the server failed.** Check `/tmp/chrome-bridge/relay.log`, and
start the server by hand to see its errors:
`bash .devcontainer/chrome-bridge/mcp-server.sh </dev/null`.

**A relay is still pointing at an old port or host.** Stop it with
`pkill -f '[s]ocat TCP-LISTEN:9333'` (use your port) or, for the Node relay,
`pkill -f '[c]hrome-bridge-relay'`. The brackets stop the pattern from matching
the shell running the command. The next session starts a fresh one.
