# Testing guidelines

Key convention: e2e tests run against a **production build**, not the dev server. Dev servers compile on demand, use much more memory, are slower to respond and can behave differently (HMR, dev-only warnings, unminified code), which makes e2e runs slow and flaky.

| ID | Sev | Type | Rule | How to check |
|---|---|---|---|---|
| TEST-01 | high | mechanical | E2E server starts from a production build (`build` + `preview`/`start`), not `dev` | Read `webServer.command` in `playwright.config.*`; flag `dev`, `vite`, `next dev`, `ng serve` |
| TEST-02 | medium | mechanical | E2E script builds first or CI builds before e2e (e.g. `pnpm build && pnpm test:e2e`) | Read `package.json` scripts and CI workflow |
| TEST-03 | medium | mechanical | Unit and e2e tests are separate scripts (`test` vs `test:e2e`) | Read `package.json` scripts |
| TEST-04 | medium | mechanical | `reuseExistingServer` is off in CI (e.g. `!process.env.CI`) so CI never hits a stray dev server | Read `playwright.config.*` |
| TEST-05 | low | judgment | E2E tests use stable selectors (role, label, `data-testid`), not CSS classes or XPath | Grep e2e test dir for `locator('.`, `xpath=`; sample up to 3 files |
| TEST-06 | low | judgment | No fixed waits (`waitForTimeout`) | Sample up to 3 files, then grep e2e test dir |
