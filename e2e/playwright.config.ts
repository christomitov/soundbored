import { defineConfig } from "@playwright/test";

/**
 * The Phoenix dev server is managed OUTSIDE of Playwright (no webServer block):
 * it is started by hand with the fake Discord credentials so the developer
 * keeps control of the VM/migration state and avoids recompiles on every run:
 *
 *   DISCORD_CLIENT_ID=test-client-id DISCORD_TOKEN=fake-token mix phx.server
 *
 * See e2e/README.md for the full workflow.
 */
export default defineConfig({
  testDir: "./tests",
  timeout: 30_000,
  workers: 1,
  use: {
    baseURL: "http://localhost:4000",
    trace: "retain-on-failure",
  },
  projects: [{ name: "chromium", use: { browserName: "chromium" } }],
});
