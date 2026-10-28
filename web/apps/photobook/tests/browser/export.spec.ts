import { expect, test } from "@playwright/test";
import JSZip from "jszip";
import { readFile } from "node:fs/promises";

test("exports 24 real PNG pages at print resolution", async ({
    page,
}, testInfo) => {
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    page.on("console", (message) => {
        if (message.type() === "error") errors.push(message.text());
    });
    await page.goto("http://127.0.0.1:4318/tests/browser/export.html");
    const downloadPromise = page.waitForEvent("download");
    await page.getByRole("button", { name: "Export PNG pages" }).click();
    const download = await downloadPromise;
    expect(await download.failure()).toBeNull();
    const output = testInfo.outputPath("pages.zip");
    await download.saveAs(output);
    const zip = await JSZip.loadAsync(await readFile(output));
    expect(Object.keys(zip.files).sort()).toEqual(
        Array.from(
            { length: 24 },
            (_, index) => `page_${String(index + 1).padStart(3, "0")}.png`,
        ),
    );
    for (const file of Object.values(zip.files)) {
        const bytes = await file.async("nodebuffer");
        expect(bytes.subarray(0, 8)).toEqual(
            Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
        );
        expect(bytes.readUInt32BE(16)).toBe(2480);
        expect(bytes.readUInt32BE(20)).toBe(2480);
    }
    await expect(page.locator("#status")).toHaveText("Done");
    expect(errors).toEqual([]);
});
