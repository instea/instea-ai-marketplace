#!/bin/bash
# stdio MCP server for Claude Code: chrome-devtools-mcp attached to the agent
# browser (Brave or Chrome) running on the Windows host, using its
# consent-based remote debugging (chrome://inspect/#remote-debugging).
# Registered as the chrome-devtools MCP server; extra arguments are passed
# through to chrome-devtools-mcp. README.md next to this script explains why
# each step is needed.
#
# stdout is the MCP protocol channel — nothing below may write to it.
set -euo pipefail

# 9333 is the port start-agent-brave.bat pins the agent browser to.
port="${CHROME_DEBUG_PORT:-9333}"
host="${CHROME_DEBUG_HOST:-host.docker.internal}"
target_port="${CHROME_DEBUG_TARGET_PORT:-$port}"
state_dir="${TMPDIR:-/tmp}/chrome-bridge"
mkdir -p "$state_dir"

# 1. Relay the debugging port into the container's loopback.
#    The browser listens on Windows 127.0.0.1 only and answers HTTP 500 to any
#    Host header that is not an IP or "localhost", so dialing
#    host.docker.internal directly fails even though Docker Desktop routes it to
#    the host. The relay lets chrome-devtools-mcp dial 127.0.0.1 instead. It is
#    detached and left running so parallel Claude sessions share it; a second
#    one racing to bind the same port just logs EADDRINUSE.
#    socat when installed, otherwise the same in a few lines of Node, which
#    npx needs anyway, so the container needs no extra package.
node_relay='// chrome-bridge-relay (the marker pkill -f can find)
const net = require("net");
const [port, host, targetPort] = process.argv.slice(1);
const log = (msg) => console.error(`${new Date().toISOString()} ${msg}`);
net.createServer((client) => {
  const upstream = net.connect(Number(targetPort), host);
  client.pipe(upstream).pipe(client);
  client.on("error", () => upstream.destroy());
  upstream.on("error", (err) => { log(`${host}:${targetPort}: ${err.message}`); client.destroy(); });
}).listen(Number(port), "127.0.0.1", () => log(`relay 127.0.0.1:${port} -> ${host}:${targetPort}`));
'
relay_listening() {
  # Without ss the check is skipped; a duplicate relay then fails to bind and exits.
  command -v ss >/dev/null 2>&1 && ss -Hltn "sport = :$port" | grep -q .
}
if ! relay_listening; then
  if command -v socat >/dev/null 2>&1; then
    setsid -f socat "TCP-LISTEN:$port,bind=127.0.0.1,reuseaddr,fork" "TCP:$host:$target_port" \
      </dev/null >>"$state_dir/relay.log" 2>&1
  else
    setsid -f node -e "$node_relay" "$port" "$host" "$target_port" \
      </dev/null >>"$state_dir/relay.log" 2>&1
  fi
fi

# 2. Give --autoConnect a DevToolsActivePort to read.
#    autoConnect only discovers a browser on the same machine, by reading
#    <userDataDir>/DevToolsActivePort (port, then websocket path). The real file
#    lives in the Windows profile, out of reach. A server started from
#    chrome://inspect accepts /devtools/browser without the per-launch UUID, so
#    a static stand-in is enough and survives browser restarts.
printf '%s\n/devtools/browser\n' "$port" >"$state_dir/DevToolsActivePort"

# 3. Run the server. Pinned so a new release cannot change behaviour under us;
#    bump deliberately (npm view chrome-devtools-mcp version).
exec npx -y chrome-devtools-mcp@1.12.0 --autoConnect --userDataDir "$state_dir" "$@"
