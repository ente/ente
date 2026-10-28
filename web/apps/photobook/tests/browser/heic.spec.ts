import { expect, test } from "@playwright/test";
import { readSession } from "./session";

test("imports HEIC through Ente's conversion worker", async ({ page }) => {
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.goto("/");
    await expect(
        page.getByRole("button", { name: "Add photos", exact: true }),
    ).toBeEnabled();
    await page
        .locator('input[type="file"]')
        .setInputFiles("tests/browser/fixtures/import.heic");
    await page.waitForURL("**/app");
    await expect
        .poll(async () => (await readSession(page)).photos?.length)
        .toBe(1);
    const photo = (await readSession(page)).photos![0]!;
    expect(photo.width).toBe(64);
    expect(photo.height).toBe(48);
    await expect(page.locator("canvas").first()).toBeVisible();
    await expect(
        page.getByRole("button", { name: "Add photos", exact: true }),
    ).toBeEnabled();
    expect(errors).toEqual([]);
});
