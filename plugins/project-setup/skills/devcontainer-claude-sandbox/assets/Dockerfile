FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Features install the language toolchain, Docker, and Claude Code. This file is
# only for what they don't cover — tools the team expects in every shell.
#
# jq is not optional: postCreateCommand.sh reads .claude/settings.json with it to
# install the repo's plugins, and Claude Code hooks are shell scripts that parse a
# JSON payload from stdin, so the first hook anyone adds needs it too.
#
# One RUN, and clean the package lists: separate install layers each carry their
# own stale package index, which surfaces weeks later as a confusing 404.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        jq \
        vim \
    && rm -rf /var/lib/apt/lists/*

# For the optional apprise notification hook, add as the remote user:
# USER vscode
# RUN pipx install apprise && pipx ensurepath
