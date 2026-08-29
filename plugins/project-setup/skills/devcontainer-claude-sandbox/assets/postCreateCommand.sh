#!/bin/bash
# Runs once after the container is created. Each fix here corresponds to a
# failure that is hard to diagnose from its error message — see the
# "Why the template looks like this" section of SKILL.md.
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

# 4. Egress firewall goes here if the project wants one — see Optional additions
#    in SKILL.md. It also needs "runArgs": ["--cap-add=NET_ADMIN"].
