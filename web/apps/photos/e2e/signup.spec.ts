import { createAccount, signUp } from "../../../e2e/fixtures/account";
import { expect, test } from "../../../e2e/fixtures/test";

test("signs up and opens the Photos gallery", async ({
    signedInPage: page,
}) => {
    await expect(page).toHaveURL(/\/plan$/);
    await page
        .getByRole("button", { name: "Continue with 10 GB plan" })
        .click();
    await expect(page).toHaveURL(/\/gallery$/);
    await expect(
        page.getByText("Upload your first photo", { exact: true }),
    ).toBeVisible();
});

test("compares monthly prices for grouped yearly prices during signup", async ({
    page,
}) => {
    await page.route("**/billing/user-plans", (route) => {
        if (route.request().method() !== "GET") return route.fallback();
        return route.fulfill({
            headers: { "access-control-allow-origin": "*" },
            json: {
                freePlan: { storage: 10 * 1024 ** 3 },
                plans: [
                    {
                        id: "50gb_monthly_v4",
                        stripeID: "price_test_monthly",
                        storage: 50 * 1024 ** 3,
                        price: "₹129",
                        period: "month",
                    },
                    {
                        id: "50gb_yearly_v4",
                        stripeID: "price_test_yearly",
                        storage: 50 * 1024 ** 3,
                        price: "₹1,199",
                        period: "year",
                    },
                ],
            },
        });
    });
    await signUp(page, createAccount());

    await expect(
        page.getByRole("radio", { name: /^50 GB / }),
    ).toHaveAccessibleName(/₹1,199\/year ₹129 ₹99\.92\/month/);
});
