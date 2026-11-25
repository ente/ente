import { createAccount, signUp } from "../../../e2e/fixtures/account";
import { expect, test } from "../../../e2e/fixtures/test";

test("adds a trusted contact using the key shown during verification", async ({
    page,
    browser,
    baseURL,
}) => {
    const owner = createAccount();
    const contact = createAccount();
    const contactPage = await browser.newPage({ baseURL });
    await signUp(contactPage, contact);
    await contactPage.close();
    await signUp(page, owner);

    let keyLookups = 0;
    page.on("request", (request) => {
        const url = new URL(request.url());
        if (
            request.method() === "GET" &&
            url.pathname === "/users/public-key" &&
            url.searchParams.get("email") === contact.email
        )
            keyLookups++;
    });

    await page
        .getByAltText("Locker", { exact: true })
        .locator("..")
        .getByRole("button")
        .click();
    await page.getByText("Legacy", { exact: true }).click();
    await page
        .getByRole("dialog")
        .getByLabel("Password", { exact: true })
        .fill(owner.password);
    await page
        .getByRole("button", { name: "Authenticate", exact: true })
        .click();
    const add = page.getByRole("button", {
        name: "Add trusted contact",
        exact: true,
    });
    await add.click();
    await page.getByPlaceholder("Enter email").fill(contact.email);
    await page.getByRole("button", { name: "Verify", exact: true }).click();
    await expect(
        page.getByText(`Verification ID for ${contact.email}`),
    ).toBeVisible();
    await page.keyboard.press("Escape");
    await add.click();
    const confirmation = page.getByRole("dialog", {
        name: "Add trusted contact?",
    });
    const added = page.waitForResponse(
        (response) =>
            response.url().endsWith("/emergency-contacts/add") &&
            response.request().method() === "POST",
    );
    await confirmation
        .getByRole("button", { name: "Add trusted contact" })
        .click();
    expect((await added).ok()).toBe(true);
    expect(keyLookups).toBe(1);
});
