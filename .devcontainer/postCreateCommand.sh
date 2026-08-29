#!/bin/bash
# Runs once after the container is created. Each fix here corresponds to a
# failure that is hard to diagnose from its error message — see the
# "Why the template looks like this" section of the devcontainer-claude-sandbox
# skill in this repo.
set -e

# 1. Drop the host's credential-helper reference.
#    With docker-in-docker the container can inherit a Docker config naming a
#    credsStore binary it does not have, and every pull then fails with:
#      docker: error getting credentials - err: exit status 255, out: ``
if [ -f "$HOME/.docker/config.json" ]; then
  sed -i '/credsStore/d' "$HOME/.docker/config.json" || true
fi

# 2. Take ownership of the Claude config volume.
#    Docker creates named volumes root-owned, so the remote user cannot write to
#    its own ~/.claude and Claude fails on first start with a permission error.
#    Derived from the current user rather than hardcoded, so this script survives
#    being copied to a project on a different base image.
sudo chown -R "$(id -un):$(id -gn)" "$HOME/.claude"

# 3. Persist the login across rebuilds.
#    Claude keeps session state in ~/.claude.json — beside the .claude directory,
#    not inside it — so the volume alone does not cover it. A file cannot be
#    bind-mounted before it exists, so create it on the volume and symlink it in.
#    The guard is what stops a rebuild from wiping an existing session.
[ -f "$HOME/.claude/.claude.json" ] || echo '{}' > "$HOME/.claude/.claude.json"
ln -sf "$HOME/.claude/.claude.json" "$HOME/.claude.json"

# 4. The devcontainer CLI, so the devcontainer-claude-sandbox skill can be
#    smoke-tested from inside this container. It needs the Node the feature
#    installs, which is why this is here and not in the Dockerfile — features
#    are applied after the image build.
npm install -g @devcontainers/cli

# 5. Egress firewall goes here if this repo ever wants one — see Optional
#    additions in the skill. It also needs "runArgs": ["--cap-add=NET_ADMIN"].
