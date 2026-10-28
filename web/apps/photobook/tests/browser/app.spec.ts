import { expect, test, type Page } from "@playwright/test";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { resolve } from "node:path";
import type { AppView, BookState, Photo } from "../../src/lib/types";

const requireFromProject = createRequire(resolve("package.json"));

async function readSession(page: Page) {
    return page.evaluate(async () => {
        const database = await new Promise<IDBDatabase>((resolve, reject) => {
            const request = indexedDB.open("ente-photobook");
            request.onsuccess = () => resolve(request.result);
            request.onerror = () =>
                reject(
                    new Error("Cannot open saved book", {
                        cause: request.error,
                    }),
                );
        });
        try {
            const store = database
                .transaction("metadata")
                .objectStore("metadata");
            const read = (key: string) =>
                new Promise<unknown>((resolve, reject) => {
                    const request = store.get(key);
                    request.onsuccess = () => resolve(request.result);
                    request.onerror = () =>
                        reject(
                            new Error("Cannot read saved book", {
                                cause: request.error,
                            }),
                        );
                });
            const [book, photos, view] = await Promise.all(
                ["bookState", "photos", "appView"].map(read),
            );
            return {
                book: book as BookState | undefined,
                photos: photos as Photo[] | undefined,
                view: view as AppView | undefined,
            };
        } finally {
            database.close();
        }
    });
}

test("imports, restores, edits, previews, exports and resets a book", async ({
    page,
}, testInfo) => {
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    page.on("console", (message) => {
        if (message.type() === "error") errors.push(message.text());
    });
    await page.goto("/");
    await expect(
        page.getByRole("button", { name: "Add photos", exact: true }),
    ).toBeEnabled();
    const image = await page.evaluate(() => {
        const canvas = document.createElement("canvas");
        canvas.width = 640;
        canvas.height = 480;
        const context = canvas.getContext("2d")!;
        context.fillStyle = "#146a89";
        context.fillRect(0, 0, 640, 480);
        context.fillStyle = "#ffab30";
        context.fillRect(80, 80, 200, 320);
        return canvas.toDataURL("image/png").split(",")[1]!;
    });
    await page
        .locator('input[type="file"]')
        .setInputFiles(
            Array.from({ length: 4 }, (_, index) => ({
                name: `photo-${index}.png`,
                mimeType: "image/png",
                buffer: Buffer.from(image, "base64"),
            })),
        );
    await page.waitForURL("**/app/");
    await expect(page.locator("canvas").first()).toBeVisible();
    await expect(
        page.getByRole("button", { name: "Add photos", exact: true }),
    ).toBeEnabled();
    await page
        .getByRole("textbox", { name: "Photobook title", exact: true })
        .fill("Saved browser test");
    await page
        .getByRole("textbox", { name: "Photobook title", exact: true })
        .press("Enter");
    await expect
        .poll(async () => {
            const session = await readSession(page);
            return (
                session.book?.title === "Saved browser test" &&
                session.photos?.length === 4 &&
                session.view === "edit"
            );
        })
        .toBe(true);
    const saved = (await readSession(page)).book!;
    await page.reload();
    await expect(
        page.getByRole("textbox", { name: "Photobook title", exact: true }),
    ).toHaveValue(saved.title!);
    await expect(page.locator("canvas").first()).toBeVisible();
    expect((await readSession(page)).book).toEqual(saved);

    await page.getByRole("button", { name: "Add page", exact: true }).click();
    await page
        .getByRole("dialog")
        .getByRole("button", { name: "Add page", exact: true })
        .click();
    await expect(page.getByRole("dialog")).toBeHidden();
    await expect
        .poll(async () => (await readSession(page)).book?.pages.length)
        .toBe(saved.pages.length + 2);
    await page.getByRole("button", { name: "Undo", exact: true }).click();
    await expect
        .poll(async () => (await readSession(page)).book?.pages.length)
        .toBe(saved.pages.length);
    await page.getByRole("button", { name: "Redo", exact: true }).click();
    await expect
        .poll(async () => (await readSession(page)).book?.pages.length)
        .toBe(saved.pages.length + 2);

    await page.getByRole("combobox", { name: "Cover type" }).click();
    await page.getByRole("option", { name: "Softcover", exact: true }).click();
    await expect
        .poll(
            async () =>
                (await readSession(page)).book?.printSelection?.productId,
        )
        .toMatch(/^softcover/);
    await page.getByRole("button", { name: "Preview", exact: true }).click();
    await expect(
        page.getByRole("heading", { name: /Add \d+ more pages/ }),
    ).toBeVisible();
    await page
        .getByRole("button", { name: "Back to editing", exact: true })
        .click();
    await expect(page.getByRole("dialog")).toBeHidden();

    const book = (await readSession(page)).book!;
    const content = book.pages.slice(1, -1);
    book.pages = [
        book.pages[0]!,
        ...Array.from({ length: 22 }, (_, index) => ({
            ...structuredClone(content[index % content.length]!),
            id: `interior-${index}`,
            centerText: `Page ${index + 1}`,
        })),
        book.pages.at(-1)!,
    ];
    await page.evaluate(async (value) => {
        const database = await new Promise<IDBDatabase>((resolve, reject) => {
            const request = indexedDB.open("ente-photobook");
            request.onsuccess = () => resolve(request.result);
            request.onerror = () =>
                reject(
                    new Error("Cannot open saved book", {
                        cause: request.error,
                    }),
                );
        });
        try {
            await new Promise<void>((resolve, reject) => {
                const transaction = database.transaction(
                    "metadata",
                    "readwrite",
                );
                transaction.objectStore("metadata").put(value, "bookState");
                transaction.oncomplete = () => resolve();
                transaction.onerror = () =>
                    reject(
                        new Error("Cannot save fixture", {
                            cause: transaction.error,
                        }),
                    );
            });
        } finally {
            database.close();
        }
    }, book);
    await page.reload();
    await page.getByRole("button", { name: "Preview", exact: true }).click();
    await expect(
        page.getByRole("button", { name: "Download", exact: true }),
    ).toBeEnabled();
    await page.getByRole("button", { name: "Next pages", exact: true }).click();
    await expect(
        page.getByRole("button", { name: "Previous pages", exact: true }),
    ).toBeEnabled();
    await page.getByRole("combobox", { name: "Current page" }).click();
    await page.getByRole("option", { name: "Back cover", exact: true }).click();
    await expect(
        page.getByRole("button", { name: "Next pages", exact: true }),
    ).toBeDisabled();
    await expect(
        page.getByRole("button", { name: "Previous pages", exact: true }),
    ).toBeEnabled();
    await page
        .getByRole("button", { name: "Previous pages", exact: true })
        .click();
    await expect(
        page.getByRole("button", { name: "Next pages", exact: true }),
    ).toBeEnabled();

    const wasmResponse = page.waitForResponse((response) =>
        /\/_next\/static\/media\/.*\.wasm$/.test(
            new URL(response.url()).pathname,
        ),
    );
    const downloadPromise = page.waitForEvent("download");
    await page.getByRole("button", { name: "Download", exact: true }).click();
    const download = await downloadPromise;
    expect(await download.failure()).toBeNull();
    const output = testInfo.outputPath("photobook.pdf");
    await download.saveAs(output);
    const pdf = (await readFile(output)).toString("latin1");
    expect(pdf.startsWith("%PDF-")).toBe(true);
    expect(pdf).toContain("/Count 24");
    expect(pdf.match(/\/Type \/Page\b/g)).toHaveLength(24);
    expect(pdf.match(/\/MediaBox \[0 0 595\.27559 595\.27559\]/g)).toHaveLength(
        24,
    );
    expect(pdf.match(/\/ColorSpace \/DeviceCMYK/g)).toHaveLength(24);
    expect(pdf).toContain("/S /GTS_PDFX");
    expect(pdf.endsWith("%%EOF\n")).toBe(true);
    const response = await wasmResponse;
    expect(response.ok()).toBe(true);
    const expectedWasm = await readFile(
        requireFromProject.resolve("@imagemagick/magick-wasm/magick.wasm"),
    );
    const hash = (bytes: Uint8Array) =>
        createHash("sha256").update(bytes).digest("hex");
    expect(hash(await response.body())).toBe(hash(expectedWasm));

    await page.getByRole("button", { name: "Edit", exact: true }).click();
    await page.getByRole("button", { name: "Reset", exact: true }).click();
    await page.keyboard.press("Escape");
    await expect(page.getByRole("dialog")).toBeHidden();
    expect((await readSession(page)).book?.pages).toHaveLength(24);
    await page.getByRole("button", { name: "Reset", exact: true }).click();
    await page
        .getByRole("dialog")
        .getByRole("button", { name: "Reset", exact: true })
        .click();
    await expect
        .poll(async () => (await readSession(page)).book)
        .toBeUndefined();
    await page.reload();
    await expect(
        page.getByRole("button", { name: "Preview", exact: true }),
    ).toBeHidden();
    expect(errors).toEqual([]);
});
