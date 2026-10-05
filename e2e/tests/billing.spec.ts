import { expect, test } from "@playwright/test";

// Billing is dormant without STRIPE_SECRET_KEY (the dev server boots with none
// set). A dormant deployment must behave as if the routes do not exist. The
// live checkout/portal flows need Stripe test keys and are verified with the
// Stripe CLI forwarding webhooks; they are not covered here.
test.describe("billing dormancy", () => {
  test("/billing 404s when Stripe is unconfigured", async ({ request }) => {
    const res = await request.get("/billing");
    expect(res.status()).toBe(404);
  });

  test("the guild index renders without a plan line crash when unconfigured", async ({ page }) => {
    await page.goto("/auth/test-login");
    await page.goto("/guilds");
    await expect(page.getByText("Your soundboards")).toBeVisible();
  });
});
