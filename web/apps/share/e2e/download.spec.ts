import { expect, test } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { createAccount, signUp } from "../../../e2e/fixtures/account";

for (const { label, tail } of [
    { label: "a full final chunk", tail: "" },
    { label: "a short final chunk", tail: "End of the shared file.\n" },
]) {
    test(`downloads the original file from a public Locker link with ${label}`, async ({
        browser,
        page,
    }, testInfo) => {
        const fileName = "share-download.txt";
        const contents = Buffer.concat([
            Buffer.alloc(4 * 1024 * 1024, "a"),
            Buffer.from(tail),
        ]);

        const lockerURL: unknown = testInfo.project.metadata.lockerURL;
        if (typeof lockerURL !== "string")
            throw new Error("Missing Locker URL");
        const sender = await browser.newContext({ baseURL: lockerURL });
        let link: URL;
        try {
            const locker = await sender.newPage();
            await signUp(locker, createAccount());
            await locker
                .getByRole("button", { name: "Save to Locker" })
                .click();
            const upload = locker.getByRole("dialog");
            await upload.getByRole("button", { name: /^Document\b/ }).click();
            await upload
                .locator('input[type="file"]')
                .setInputFiles({
                    name: fileName,
                    mimeType: "text/plain",
                    buffer: contents,
                });
            await upload
                .getByRole("button", { name: "Save", exact: true })
                .click();
            const uploaded = locker.getByRole("dialog", {
                name: "Item uploaded successfully",
            });
            await uploaded
                .getByRole("button", { name: "Share", exact: true })
                .click();
            const shareDialog = locker.getByRole("dialog", { name: fileName });
            const publicURL = shareDialog.getByText(/^https?:\/\/\S+#\S+$/);
            await expect(publicURL).toBeVisible();
            link = new URL(await publicURL.innerText());
        } finally {
            await sender.close();
        }

        // Open the generated link in a separate context, using the local Share app.
        await page.goto(link.pathname + link.search + link.hash);
        await expect(page.getByText(fileName, { exact: true })).toBeVisible();
        const downloadEvent = page.waitForEvent("download");
        await page
            .getByRole("button", { name: "Download", exact: true })
            .click();
        const download = await downloadEvent;
        expect(download.suggestedFilename()).toBe(fileName);
        const downloadedPath = testInfo.outputPath(fileName);
        await download.saveAs(downloadedPath);
        expect((await readFile(downloadedPath)).equals(contents)).toBe(true);
    });
}
