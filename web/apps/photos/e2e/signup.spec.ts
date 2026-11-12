import { expect, test } from "../../../e2e/fixtures/test";

test("signs up and opens the Photos gallery", async ({
    signedInPage: page,
}) => {
    await expect(page).toHaveURL(/\/plan$/);
    await page.getByText("Continue with free plan", { exact: true }).click();
    await expect(page).toHaveURL(/\/gallery$/);
    await expect(
        page.getByText("Upload your first photo", { exact: true }),
    ).toBeVisible();
});
