# CLAUDE.md

Guidance for Claude Code when working in this repo.

This is a Claude Code plugin marketplace: `.claude-plugin/marketplace.json` at the root lists
plugins, each of which lives under `plugins/<name>/` and ships one or more skills.

## Versioning

### The invariant

**A plugin's version is written in two places, and they must always match:**

| File | Field |
|---|---|
| `plugins/<name>/.claude-plugin/plugin.json` | `version` |
| `.claude-plugin/marketplace.json` | the plugin's entry in `plugins[]` → `version` |

Change one, change the other, in the same commit. Nothing enforces this — `claude plugin validate`
does not compare them — so a mismatch ships silently and installs the wrong version for everyone.
Check it before committing:

```bash
python3 -c "
import json
m = json.load(open('.claude-plugin/marketplace.json'))['plugins']
for e in m:
    p = json.load(open(e['source'].rstrip('/') + '/.claude-plugin/plugin.json'))
    print(('OK  ' if e['version'] == p['version'] else 'DRIFT'), e['name'], e['version'], p['version'])
"
```

### What gets a version

- **Plugins are versioned.** Semver, in the two places above.
- **Skills are not.** `SKILL.md` frontmatter carries `name`, `description`, and optionally
  `disable-model-invocation` — no `version` key. A skill's changes are released through its
  plugin's version.
- **The marketplace itself is not.** `.claude-plugin/marketplace.json` has no top-level `version`
  field; do not add one.

### When to bump what

Semver, scoped to what an *installed user* experiences:

| Bump | When |
|---|---|
| **Patch** (`0.2.0` → `0.2.1`) | Docs, troubleshooting entries, typo and wording fixes, template tweaks that don't change what the skill produces |
| **Minor** (`0.2.0` → `0.3.0`) | A new skill, a new capability or step in an existing skill, a new bundled asset or script |
| **Major** (`0.2.0` → `1.0.0`) | Removing or renaming a skill, or changing a skill's output in a way that breaks repos already set up by the previous version |

Everything is pre-1.0 today. Staying below `1.0.0` is deliberate — it signals the house standards
are still settling. Reaching for a major bump is a decision to make explicitly, not a mechanical
consequence of a breaking change; prefer discussing it first.

### Things that ride along with a version bump

Adding or removing a skill is never just a version change. The same commit should also update:

- The **skills table** in `plugins/<name>/README.md`, and the **plugins table** in the root
  `README.md` — mark the skill ⌨️ explicit if it sets `disable-model-invocation: true`,
  🤖 automatic otherwise.
- The plugin entry's **`description`** in `marketplace.json`, which names its skills inline
  (e.g. `"Skills: docker-release-workflow, devcontainer-claude-sandbox."`) — it goes stale
  silently otherwise.
- **`keywords`** in both manifests, kept roughly in sync.

Then run both gates:

```bash
claude plugin validate ./plugins/<name> --strict   # plugin manifest
claude plugin validate . --strict                  # marketplace manifest
```

### Versions this repo does *not* own

Some `version` fields in the tree belong to the *output* skills generate, not to this repo. Never
bump these as part of a release:

- `plugins/*/skills/*/assets/devcontainer.json` — `"version": "lts"` on devcontainer features, and
  the pinned feature majors in the feature keys themselves (`node:1`, `docker-in-docker:3`,
  `claude-code:1.0`). These are pinned on purpose so a feature's next major cannot silently change
  what a generated container contains. Changing one is a deliberate edit to the house standard —
  and, because it changes generated output, usually warrants a plugin bump of its own.
- Any version referenced inside `assets/` templates (base images, action refs, tool versions).
