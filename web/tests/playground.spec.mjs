import { expect, test } from "@playwright/test";

const browserErrors = new WeakMap();

test.beforeEach(async ({ page }) => {
  const errors = [];
  browserErrors.set(page, errors);
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto("/");
  await expect(page).toHaveTitle("MoonWren Playground");
});

test.afterEach(async ({ page }) => {
  expect(browserErrors.get(page), "browser console and page errors").toEqual([]);
});

test("runs source and renders compile diagnostics", async ({ page }) => {
  await expect(page.locator("#output")).toHaveText("55\n=> 55");
  await page.locator("#source").fill("System.print(40 + 2)");
  await page.locator("#run").click();
  await expect(page.locator("#output")).toHaveText("42\n=> 42");

  await page.locator("#source").fill("var =");
  await page.locator("#run").click();
  await expect(page.locator("#output")).toContainText("expected variable name");
});

test("runs Fiber and UTF-8 examples", async ({ page }) => {
  await page.locator("#example").selectOption("fiber");
  await expect(page.locator("#output")).toContainText("started\npaused\nfinished");

  await page.locator("#example").selectOption("unicode");
  await expect(page.locator("#output")).toHaveText("12\n16\n你\n=> 你");
});

test("preserves shared source and resets the playground", async ({ page }) => {
  const shared = "System.print(6 * 7)";
  await page.locator("#source").fill(shared);
  await page.locator("#share").click();
  await expect(page).toHaveURL(/#.+/);
  await page.reload();
  await expect(page.locator("#source")).toHaveValue(shared);
  await expect(page.locator("#output")).toHaveText("42\n=> 42");

  await page.locator("#reset").click();
  await expect(page.locator("#source")).toHaveValue(/var total = 0/);
  await expect(page.locator("#output")).toHaveText("55\n=> 55");
});

test("evaluates through a real module worker", async ({ page }) => {
  const result = await page.evaluate(async () => {
    const { createWorker } = await import("./sdk.mjs");
    const worker = createWorker();
    try {
      return await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error("worker timed out")), 10_000);
        worker.addEventListener("message", (event) => {
          clearTimeout(timer);
          resolve(event.data);
        }, { once: true });
        worker.addEventListener("error", (event) => {
          clearTimeout(timer);
          reject(new Error(event.message));
        }, { once: true });
        worker.postMessage({ id: "acceptance", source: "System.print(40 + 2)" });
      });
    } finally {
      worker.terminate();
    }
  });

  expect(result).toEqual({
    id: "acceptance",
    result: { ok: true, value: "42", output: ["42"], diagnostics: [] },
  });
});
