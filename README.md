# instea AI marketplace

Instea's Claude Code plugin marketplace — shared skills, plugins and house standards for our projects.

## Install

In Claude Code, add the marketplace once, then install the plugins you want:

```
/plugin marketplace add instea/instea-ai-marketplace
/plugin install project-setup@instea-ai-marketplace
```

Update later with `/plugin marketplace update instea-ai-marketplace`.

## Plugins

| Plugin | Skills | What it does |
|---|---|---|
| [project-setup](plugins/project-setup) | `docker-release-workflow` ⌨️<br>`devcontainer-claude-sandbox` ⌨️ | Sets up a GitHub Actions workflow that builds each service's Docker image, pushes it to `registry.instea.co`, and cuts a GitHub release from the `package.json` version — scaffolding any missing Dockerfile. Also scaffolds a `.devcontainer/` that runs Claude Code sandboxed inside the project's own container, keeping the agent's config on a named volume instead of the host's `~/.claude`. |

- ⌨️ **explicit** — you start it yourself with a slash command (`/project-setup:docker-release-workflow`).
- 🤖 **automatic** — Claude invokes it on its own when the task calls for it.

See each plugin's README for details.

## Contributing a plugin

```
plugins/<plugin-name>/
  .claude-plugin/plugin.json     # name, description, version, author
  README.md                      # what it does, how to invoke it
  skills/<skill-name>/SKILL.md   # one dir per skill, + optional assets/ and references/
```

Add an entry for it to `.claude-plugin/marketplace.json`, then validate and smoke-test locally:

```
claude plugin validate ./plugins/<plugin-name> --strict
# test local (not yet published) version
claude --plugin-dir ./plugins/<plugin-name>
```
