import { test as base, type Page } from "@playwright/test";
import { createAccount, signUp } from "./account";

export const test = base.extend<{ signedInPage: Page }>({
    signedInPage: async ({ page }, use) => {
        await signUp(page, createAccount());
        await use(page);
    },
});

export { expect } from "@playwright/test";
