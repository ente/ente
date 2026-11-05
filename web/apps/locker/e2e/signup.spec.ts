import { expect, test } from "../../../e2e/fixtures/test";

test("signs up and opens Locker", async ({ signedInPage: page }) => {
    await expect(page).toHaveURL("/");
    await expect(
        page.getByText("Your Locker is empty", { exact: true }),
    ).toBeVisible();
});
