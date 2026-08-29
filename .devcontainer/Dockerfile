FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Features install Node, Docker and Claude Code. This file is only for what they
# don't cover — tools every shell in this repo expects.
#
# jq: Claude Code hooks are shell scripts that parse a JSON payload from stdin,
#     and this repo's manifests (marketplace.json, plugin.json) get poked by hand.
# python3: the skills ship python3 validators (scripts/check-devcontainer.py) and
#     CLAUDE.md's version-drift check is a python3 one-liner.
# shellcheck: the skills ship bash assets; lint them where they're edited.
#
# One RUN, and clean the package lists: separate install layers each carry their
# own stale package index, which surfaces weeks later as a confusing 404.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        jq \
        python3 \
        shellcheck \
        vim \
    && rm -rf /var/lib/apt/lists/*
