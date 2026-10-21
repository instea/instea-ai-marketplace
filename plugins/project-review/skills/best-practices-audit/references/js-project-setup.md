# JavaScript project setup

Team convention: pnpm is the package manager. It's faster, saves disk space with a shared store, and its strict `node_modules` catches undeclared dependencies.

| ID | Sev | Type | Rule | How to check |
|---|---|---|---|---|
| JS-01 | high | mechanical | Use pnpm: `pnpm-lock.yaml` present | List root files |
| JS-02 | high | mechanical | No foreign lockfiles (`package-lock.json`, `yarn.lock`, `bun.lockb`) | List root and workspace files |
| JS-03 | medium | mechanical | `packageManager` field pins pnpm (e.g. `"pnpm@9.x.x"`) so Corepack uses the right version | Read `package.json` |
| JS-04 | medium | mechanical | Monorepos use `pnpm-workspace.yaml`, not a `workspaces` field in `package.json` | Read `package.json`, list root |
| JS-05 | medium | mechanical | Scripts and CI call `pnpm`, not `npm`/`yarn`/`npx` | Grep `package.json` scripts, `.github/workflows/*`, `Dockerfile*` for `npm `, `npx `, `yarn ` |
| JS-06 | medium | mechanical | CI installs with `pnpm install --frozen-lockfile` | Grep CI files for `pnpm install` |
| JS-07 | low | mechanical | Node version pinned (`engines.node`, `.nvmrc` or `.node-version`) | Read `package.json`, list root |
