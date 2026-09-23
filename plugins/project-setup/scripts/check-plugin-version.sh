#!/usr/bin/env bash
# Is this plugin the current house standard, or a copy someone installed months ago?
#
# Usage:  bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-plugin-version.sh"
#
# A skill runs from whatever version is in the user's plugin cache, and that is
# usually not the newest one — nothing updates it automatically. So a skill can
# happily scaffold last quarter's house standard with no sign that it did.
#
# Prints exactly one line. Exit 3 means STALE; 0 means up to date, unknown, or a
# situation where the question does not apply. Never exits non-zero for a failure
# to find out — being offline is not a reason to block a scaffold.
set -uo pipefail

plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
manifest="$plugin_root/.claude-plugin/plugin.json"

if [ -z "$plugin_root" ] || [ ! -f "$manifest" ]; then
  echo "version check skipped: CLAUDE_PLUGIN_ROOT does not point at a plugin"
  exit 0
fi

command -v jq >/dev/null 2>&1 || { echo "version check skipped: jq not installed"; exit 0; }

name=$(jq -r '.name // empty' "$manifest")
installed=$(jq -r '.version // empty' "$manifest")
[ -n "$name" ] && [ -n "$installed" ] || { echo "version check skipped: unreadable $manifest"; exit 0; }

# Working inside a checkout of the marketplace itself (this repo, or `claude
# --plugin-dir`) means the files on disk ARE the newest version. Comparing them
# against the published one would report the opposite of the truth.
toplevel=$(git -C "$plugin_root" rev-parse --show-toplevel 2>/dev/null || true)
if [ -n "$toplevel" ] && [ -f "$toplevel/.claude-plugin/marketplace.json" ] \
   && [[ "$toplevel" != "$HOME/.claude/plugins/"* ]]; then
  echo "$name $installed — local checkout at $toplevel, skipping the version check"
  exit 0
fi

# Installed plugins live at <cache>/<marketplace>/<plugin>/<version>, so the
# marketplace name is two directories up from the plugin root.
marketplace=$(basename "$(dirname "$(dirname "$plugin_root")")")
known="$HOME/.claude/plugins/known_marketplaces.json"
location=""
[ -f "$known" ] && location=$(jq -r --arg m "$marketplace" '.[$m].installLocation // empty' "$known")
if [ -z "$location" ]; then
  echo "$name $installed — marketplace '$marketplace' not on disk, cannot check for updates"
  exit 0
fi

# Refresh the clone; offline is fine, we then compare against what we already have.
timeout 60 claude plugin marketplace update "$marketplace" >/dev/null 2>&1 || true

latest=$(jq -r --arg n "$name" '.plugins[]? | select(.name == $n) | .version // empty' \
  "$location/.claude-plugin/marketplace.json" 2>/dev/null | head -1)
if [ -z "$latest" ]; then
  echo "$name $installed — latest unknown (marketplace manifest unreadable or offline)"
  exit 0
fi

if [ "$installed" = "$latest" ]; then
  echo "$name $installed — up to date"
  exit 0
fi

newest=$(printf '%s\n%s\n' "$installed" "$latest" | sort -V | tail -1)
if [ "$newest" = "$installed" ]; then
  echo "$name $installed — ahead of the marketplace ($latest), nothing to update"
  exit 0
fi

echo "$name $installed — STALE, marketplace has $latest: run 'claude plugin update $name@$marketplace' and restart Claude Code"
exit 3
