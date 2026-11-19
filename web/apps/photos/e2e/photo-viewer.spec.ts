import type { Locator, Page } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { expect, test } from "../../../e2e/fixtures/test";

const albumName = "Photo viewer";
const photos = [
    { name: "IMG-20200103-WA0000.png", color: "royalblue" },
    { name: "IMG-20200102-WA0000.png", color: "seagreen" },
    { name: "IMG-20200101-WA0000.png", color: "tomato" },
] as const;

const testWithPhotos = test.extend<{
    photoAlbum: { page: Page; thumbnails: Locator; buffers: Buffer[] };
}>({
    photoAlbum: async ({ signedInPage: page }, use) => {
        await page.setViewportSize({ width: 1440, height: 900 });
        await page
            .getByText("Continue with free plan", { exact: true })
            .click();

        const albums = page.getByRole("navigation", { name: "Albums" });
        await albums.getByRole("button", { name: "New album" }).click();
        const newAlbum = page.getByRole("dialog", { name: "New album" });
        await newAlbum
            .getByRole("textbox", { name: "Album name" })
            .fill(albumName);
        await newAlbum
            .getByRole("button", { name: "Create", exact: true })
            .click();
        await expect(newAlbum).toBeHidden();

        const images = await page.evaluate(
            (colors) => {
                const canvas = document.createElement("canvas");
                canvas.width = 1600;
                canvas.height = 1200;
                const context = canvas.getContext("2d")!;
                return colors.map((color) => {
                    context.fillStyle = color;
                    context.fillRect(0, 0, canvas.width, canvas.height);
                    return canvas.toDataURL().split(",")[1]!;
                });
            },
            photos.map(({ color }) => color),
        );
        const buffers = images.map((image) => Buffer.from(image, "base64"));

        await page.getByRole("button", { name: "Upload", exact: true }).click();
        const chooser = page.waitForEvent("filechooser");
        await page.getByRole("button", { name: "Files", exact: true }).click();
        await (
            await chooser
        ).setFiles(
            photos.map(({ name }, index) => ({
                name,
                mimeType: "image/png",
                buffer: buffers[index]!,
            })),
        );
        const uploadAlbum = page
            .getByRole("dialog")
            .filter({
                has: page.getByText("Upload to album", { exact: true }),
            });
        await uploadAlbum
            .getByRole("button", { name: /^Photo viewer\b/ })
            .click();
        await page
            .getByRole("button", { name: "Start upload", exact: true })
            .click();
        await albums
            .getByRole("button", { name: albumName, exact: true })
            .click();
        await expect(
            page.getByText("3 memories", { exact: true }),
        ).toBeVisible();
        await page
            .getByText("Upload complete", { exact: true })
            .locator("../..")
            .getByRole("button", { name: "Close", exact: true })
            .click();

        const thumbnails = page
            .locator('.photo-list input[type="checkbox"] + img')
            .locator("..");
        await expect(thumbnails).toHaveCount(photos.length);
        await use({ page, thumbnails, buffers });
    },
});

testWithPhotos(
    "navigates, zooms, and downloads the active photo",
    async ({ photoAlbum: { page, thumbnails, buffers } }) => {
        await thumbnails.first().click();

        const viewer = page.getByRole("dialog").and(page.locator(".pswp"));
        const counter = viewer.locator(".pswp__counter");
        const activeImage = viewer.locator(
            '[aria-hidden="false"] img.pswp__img:not(.pswp__img--placeholder)',
        );
        await expect(counter).toHaveText("1 / 3");
        // Wait for the original image to replace the thumbnail before zooming.
        await expect(activeImage).toHaveJSProperty("naturalWidth", 1600);
        const displayedWidth = () =>
            activeImage.evaluate((image) =>
                Math.round(image.getBoundingClientRect().width),
            );
        const fittedWidth = await displayedWidth();
        await activeImage.hover();
        await page.mouse.wheel(0, -500);
        await expect.poll(displayedWidth).toBeGreaterThan(fittedWidth);
        await page.mouse.wheel(0, 500);
        await expect.poll(displayedWidth).toBe(fittedWidth);

        await viewer.getByRole("button", { name: "Next", exact: true }).click();
        await expect(counter).toHaveText("2 / 3");
        await page.keyboard.press("ArrowRight");
        await expect(counter).toHaveText("3 / 3");
        await viewer
            .getByRole("button", { name: "Previous", exact: true })
            .click();
        await expect(counter).toHaveText("2 / 3");

        await viewer.getByRole("button", { name: "More", exact: true }).click();
        const [download] = await Promise.all([
            page.waitForEvent("download"),
            page
                .getByRole("menuitem", { name: "Download", exact: true })
                .click(),
        ]);
        expect(download.suggestedFilename()).toBe(photos[1].name);
        expect(await readFile(await download.path())).toEqual(buffers[1]);

        await viewer
            .getByRole("button", { name: "Close", exact: true })
            .click();
        await expect(viewer).toBeHidden();
        await expect(thumbnails).toHaveCount(photos.length);
    },
);

testWithPhotos(
    "keeps an edited description with its photo after navigation",
    async ({ photoAlbum: { page, thumbnails } }) => {
        await thumbnails.first().click();

        const viewer = page.getByRole("dialog").and(page.locator(".pswp"));
        const caption = viewer.locator(".pswp__caption");
        const description = "Blue photo from the viewer test";
        await viewer.getByRole("button", { name: "Info", exact: true }).click();
        await expect(
            page.getByRole("heading", { name: "Details" }),
        ).toBeVisible();
        await page.getByPlaceholder("Add a description").fill(description);
        const save = page.getByRole("button", { name: "Save", exact: true });
        await save.click();
        await expect(save).toBeHidden();
        await page
            .getByRole("button", { name: "Go back", exact: true })
            .click();
        await expect(caption).toHaveText(description);

        await page.keyboard.press("ArrowRight");
        await expect(viewer.locator(".pswp__counter")).toHaveText("2 / 3");
        await expect(caption).toBeHidden();
        await page.keyboard.press("ArrowLeft");
        await expect(caption).toHaveText(description);

        await page.keyboard.press("Escape");
        await expect(viewer).toBeHidden();
        await thumbnails.first().click();
        await expect(caption).toHaveText(description);
    },
);
