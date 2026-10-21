# JavaScript project setup

Team convention: pnpm is the package manager. It's faster, by default protects against supply chain attacks, saves disk space with a shared store, and its strict `node_modules` catches undeclared dependencies.

| ID | Sev | Type | Rule | How to check |
|---|---|---|---|---|
| JS-01 | high | mechanical | Use pnpm: `pnpm-lock.yaml` present | List root files |
| JS-02 | high | mechanical | No foreign lockfiles (`package-lock.json`, `yarn.lock`, `bun.lockb`) | List root and workspace files |
| JS-03 | medium | mechanical | `packageManager` field pins pnpm (e.g. `"pnpm@9.x.x"`) so Corepack uses the right version | Read `package.json` |
| JS-04 | medium | mechanical | Monorepos use `pnpm-workspace.yaml`, not a `workspaces` field in `package.json` | Read `package.json`, list root |
| JS-05 | medium | mechanical | Scripts and CI call `pnpm`, not `npm`/`yarn`/`npx` | Grep `package.json` scripts, `.github/workflows/*`, `Dockerfile*` for `npm `, `npx `, `yarn ` |
| JS-06 | medium | mechanical | CI installs with `pnpm install --frozen-lockfile` | Grep CI files for `pnpm install` |
| JS-07 | low | mechanical | Node version pinned (`engines.node`, `.nvmrc` or `.node-version`) | Read `package.json`, list root |
| JS-08 | high | mechanical | `minimumReleaseAge` not disabled: pnpm's 1-day default keeps out fresh releases, and most compromised packages are caught within that window | Read `pnpm-workspace.yaml` and `.npmrc`; flag `minimumReleaseAge: 0` |
| JS-09 | high | mechanical | Install scripts limited to an explicit `allowBuilds` allowlist: most packages don't need them, and compromised ones usually ship one | Read `pnpm-workspace.yaml` and `.npmrc`; flag a blanket `allowBuilds` or `dangerouslyAllowAllBuilds: true` |
| JS-10 | medium | mechanical | `trustPolicy: no-downgrade` set, so a package published by a trusted publisher can't be upgraded to an untrusted release | Read `pnpm-workspace.yaml` and `.npmrc` |
