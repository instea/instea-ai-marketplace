#!/usr/bin/env python3
"""Validate a .devcontainer/ produced by the devcontainer-claude-sandbox skill.

Usage:  python3 scripts/check-devcontainer.py [path-to-repo]

Checks the things that fail silently — a config that parses but leaves the agent
unsandboxed, or a mount target the agent will never read. Exit code 1 on any
FAIL. WARNs are judgment calls that may be correct for the project.

devcontainer.json is JSONC: it allows // and /* */ comments and trailing commas.
Stripping those with a naive regex corrupts any "https://..." string value, so
this walks the text tracking string state instead.
"""
import json
import re
import sys
from pathlib import Path


def strip_jsonc(s: str) -> str:
    out, i, in_str, esc = [], 0, False, False
    while i < len(s):
        c = s[i]
        if in_str:
            out.append(c)
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            i += 1
        elif c == '"':
            in_str = True
            out.append(c)
            i += 1
        elif c == "/" and i + 1 < len(s) and s[i + 1] == "/":
            while i < len(s) and s[i] != "\n":
                i += 1
        elif c == "/" and i + 1 < len(s) and s[i + 1] == "*":
            j = s.find("*/", i + 2)
            i = len(s) if j == -1 else j + 2
        else:
            out.append(c)
            i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))


results = []


def ok(msg, ev=""):
    results.append(("PASS", msg, ev))


def bad(msg, ev=""):
    results.append(("FAIL", msg, ev))


def warn(msg, ev=""):
    results.append(("WARN", msg, ev))


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    dc_dir = root / ".devcontainer"
    dc_path = dc_dir / "devcontainer.json"

    if not dc_path.exists():
        print(f"FAIL  no devcontainer.json at {dc_path}")
        return 1

    try:
        dc = json.loads(strip_jsonc(dc_path.read_text()))
        ok("devcontainer.json parses")
    except json.JSONDecodeError as e:
        print(f"FAIL  devcontainer.json does not parse: {e}")
        return 1

    compose_based = "dockerComposeFile" in dc
    feats = {k.lower(): v for k, v in (dc.get("features") or {}).items()}
    has = lambda n: any(n in k for k in feats)

    # --- the agent ---
    if has("claude-code"):
        ok("claude-code feature present")
    else:
        bad("claude-code feature missing", ", ".join(feats) or "no features")

    # --- the config volume: the security core ---
    if compose_based:
        warn(
            "compose-based config: devcontainer.json 'mounts' is NOT honoured here",
            "the .claude volume must be declared in the compose file instead — verify it by hand",
        )
        if dc.get("mounts"):
            bad(
                "'mounts' declared in a compose-based devcontainer.json",
                "it is ignored; move it to the compose file's volumes:",
            )
    else:
        mounts = dc.get("mounts") or []
        blob = json.dumps(mounts)
        vols = [m for m in mounts if ".claude" in str(m) and "volume" in str(m)]
        if not vols:
            bad("no named volume mounted for the agent config", blob or "no mounts")
        else:
            m = re.search(r"target=([^,\"]+)", str(vols[0])) if isinstance(vols[0], str) else None
            target = m.group(1) if m else str(vols[0].get("target", "")) if isinstance(vols[0], dict) else ""
            if target.endswith("/.claude"):
                ok("agent config on a named volume", target)
            else:
                bad("mount target is not <home>/.claude — the volume will sit unused", target)
            ru = dc.get("remoteUser")
            if ru and f"/{ru}/" not in target and not target.startswith(f"/home/{ru}"):
                bad("mount target does not match remoteUser", f"remoteUser={ru} target={target}")
        if "localEnv:HOME" in blob or "localEnv:USERPROFILE" in blob:
            bad("the HOST home directory is being mounted in", blob)

    # --- lifecycle scripts ---
    pc = next(iter(dc_dir.glob("postCreate*.sh")), None)
    if not pc:
        bad("no postCreateCommand.sh in .devcontainer/")
    else:
        body = pc.read_text()
        for label, pat in (
            ("strips credsStore", r"credsStore"),
            ("chowns the config volume", r"chown[^\n]*\.claude"),
            ("symlinks .claude.json", r"ln -s[^\n]*\.claude\.json"),
        ):
            (ok if re.search(pat, body) else bad)(f"postCreate {label}", pc.name)
        if re.search(r"/home/(vscode|node|codespace)\b", body):
            warn("postCreate hardcodes a user path; prefer $HOME / id -un", pc.name)

    # --- deprecated schema ---
    for key in ("extensions", "settings"):
        if key in dc:
            bad(
                f"top-level '{key}' is the deprecated pre-customizations schema",
                f"move to customizations.vscode.{key} — it is ignored outside VS Code",
            )

    # --- services / persistence ---
    if has("docker-in-docker"):
        dind_persisted = "/var/lib/docker" in json.dumps(dc.get("mounts") or [])
        compose_files = list(root.glob("docker-compose*.y*ml")) + list(root.glob("compose*.y*ml"))
        if compose_files and not dind_persisted:
            warn(
                "docker-in-docker + a compose file: inner volumes are LOST on rebuild",
                "see 'Step 3' in SKILL.md — prefer compose siblings, or persist /var/lib/docker",
            )
        if compose_files and "postStartCommand" not in dc:
            warn(
                "compose services will not be running after a container restart",
                "bring them up in postStartCommand, not postCreateCommand",
            )
    if "docker-outside-of-docker" in " ".join(feats):
        bad(
            "docker-outside-of-docker mounts the HOST Docker socket",
            "that is effective root on the host and defeats the sandbox — see SKILL.md",
        )

    # --- shell syntax ---
    import subprocess

    for sh in sorted(dc_dir.glob("*.sh")):
        r = subprocess.run(["bash", "-n", str(sh)], capture_output=True, text=True)
        (ok if r.returncode == 0 else bad)(f"{sh.name} shell syntax", r.stderr.strip()[:120])

    width = max(len(m) for _, m, _ in results)
    for status, msg, ev in results:
        print(f"{status:4}  {msg:<{width}}  {ev}")
    fails = sum(1 for s, _, _ in results if s == "FAIL")
    warns = sum(1 for s, _, _ in results if s == "WARN")
    print(f"\n{len(results) - fails - warns} passed, {fails} failed, {warns} warnings")
    return 1 if fails else 0


sys.exit(main())
