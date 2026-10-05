# E2E (Playwright)

End-to-end tests for the onboarding flow. No real Discord OAuth is exercised —
tests sign in via the dev-only fake login route `/auth/test-login` (enabled by
`config :soundboard, enable_test_login: true` in dev) and only assert on the
invite URL string for the Discord invite.

## Server management

The Phoenix dev server is **managed outside Playwright** (the config has no
`webServer` block). This is the more reliable option here: the server needs
fake Discord credentials and a one-time `mix ecto.migrate`, and reusing a
long-lived server avoids recompiles between runs.

From the repo root:

```sh
mix ecto.migrate   # once; dev SQLite db lives at priv/db/soundboard_dev.db
DISCORD_CLIENT_ID=test-client-id DISCORD_TOKEN=fake-token mix phx.server
```

Wait for the Phoenix banner / port 4000, then run the tests:

```sh
cd e2e
npm install
npx playwright install chromium   # add --with-deps if OS libs are missing
npx playwright test
```

## Layout

- `playwright.config.ts` — baseURL `http://localhost:4000`, chromium, `workers: 1` (shared server state).
- `tests/onboarding.spec.ts` — onboarding + guild-selection flow.
