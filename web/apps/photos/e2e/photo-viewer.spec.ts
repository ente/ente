import type { Locator, Page } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { expect, test } from "../../../e2e/fixtures/test";

const albumName = "Photo viewer";
const photos = [
    { name: "IMG-20200103-WA0000.png", color: "royalblue", width: 1600 },
    { name: "IMG-20200102-WA0000.png", color: "seagreen", width: 1500 },
    { name: "IMG-20200101-WA0000.png", color: "tomato", width: 1400 },
    { name: "IMG-20191231-WA0000.png", color: "goldenrod", width: 1300 },
] as const;

const testWithPhotos = test.extend<{
    photoAlbum: { page: Page; thumbnails: Locator; buffers: Buffer[] };
}>({
    photoAlbum: async ({ signedInPage: page }, use) => {
        await page.setViewportSize({ width: 1440, height: 900 });
        await page
            .getByRole("button", {
                name: "Continue with 10 GB plan",
                exact: true,
            })
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

        const images = await page.evaluate((fixtures) => {
            const canvas = document.createElement("canvas");
            canvas.height = 1200;
            const context = canvas.getContext("2d")!;
            return fixtures.map(({ color, width }) => {
                canvas.width = width;
                context.fillStyle = color;
                context.fillRect(0, 0, canvas.width, canvas.height);
                return canvas.toDataURL().split(",")[1]!;
            });
        }, photos);
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
            page.getByText(`${photos.length} memories`, { exact: true }),
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
        await expect(counter).toHaveText("1 / 4");
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
        await expect(counter).toHaveText("2 / 4");
        await expect(activeImage).toBeVisible();
        await expect(activeImage).toHaveJSProperty(
            "naturalWidth",
            photos[1].width,
        );
        await page.keyboard.press("ArrowRight");
        await expect(counter).toHaveText("3 / 4");
        await expect(activeImage).toBeVisible();
        await expect(activeImage).toHaveJSProperty(
            "naturalWidth",
            photos[2].width,
        );
        await viewer
            .getByRole("button", { name: "Previous", exact: true })
            .click();
        await expect(counter).toHaveText("2 / 4");
        await expect(activeImage).toBeVisible();
        await expect(activeImage).toHaveJSProperty(
            "naturalWidth",
            photos[1].width,
        );

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
    "wraps keyboard focus inside the Home photo viewer",
    async ({ photoAlbum: { page, thumbnails } }) => {
        await page.setViewportSize({ width: 1280, height: 800 });
        await page.getByRole("button", { name: "Home", exact: true }).click();
        const feed = page.getByRole("button", { name: "Feed", exact: true });
        await expect(feed).toBeVisible();
        await thumbnails.first().click();

        const viewer = page.locator(".pswp");
        const next = viewer.getByRole("button", { name: "Next", exact: true });
        await expect(next).toBeVisible();
        await next.focus();
        await page.keyboard.press("Tab");
        const first = viewer.locator(":focus");
        await expect(first).toHaveCount(1);
        await expect(next).not.toBeFocused();

        await page.keyboard.press("Shift+Tab");
        await expect(next).toBeFocused();

        // Even if another component moves focus behind the viewer, Enter
        // must not activate the background navigation.
        await feed.focus();
        await expect(feed).toBeFocused();
        await page.keyboard.press("Enter");
        await expect(viewer).toBeVisible();
        await expect(feed).toHaveAttribute("aria-pressed", "false");
        await page.keyboard.press("Tab");
        await expect(first).toHaveCount(1);
    },
);

testWithPhotos(
    "keeps an edited description with its photo after navigation",
    async ({ photoAlbum: { page, thumbnails } }) => {
        await thumbnails.first().click();

        const viewer = page.getByRole("dialog").and(page.locator(".pswp"));
        const activeImage = viewer.locator(
            '[aria-hidden="false"] img.pswp__img:not(.pswp__img--placeholder)',
        );
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
        await expect(caption).toBeVisible();
        await expect(activeImage).toBeVisible();
        await expect(activeImage).toHaveJSProperty(
            "naturalWidth",
            photos[0].width,
        );

        await page.keyboard.press("ArrowRight");
        await expect(viewer.locator(".pswp__counter")).toHaveText("2 / 4");
        await expect(activeImage).toBeVisible();
        await expect(activeImage).toHaveJSProperty(
            "naturalWidth",
            photos[1].width,
        );
        await expect(caption).toBeHidden();
        await page.keyboard.press("ArrowLeft");
        await expect(caption).toHaveText(description);
        await expect(caption).toBeVisible();
        await expect(activeImage).toBeVisible();
        await expect(activeImage).toHaveJSProperty(
            "naturalWidth",
            photos[0].width,
        );

        await page.keyboard.press("Escape");
        await expect(viewer).toBeHidden();
        await thumbnails.first().click();
        await expect(caption).toHaveText(description);
        await expect(caption).toBeVisible();
        await expect(activeImage).toBeVisible();
        await expect(activeImage).toHaveJSProperty(
            "naturalWidth",
            photos[0].width,
        );
    },
);

testWithPhotos(
    "keeps the correct photo centered after moving a photo to trash",
    async ({ photoAlbum: { page, thumbnails } }) => {
        await thumbnails.first().click();
        const viewer = page.locator(".pswp");
        const counter = viewer.locator(".pswp__counter");
        const activeImage = viewer.locator(
            '[aria-hidden="false"] img.pswp__img:not(.pswp__img--placeholder)',
        );
        await expect(activeImage).toHaveJSProperty(
            "naturalWidth",
            photos[0].width,
        );
        await viewer.getByRole("button", { name: "More", exact: true }).click();
        await page
            .getByRole("menuitem", { name: "Delete", exact: true })
            .click();
        const confirm = page.getByRole("dialog", { name: "Delete file?" });
        await confirm.getByRole("button", { name: "Move to trash" }).click();
        await expect(confirm).toBeHidden();
        await expect(counter).toHaveText("1 / 3");
        await expect(viewer).toBeVisible();
        await expect(activeImage).toBeVisible();
        await expect(activeImage).toHaveJSProperty(
            "naturalWidth",
            photos[1].width,
        );

        for (const [index, photo] of photos.slice(2).entries()) {
            await viewer
                .getByRole("button", { name: "Next", exact: true })
                .click();
            await expect(counter).toHaveText(`${index + 2} / 3`);
            await expect(activeImage).toBeVisible();
            await expect(activeImage).toHaveJSProperty(
                "naturalWidth",
                photo.width,
            );
        }

        await expect
            .poll(() =>
                activeImage.evaluate(async (image) => {
                    let previousLeft = image.getBoundingClientRect().left;
                    for (let frame = 0; frame < 6; frame++) {
                        await new Promise<void>((resolve) =>
                            requestAnimationFrame(() => resolve()),
                        );
                        const left = image.getBoundingClientRect().left;
                        if (Math.abs(left - previousLeft) > 0.1) return false;
                        previousLeft = left;
                    }
                    return true;
                }),
            )
            .toBe(true);

        const horizontalOffset = await activeImage.evaluate((image) => {
            const { left, right } = image.getBoundingClientRect();
            return Math.abs((left + right) / 2 - window.innerWidth / 2);
        });

        await page.keyboard.press("i");
        await expect(
            page.getByRole("heading", { name: "Details" }),
        ).toBeVisible();
        await expect(
            page.getByText(photos[3].name, { exact: true }),
        ).toBeVisible();

        expect(horizontalOffset).toBeLessThan(2);
    },
);
