import { execSync } from "node:child_process";
import { join } from "node:path";
import { expect, test } from "@playwright/test";

// The claim flow under test is pure app logic (Tenants + session scoping); it
// does not need the real bot. Seeding a tenant row directly into the dev
// database stands in for "the bot is in this guild", and /g/:slug scopes the
// session to it without touching GuildCache.
const GUILD_ID = "e2e-claim-guild";
const SLUG = "e2e-seed";
const DB = join(__dirname, "..", "..", "priv", "db", "soundboard_dev.db");

function seedGuild() {
  execSync(
    `sqlite3 ${DB} "INSERT OR REPLACE INTO guilds (discord_guild_id, slug, name, max_storage_bytes, inserted_at, updated_at) VALUES ('${GUILD_ID}', '${SLUG}', 'E2E Seed', 2147483648, datetime('now'), datetime('now'));"`,
  );
}

test.describe("slug claim", () => {
  test("claiming a free slug flashes the final URL and the /g path resolves", async ({ page }) => {
    seedGuild();

    // /g/:slug scopes the session to the seeded tenant.
    await page.goto("/auth/test-login");
    await page.goto(`/g/${SLUG}`);
    await page.goto("/guilds");

    const form = page.locator('form[action="/guilds/claim"]');
    await expect(form).toBeVisible();
    await form.locator('input[name="slug"]').fill("e2e-claimed");
    await form.getByRole("button", { name: /claim/i }).click();

    await expect(page.getByText(/soundbored\.app\/g\/e2e-claimed/)).toBeVisible();

    // A fresh request to the claimed path resolves the tenant and scopes.
    await page.goto("/g/e2e-claimed");
    await expect(page).toHaveURL(/\/$/);
  });

  test("claiming a taken slug errors without changing the claimed slug", async ({ page }) => {
    seedGuild();
    execSync(
      `sqlite3 ${DB} "INSERT OR IGNORE INTO guilds (discord_guild_id, slug, name, max_storage_bytes, inserted_at, updated_at) VALUES ('e2e-other-guild', 'e2e-taken', 'Other', 2147483648, datetime('now'), datetime('now'));"`,
    );

    await page.goto("/auth/test-login");
    await page.goto(`/g/${SLUG}`);
    await page.goto("/guilds");

    const form = page.locator('form[action="/guilds/claim"]');
    await form.locator('input[name="slug"]').fill("e2e-taken");
    await form.getByRole("button", { name: /claim/i }).click();

    await expect(page.getByText(/not available/i)).toBeVisible();
    // The taken slug still resolves to its original owner, not us.
    const owner = execSync(
      `sqlite3 ${DB} "SELECT discord_guild_id FROM guilds WHERE slug='e2e-taken';"`,
    )
      .toString()
      .trim();
    expect(owner).toBe("e2e-other-guild");
  });

  test("a reserved slug is rejected", async ({ page }) => {
    seedGuild();

    await page.goto("/auth/test-login");
    await page.goto(`/g/${SLUG}`);
    await page.goto("/guilds");

    const form = page.locator('form[action="/guilds/claim"]');
    await form.locator('input[name="slug"]').fill("admin");
    await form.getByRole("button", { name: /claim/i }).click();

    await expect(page.getByText(/not available/i)).toBeVisible();
  });

  test("a signed-out /g path redirects to auth and creates no row", async ({ request }) => {
    const res = await request.get("/g/e2e-never-seeded", { maxRedirects: 0 });
    expect(res.status()).toBe(302);
    expect(res.headers().location).toBe("/auth/discord");
    const rows = execSync(
      `sqlite3 ${DB} "SELECT count(*) FROM guilds WHERE slug='e2e-never-seeded';"`,
    )
      .toString()
      .trim();
    expect(rows).toBe("0");
  });
});
