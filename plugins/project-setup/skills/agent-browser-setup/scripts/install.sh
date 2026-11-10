#!/bin/bash
# Installs the browser bridge kit (assets/chrome-bridge) into a repo, so Claude
# Code in its dev container can drive the agent browser on the Windows host.
#
# Usage: install.sh [--scope project|local] [--force] [REPO_ROOT]
#   --scope project  (default) files meant to be committed: the kit in
#                    .devcontainer/chrome-bridge/ and a chrome-devtools entry in
#                    .mcp.json
#   --scope local    personal: the same folder, but git-ignored through
#                    .git/info/exclude, and the server registered in Claude's
#                    local config for this repo (~/.claude.json)
#   --force          replace a kit file or chrome-devtools entry that differs
#   REPO_ROOT        defaults to the git top level of the current directory
#
# Safe to re-run: identical files are left alone. Exit 0 = done, 1 = something
# needs attention (lines marked !!), 2 = usage error.
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kit="$skill_dir/assets/chrome-bridge"
server=chrome-devtools
server_args='"--no-usage-statistics", "--no-performance-crux"'

scope=project force=0 repo=""
while [ $# -gt 0 ]; do
  case "$1" in
    --scope) scope="${2:-}"; shift 2 ;;
    --force) force=1; shift ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) repo="$1"; shift ;;
  esac
done
case "$scope" in project|local) ;; *) echo "--scope must be project or local" >&2; exit 2 ;; esac
repo="${repo:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
repo="$(cd "$repo" && pwd)"
rel=".devcontainer/chrome-bridge"
dest="$repo/$rel"

attention=0
say()  { printf '  %-8s %s\n' "$1" "$2"; }
warn() { printf '  %-8s %s\n' '!!' "$*"; attention=1; }

echo "Repo: $repo (scope: $scope)"

# 1. Prerequisites in the running container. Node is a hard requirement: npx
#    runs chrome-devtools-mcp, and this script edits JSON with it.
echo "Prerequisites"
if ! command -v node >/dev/null 2>&1 || ! command -v npx >/dev/null 2>&1; then
  warn "node/npx not found — chrome-devtools-mcp needs Node ^20.19 || ^22.12 || >=23"
  exit 1
fi
node_version="$(node -p 'process.versions.node')"
if node -e 'const [a, b] = process.versions.node.split(".").map(Number);
            process.exit(a >= 23 || (a === 22 && b >= 12) || (a === 20 && b >= 19) ? 0 : 1)'; then
  say ok "node $node_version"
else
  warn "node $node_version is too old — chrome-devtools-mcp needs ^20.19 || ^22.12 || >=23"
fi
if command -v socat >/dev/null 2>&1; then say ok "relay: socat"; else say ok "relay: node (socat not installed)"; fi
command -v setsid >/dev/null 2>&1 && say ok "setsid" || warn "setsid (util-linux) not found — mcp-server.sh needs it to detach the relay"
command -v ss >/dev/null 2>&1 && say ok "ss" || say info "ss (iproute2) not found — harmless, check.sh just cannot report the relay"
if addr="$(getent hosts host.docker.internal | awk '{print $1; exit}')" && [ -n "$addr" ]; then
  say ok "host.docker.internal -> $addr"
else
  warn "host.docker.internal does not resolve — Docker Desktop provides it; on plain Docker Engine add --add-host=host.docker.internal:host-gateway"
fi
# An egress firewall shows up as a non-comment line naming it (the Instea
# template only mentions NET_ADMIN in a comment).
firewall="$(grep -rIE 'init-firewall|NET_ADMIN|iptables|ipset' "$repo/.devcontainer" 2>/dev/null \
  | grep -v '/chrome-bridge/' | grep -vE '^[^:]*:[[:space:]]*(#|//)' \
  | cut -d: -f1 | sort -u | sed "s#^$repo/##" | paste -sd, - || true)"
if [ -n "$firewall" ]; then
  warn "egress firewall likely ($firewall) — allow host.docker.internal:${CHROME_DEBUG_PORT:-9333} (and the npm registry for the first npx run)"
fi

# 2. The kit. The .bat is written with CRLF whatever the source has: cmd.exe
#    misparses LF-only batch files, and Windows runs it from this working tree.
echo "Kit files ($rel/)"
mkdir -p "$dest"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
for src in "$kit"/*; do
  name="$(basename "$src")"
  case "$name" in
    *.sh)  mode=755; cp "$src" "$tmp" ;;
    *.bat) mode=644; sed 's/\r*$/\r/' "$src" >"$tmp" ;;
    *)     mode=644; cp "$src" "$tmp" ;;
  esac
  if [ ! -e "$dest/$name" ]; then
    install -m "$mode" "$tmp" "$dest/$name"; say added "$name"
  elif cmp -s "$tmp" "$dest/$name"; then
    chmod "$mode" "$dest/$name"; say same "$name"
  elif [ "$force" = 1 ]; then
    install -m "$mode" "$tmp" "$dest/$name"; say replaced "$name"
  else
    warn "$name differs from the kit — kept. See: diff --strip-trailing-cr '$src' '$dest/$name'"
  fi
done

# 3. Register the MCP server.
echo "MCP server '$server'"
if [ "$scope" = project ]; then
  # Relative path: .mcp.json is shared, so it must not depend on where the repo
  # is checked out. Claude has to be started from the repo root.
  entry="{\"command\": \"bash\", \"args\": [\"$rel/mcp-server.sh\", $server_args]}"
  result="$(node - "$repo/.mcp.json" "$server" "$entry" "$force" <<'JS'
const fs = require("fs");
const [file, name, entryJson, force] = process.argv.slice(2);
const entry = JSON.parse(entryJson);
let cfg = {};
if (fs.existsSync(file)) {
  try { cfg = JSON.parse(fs.readFileSync(file, "utf8")); }
  catch (e) { console.log(`invalid: ${e.message}`); process.exit(0); }
}
cfg.mcpServers ??= {};
const old = cfg.mcpServers[name];
let result;
if (!old) result = "added";
else if (JSON.stringify(old) === JSON.stringify(entry)) result = "same";
else if (force === "1") result = "replaced";
else { console.log(`differs: ${JSON.stringify(old)}`); process.exit(0); }
if (result !== "same") {
  cfg.mcpServers[name] = entry;
  fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + "\n");
}
console.log(result);
JS
)"
  case "$result" in
    added|same|replaced) say "$result" ".mcp.json" ;;
    *) warn ".mcp.json: ${result} — kept; re-run with --force to replace the entry" ;;
  esac

  # cmd.exe misparses LF-only batch files; keep git from converting the .bat.
  if ! grep -qsE '^\*\.bat[[:space:]].*eol=crlf' "$repo/.gitattributes"; then
    { [ -s "$repo/.gitattributes" ] && [ -n "$(tail -c1 "$repo/.gitattributes")" ] && echo
      echo "# cmd.exe misparses batch files with LF-only line endings."
      echo "*.bat text eol=crlf"; } >>"$repo/.gitattributes"
    say added ".gitattributes: *.bat text eol=crlf"
  else
    say same ".gitattributes"
  fi
else
  # Personal: keep the kit out of git and the server out of .mcp.json.
  if exclude="$(git -C "$repo" rev-parse --git-path info/exclude 2>/dev/null)"; then
    case "$exclude" in /*) ;; *) exclude="$repo/$exclude" ;; esac
    if grep -qsxF "/$rel/" "$exclude"; then
      say same "git exclude"
    else
      mkdir -p "$(dirname "$exclude")"
      echo "/$rel/" >>"$exclude"
      say added "git exclude: /$rel/"
    fi
  else
    say info "not a git repo — nothing to exclude"
  fi
  if grep -qs "\"$server\"" "$repo/.mcp.json"; then
    warn ".mcp.json already defines '$server' — the local entry will take precedence over it"
  fi
  # Absolute path: local config is per machine and per checkout anyway.
  entry="{\"type\": \"stdio\", \"command\": \"bash\", \"args\": [\"$dest/mcp-server.sh\", $server_args]}"
  if ! command -v claude >/dev/null 2>&1; then
    warn "claude CLI not found — run from $repo: claude mcp add-json -s local $server '$entry'"
  else
    [ "$force" = 1 ] && (cd "$repo" && claude mcp remove -s local "$server" >/dev/null 2>&1) || true
    if out="$(cd "$repo" && claude mcp add-json -s local "$server" "$entry" 2>&1)"; then
      say added "local config ($server)"
    elif [[ $out == *"already exists"* ]]; then
      say kept "local config already has '$server' (re-run with --force to replace it)"
    else
      warn "claude mcp add-json failed: $out"
    fi
  fi
fi

if [ "$attention" = 1 ]; then
  echo "Done, but lines marked !! need attention."
  exit 1
fi
echo "Done. Next: verify with $rel/check.sh, then restart Claude from the repo root."
