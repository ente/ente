import type { Page } from "@playwright/test";
import { expect, test } from "../../../e2e/fixtures/test";

const fixture = {
    name: "locker-upload.txt",
    mimeType: "text/plain",
    buffer: Buffer.from("Locker upload test\n"),
};

async function createCollection(page: Page, name: string) {
    await page.goto("/collections");
    await page.getByRole("button", { name: "Create collection" }).click();
    const dialog = page.getByRole("dialog");
    await dialog.getByLabel("Enter collection name").fill(name);
    await dialog.getByRole("button", { name: "Create collection" }).click();
    await expect(page).toHaveURL(/\/collection\?id=\d+/);
}

async function openUpload(page: Page) {
    await page.goto("/");
    await page.getByRole("button", { name: "Save to Locker" }).click();
    const dialog = page.getByRole("dialog");
    await dialog.getByRole("button", { name: /^Document\b/ }).click();
    await dialog.locator('input[type="file"]').setInputFiles(fixture);
    return dialog;
}

async function saveUpload(page: Page) {
    await page
        .getByRole("dialog")
        .getByRole("button", { name: "Save", exact: true })
        .click();
    await expect(
        page.getByText("Item uploaded successfully", { exact: true }),
    ).toBeVisible();
    await page.reload();
}

async function openCollection(page: Page, name: string) {
    await page.goto("/collections");
    await page.getByText(name, { exact: true }).click();
    await expect(page).toHaveURL(/\/collection\?id=\d+/);
}

test("uploads a file to the selected collection", async ({
    signedInPage: page,
}) => {
    await createCollection(page, "Selected collection");
    await createCollection(page, "Other collection");

    const upload = await openUpload(page);
    await upload
        .getByRole("button", { name: "Selected collection", exact: true })
        .click();
    await saveUpload(page);

    await openCollection(page, "Selected collection");
    await expect(page.getByText(fixture.name, { exact: true })).toBeVisible();
    await openCollection(page, "Other collection");
    await expect(
        page.getByText("There are no items in this collection"),
    ).toBeVisible();
    await expect(page.getByText(fixture.name, { exact: true })).toHaveCount(0);
});

test("uploads a file to a collection created in the upload dialog", async ({
    signedInPage: page,
}) => {
    const name = "Created during upload";
    const upload = await openUpload(page);
    await upload
        .getByRole("button", { name: "Collection", exact: true })
        .click();
    await upload.getByPlaceholder("Enter collection name").fill(name);
    await upload.getByRole("button", { name: "Create", exact: true }).click();
    await saveUpload(page);

    await openCollection(page, name);
    await expect(page.getByText(fixture.name, { exact: true })).toBeVisible();
});
