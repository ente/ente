import type { Page } from "@playwright/test";
import type { LegacyInfo } from "ente-contacts/legacy/types";
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

    await openLegacy(page, owner.password);
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
    const invitation = await added;
    expect(invitation.ok()).toBe(true);
    expect(keyLookups).toBe(1);

    await openLegacy(contactPage, contact.password);
    const ownerRow = contactPage
        .getByText(owner.email, { exact: true })
        .and(contactPage.getByRole("paragraph", { includeHidden: true }));
    const inviteIcon = ownerRow.locator("..").locator("svg");
    await expect(inviteIcon).toBeVisible();
    await ownerRow.click();
    await contactPage.getByRole("button", { name: "Accept invite" }).click();
    await expect(inviteIcon).toHaveCount(0);
    await ownerRow.click();
    await contactPage.getByRole("button", { name: "Start recovery" }).click();
    const recoveryInfo = contactPage.waitForResponse((response) =>
        response.url().endsWith("/emergency-contacts/info"),
    );
    await contactPage
        .getByRole("dialog", { name: "Start recovery" })
        .getByRole("button", { name: "Start recovery" })
        .click();
    const info = (await (await recoveryInfo).json()) as LegacyInfo;
    const [session] = info.othersRecoverySession;
    if (!session) throw new Error("Expected a recovery session for the owner");

    // Locker Web has no owner approval button. Approve through the owner's API.
    const ownerHeaders = invitation.request().headers();
    const approved = await page.request.post(
        new URL("approve-recovery", invitation.url()).href,
        {
            headers: {
                "X-Auth-Token": ownerHeaders["x-auth-token"]!,
                "X-Client-Package": ownerHeaders["x-client-package"]!,
            },
            data: {
                id: session.id,
                userID: session.user.id,
                emergencyContactID: session.emergencyContact.id,
            },
        },
    );
    await expect(approved).toBeOK();

    await contactPage.reload();
    await openLegacy(contactPage, contact.password);
    await ownerRow.click();
    await contactPage.getByRole("button", { name: "Recover account" }).click();
    const newPassword = owner.password + "-recovered";
    await contactPage.getByLabel("Password", { exact: true }).fill(newPassword);
    await contactPage
        .getByLabel("Confirm password", { exact: true })
        .fill(newPassword);
    await contactPage.getByRole("button", { name: "Reset password" }).click();
    await expect(
        contactPage.getByText("Account recovered", { exact: true }),
    ).toBeVisible();
    await contactPage.close();
});

const openLegacy = async (page: Page, password: string) => {
    await page
        .getByAltText("Locker", { exact: true })
        .locator("..")
        .getByRole("button")
        .click();
    await page.getByText("Legacy", { exact: true }).click();
    await page
        .getByRole("dialog")
        .getByLabel("Password", { exact: true })
        .fill(password);
    await page
        .getByRole("button", { name: "Authenticate", exact: true })
        .click();
};
