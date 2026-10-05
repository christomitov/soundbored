import { expect, test } from "@playwright/test";

const OAUTH_START = "/auth/discord";
const INVITE_CLIENT_ID = "client_id=test-client-id";
const INVITE_PERMISSIONS = "permissions=1049608";
const INVITE_SCOPE = "scope=bot%20applications.commands";

test.describe("onboarding", () => {
  test("signed-out /onboarding redirects to the Discord OAuth start", async ({ request }) => {
    const res = await request.get("/onboarding", { maxRedirects: 0 });
    expect(res.status()).toBe(302);
    expect(res.headers().location).toBe(OAUTH_START);
  });

  test("signed-out /guilds redirects to the Discord OAuth start", async ({ request }) => {
    const res = await request.get("/guilds", { maxRedirects: 0 });
    expect(res.status()).toBe(302);
    expect(res.headers().location).toBe(OAUTH_START);
  });

  test("fake test-login signs in and lands on /guilds", async ({ page }) => {
    await page.goto("/auth/test-login");
    await expect(page).toHaveURL(/\/guilds$/);
    await expect(page.getByText("Your soundboards")).toBeVisible();
  });

  test("signed-in /onboarding shows an invite link and a continue link", async ({ page }) => {
    await page.goto("/auth/test-login");
    await page.goto("/onboarding");

    const invite = page.locator('a[target="_blank"]').filter({ hasText: /add the bot/i }).first();
    const href = await invite.getAttribute("href");
    expect(href).toContain("https://discord.com/oauth2/authorize");
    expect(href).toContain(INVITE_CLIENT_ID);
    expect(href).toContain(INVITE_PERMISSIONS);
    expect(href).toContain(INVITE_SCOPE);

    const cont = page.locator('a[href="/guilds"]');
    await expect(cont).toHaveCount(1);
  });

  test("the continue link on /onboarding lands on /guilds", async ({ page }) => {
    await page.goto("/auth/test-login");
    await page.goto("/onboarding");
    await page.locator('a[href="/guilds"]').click();
    await expect(page).toHaveURL(/\/guilds$/);
    await expect(page.getByText("Your soundboards")).toBeVisible();
  });

  test("/guilds links to /onboarding", async ({ page }) => {
    await page.goto("/auth/test-login");
    await page.goto("/guilds");
    const link = page.locator('a[href="/onboarding"]').filter({ hasText: /add the bot to a server/i });
    await expect(link).toHaveCount(1);
  });
});
