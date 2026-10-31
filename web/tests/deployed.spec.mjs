import { expect, test } from "@playwright/test";

test("deployed playground executes Wren without browser errors", async ({ page }) => {
  const errors = [];
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });
  page.on("pageerror", (error) => errors.push(error.message));

  // Resolve relative to baseURL so repository Pages deployments retain their
  // /<repository>/ path instead of navigating to the account-site root.
  await page.goto("./");
  await expect(page).toHaveTitle("MoonWren Playground");
  await page.locator("#source").fill("System.print(40 + 2)");
  await page.locator("#run").click();
  await expect(page.locator("#output")).toHaveText("42\n=> 42");
  expect(errors).toEqual([]);
});
