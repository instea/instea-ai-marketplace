#!/bin/bash
# Diagnoses the container -> Windows browser debugging path step by step.
# Run inside the dev container: .devcontainer/chrome-bridge/check.sh
# The last step opens a real debugging connection, so the browser shows its
# "Allow remote debugging?" dialog — click Allow to finish the check.
set -uo pipefail

port="${CHROME_DEBUG_PORT:-9333}"
host="${CHROME_DEBUG_HOST:-host.docker.internal}"
target_port="${CHROME_DEBUG_TARGET_PORT:-$port}"

ok()   { printf '  \033[32mOK\033[0m   %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; exit 1; }
hint() { printf '       %s\n' "$*"; }

echo "Browser target: $host:$target_port (container relay: 127.0.0.1:$port)"

# 1. Docker Desktop provides host.docker.internal; plain Docker Engine on Linux
#    needs --add-host=host.docker.internal:host-gateway.
echo "1. Resolve $host"
addr="$(getent hosts "$host" | awk '{print $1; exit}')"
[ -n "$addr" ] || fail "$host does not resolve"
ok "$host -> $addr"

# 2. Plain TCP. Refused = nothing listens on that port on the host; a timeout
#    means the traffic does not reach Windows loopback at all.
echo "2. TCP connect to $host:$target_port"
err="$(timeout 5 bash -c "exec 3<>/dev/tcp/$host/$target_port" 2>&1)"
case $? in
  0)   ok "port is open" ;;
  124) fail "timed out"
       hint "Docker Desktop is not forwarding to Windows 127.0.0.1 — see the netsh"
       hint "portproxy fallback in README.md next to this script (Troubleshooting)." ;;
  *)   fail "${err##*: }"
       hint "Is the agent browser running, with remote debugging turned on in"
       hint "brave://inspect/#remote-debugging (chrome://inspect for Chrome)?"
       hint "Is the port right? The page shows 'Server running at 127.0.0.1:<port>';"
       hint "set CHROME_DEBUG_PORT if it is not $port." ;;
esac

# 3. The websocket handshake chrome-devtools-mcp will do, with the Host header
#    it will send through the relay (127.0.0.1). The browser holds the response
#    until the dialog is answered.
echo "3. WebSocket handshake on /devtools/browser — click Allow in the browser (60 s)"
exec 3<>"/dev/tcp/$host/$target_port" || fail "could not reconnect"
printf 'GET /devtools/browser HTTP/1.1\r\nHost: 127.0.0.1:%s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n' "$port" >&3
IFS= read -r -t 60 status <&3
rc=$?
exec 3>&- 3<&-
status="${status%$'\r'}"
case "$status" in
  "HTTP/1.1 101"*) ok "$status" ;;
  "HTTP/1.1 500"*) fail "$status"
                   hint "Host header rejected — the browser only accepts an IP or localhost." ;;
  "HTTP/1.1 404"*) fail "$status"
                   hint "Not a chrome://inspect debugging server (or an old browser; Chromium 144+ needed)." ;;
  "HTTP/1.1 403"*) fail "$status"
                   hint "Connection rejected — denied in the dialog, or blocked by policy." ;;
  "")              if [ $rc -gt 128 ]; then fail "no answer within 60 s — the dialog was not answered"
                   else fail "connection closed without a response — denied in the dialog?"; fi ;;
  *)               fail "unexpected response: $status" ;;
esac

# 4. Informational: the relay only exists once Claude has started the MCP server.
echo "4. Container relay on 127.0.0.1:$port"
if ! command -v ss >/dev/null 2>&1; then
  hint "cannot tell — ss (iproute2) is not installed"
elif ss -Hltn "sport = :$port" | grep -q .; then
  ok "listening"
else
  hint "not running yet — Claude starts it with the chrome-devtools MCP server"
fi
