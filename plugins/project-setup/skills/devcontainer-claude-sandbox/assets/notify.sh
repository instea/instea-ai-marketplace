#!/usr/bin/env bash
# Optional add-on. Notifications raised inside a container never reach the host
# desktop, so this pushes them out through apprise instead.
#
# Needs: `pipx install apprise` in the Dockerfile, CLAUDE_NOTIFY_URL forwarded via
# remoteEnv, and Stop + Notification hooks in .claude/settings.json:
#   "Stop":         [{"hooks": [{"type": "command", "command": ".claude/hooks/notify.sh done"}]}]
#   "Notification": [{"hooks": [{"type": "command", "command": ".claude/hooks/notify.sh notify"}]}]
#
# The hook payload arrives as JSON on stdin. Notification events carry `message`;
# every event carries `cwd`, used here to say which project it came from.

payload=$(cat)

if command -v jq &>/dev/null; then
  project=$(basename "$(jq -r '.cwd // empty' <<<"$payload")")
  text=$(jq -r '.message // empty' <<<"$payload")
fi

case "${1}" in
  done)   body="Task finished" ;;
  notify) body="${text:-Waiting for your input}" ;;
  *)      body="Claude Code event" ;;
esac
[ -n "${project}" ] && body="${body} (${project})"

if command -v apprise &>/dev/null && [ -n "${CLAUDE_NOTIFY_URL}" ]; then
  apprise -t "Claude Code" -b "${body}" "${CLAUDE_NOTIFY_URL}" 2>/dev/null
else
  echo "CLAUDE_NOTIFY_URL not set or apprise missing: ${body}"
fi
