import { expect, type Page } from "@playwright/test";
import { randomUUID } from "node:crypto";

export const createAccount = () => {
    const suffix = process.env.ENTE_TEST_EMAIL_SUFFIX;
    if (
        !suffix ||
        !process.env.ENTE_TEST_EMAIL_CODE ||
        !process.env.NEXT_PUBLIC_ENTE_ENDPOINT
    ) {
        throw new Error(
            "Run npm run test:e2e to start an isolated test backend",
        );
    }
    return {
        email: `web-e2e-${randomUUID()}${suffix}`,
        password: `E2e-${randomUUID()}-A9!`,
    };
};

export const signUp = async (
    page: Page,
    account: ReturnType<typeof createAccount>,
) => {
    await page.goto("/signup");
    await page.getByLabel("Email address", { exact: true }).fill(account.email);
    await page.getByLabel("Password", { exact: true }).fill(account.password);
    await page
        .getByLabel("Confirm password", { exact: true })
        .fill(account.password);
    const terms = page.getByRole("checkbox");
    await terms.press("Space");
    await expect(terms).toBeChecked();
    await page
        .getByRole("button", { name: "Create account", exact: true })
        .click();

    await expect(page).toHaveURL(/\/verify$/);
    const code = process.env.ENTE_TEST_EMAIL_CODE!;
    for (let i = 0; i < code.length; i++) {
        await page
            .getByRole("textbox", {
                name: `Verification code ${i + 1}`,
                exact: true,
            })
            .fill(code[i]!);
    }
    await expect(
        page.getByRole("heading", { name: "Your recovery key" }),
    ).toBeVisible();
    await page
        .getByRole("button", { name: "Do this later", exact: true })
        .click();
};
