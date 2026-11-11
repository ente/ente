import type { Page } from "@playwright/test";
import { randomInt } from "node:crypto";
import { expect, test } from "../../../e2e/fixtures/test";

test.use({ actionTimeout: 15_000 });

const albumName = "Toolbar test";
const desktop = { width: 1440, height: 900 };
const mobile = { width: 320, height: 700 };
const importedCaptureDate = "Mon, Jan 4, 2021";
const filenameCaptureDate = "Wed, Jan 1, 2020";

const expectAlbumSize = (page: Page, count: number) =>
    expect(
        page.getByText(count === 1 ? "1 memory" : `${count} memories`, {
            exact: true,
        }),
    ).toBeVisible();

const testPhotos = async (page: Page, count: number) => {
    const images = await page.evaluate((count) => {
        const canvas = document.createElement("canvas");
        canvas.width = canvas.height = 32;
        const context = canvas.getContext("2d")!;
        return Array.from({ length: count }, (_, index) => {
            context.fillStyle = `hsl(${index * 19}, 80%, 50%)`;
            context.fillRect(0, 0, canvas.width, canvas.height);
            return canvas.toDataURL().split(",")[1]!;
        });
    }, count);
    return images.map((image, index) => ({
        name: `IMG-20200101-WA${String(index).padStart(4, "0")}.png`,
        mimeType: "image/png",
        buffer: Buffer.from(image, "base64"),
    }));
};

const openAlbumWithPhotos = async (
    page: Page,
    photos: Awaited<ReturnType<typeof testPhotos>>,
    destinationAlbums: string[],
    metadataSidecars = false,
) => {
    await page.setViewportSize(desktop);
    await page.getByText("Continue with free plan", { exact: true }).click();

    const navigation = page.getByRole("navigation", {
        name: "Albums",
        exact: true,
    });
    for (const name of [albumName, ...destinationAlbums]) {
        await navigation.getByRole("button", { name: "New album" }).click();
        const newAlbum = page.getByRole("dialog", { name: "New album" });
        await newAlbum.getByRole("textbox", { name: "Album name" }).fill(name);
        await newAlbum
            .getByRole("button", { name: "Create", exact: true })
            .click();
        await expect(newAlbum).toBeHidden();
    }

    await page.getByRole("button", { name: "Upload", exact: true }).click();
    const chooser = page.waitForEvent("filechooser");
    await page.getByRole("button", { name: "Files", exact: true }).click();
    const sidecars = metadataSidecars
        ? photos.map(({ name }) => ({
              name: `${name}.json`,
              mimeType: "application/json",
              buffer: Buffer.from(
                  JSON.stringify({
                      photoTakenTime: {
                          timestamp: Date.parse("2021-01-04T12:00:00Z") / 1000,
                      },
                  }),
              ),
          }))
        : [];
    await (await chooser).setFiles([...photos, ...sidecars]);
    const uploadAlbum = page
        .getByRole("dialog")
        .filter({ has: page.getByText("Upload to album", { exact: true }) });
    await uploadAlbum.getByRole("button", { name: /^Toolbar test\b/ }).click();
    await expect(uploadAlbum).toBeHidden();
    if (photos.length > 1) {
        await page
            .getByRole("button", {
                name: metadataSidecars ? "Start import" : "Start upload",
                exact: true,
            })
            .click();
    }
    await navigation
        .getByRole("button", { name: albumName, exact: true })
        .click();
    await expectAlbumSize(page, photos.length);
    const uploadComplete = page.getByText("Upload complete", { exact: true });
    await uploadComplete
        .locator("../..")
        .getByRole("button", { name: "Close", exact: true })
        .click();
};

test("keeps album selection actions reachable across toolbar widths", async ({
    signedInPage: page,
}) => {
    await openAlbumWithPhotos(page, await testPhotos(page, 1), [
        "Destination album",
    ]);

    const toolbar = page.getByRole("toolbar", { name: "1 selected" });
    const albumMenu = page.locator("#collection-options-trigger");
    const selectionMenu = toolbar.getByRole("button", { name: "More options" });
    const photoCheckbox = page.locator('input[type="checkbox"]:not([name])');
    const actionNames = [
        "Favorite",
        "Fix time",
        "Edit location",
        "Send link",
        "Download",
        "Add",
        "Move",
        "Remove",
        "Hide",
        "Delete",
    ];

    await expect(albumMenu).toBeEnabled();
    await photoCheckbox.locator("..").hover();
    await photoCheckbox.check();
    await expect(albumMenu).toBeDisabled();
    for (const name of actionNames) {
        await expect(
            toolbar.getByRole("button", { name, exact: true }),
        ).toBeVisible();
    }
    await expect(selectionMenu).toBeHidden();

    await page.setViewportSize({ width: 1000, height: 900 });
    await expect(selectionMenu).toBeVisible();
    await page.getByRole("button", { name: "Hide navigation panel" }).click();
    await expect(
        toolbar.getByRole("button", { name: "Favorite" }),
    ).toBeVisible();
    await expect(selectionMenu).toBeHidden();

    await page.setViewportSize({ width: 320, height: 700 });
    await selectionMenu.click();
    const menu = page.getByRole("menu");
    await expect(menu.getByRole("menuitem")).toHaveText(actionNames);
    await menu.getByRole("menuitem", { name: "Favorite", exact: true }).click();
    await expect(toolbar).toBeHidden();
    await expect(albumMenu).toBeEnabled();

    await photoCheckbox.locator("..").hover();
    await photoCheckbox.check();
    await selectionMenu.click();
    await expect(
        menu.getByRole("menuitem", { name: "Unfavorite" }),
    ).toBeVisible();
    await menu.getByRole("menuitem", { name: "Add", exact: true }).click();
    const addToAlbum = page
        .getByRole("dialog")
        .filter({ has: page.getByText("Add to album", { exact: true }) });
    await expect(
        addToAlbum.getByRole("button", { name: /^Destination album/ }),
    ).toBeVisible();
    await addToAlbum
        .getByRole("button", { name: "Close", exact: true })
        .click();

    await toolbar.getByRole("button", { name: "Deselect all" }).click();
    await expect(toolbar).toBeHidden();
    await expect(albumMenu).toBeEnabled();
});

const shuffled = <T>(items: readonly T[], random: () => number) => {
    const result = [...items];
    for (let i = result.length - 1; i > 0; i--) {
        const j = Math.floor(random() * (i + 1));
        [result[i], result[j]] = [result[j]!, result[i]!];
    }
    return result;
};

test("performs every selection action on shuffled batches of photos", async ({
    signedInPage: page,
}, testInfo) => {
    test.setTimeout(180_000);
    const seed = process.env.ENTE_E2E_SELECTION_SEED
        ? Number(process.env.ENTE_E2E_SELECTION_SEED) >>> 0
        : randomInt(2 ** 32);
    testInfo.annotations.push({
        type: "selection seed",
        description: String(seed),
    });
    let state = seed;
    const random = () => {
        state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
        return state / 2 ** 32;
    };

    let remaining = 15;
    await openAlbumWithPhotos(
        page,
        await testPhotos(page, remaining),
        ["Add destination", "Move destination"],
        true,
    );

    const toolbar = page.getByRole("toolbar");
    const thumbnails = page.locator('input[type="checkbox"]:not([name])');
    const dialog = page.getByRole("dialog");
    const finishAlbumChange = async (title: string, destination: string) => {
        const picker = dialog.filter({
            has: page.getByText(title, { exact: true }),
        });
        await picker
            .getByRole("button", { name: new RegExp(`^${destination}`) })
            .click();
        await expect(picker).toBeHidden();
    };

    const operations = [
        {
            name: "Favorite",
            run: async (click: () => Promise<void>) => {
                await click();
                await expect(toolbar).toBeHidden();
            },
        },
        {
            name: "Fix time",
            run: async (click: () => Promise<void>) => {
                const importedDate = page.getByText(importedCaptureDate, {
                    exact: true,
                });
                const filenameDate = page.getByText(filenameCaptureDate, {
                    exact: true,
                });
                await expect(importedDate).toBeVisible();
                await expect(filenameDate).toBeHidden();
                await click();
                const fixTime = page.getByRole("dialog", { name: "Fix time" });
                await fixTime.getByRole("radio", { name: "File name" }).check();
                await fixTime.getByRole("button", { name: "Fix time" }).click();
                await expect(fixTime.getByRole("status")).toHaveText(
                    "Successfully updated all files",
                );
                await fixTime
                    .getByRole("button", { name: "Close", exact: true })
                    .last()
                    .click();
                await page.setViewportSize(desktop);
                await expect(filenameDate).toBeVisible();
            },
        },
        {
            name: "Edit location",
            run: async (click: () => Promise<void>) => {
                await click();
                const editLocation = page.getByRole("dialog", {
                    name: /^(Add|Edit) location$/,
                });
                await editLocation
                    .getByLabel("Latitude", { exact: true })
                    .fill("12.5");
                await editLocation
                    .getByLabel("Longitude", { exact: true })
                    .fill("77.5");
                const saveLocation = editLocation.getByRole("button", {
                    name: "Save location",
                });
                await expect(saveLocation).toBeEnabled();
                await saveLocation.press("Enter");
                await expect(editLocation).toBeHidden();
            },
        },
        {
            name: "Send link",
            run: async (click: () => Promise<void>) => {
                await click();
                const linkCreated = page
                    .getByRole("status")
                    .filter({ hasText: "Link created" });
                await expect(linkCreated).toBeVisible();
                await page
                    .getByRole("button", { name: "Copy link", exact: true })
                    .locator("..")
                    .getByRole("button", { name: "Close", exact: true })
                    .click();
            },
        },
        {
            name: "Download",
            run: async (click: () => Promise<void>) => {
                const [download] = await Promise.all([
                    page.waitForEvent("download"),
                    click(),
                ]);
                expect(download.suggestedFilename()).toMatch(/\.zip$/i);
                expect(await download.failure()).toBeNull();
            },
        },
        {
            name: "Add",
            run: async (click: () => Promise<void>) => {
                await click();
                await finishAlbumChange("Add to album", "Add destination");
            },
        },
        {
            name: "Move",
            removesPhotos: true,
            run: async (click: () => Promise<void>) => {
                await click();
                await finishAlbumChange("Move to album", "Move destination");
            },
        },
        {
            name: "Remove",
            removesPhotos: true,
            run: async (click: () => Promise<void>) => {
                await click();
                await dialog
                    .getByRole("button", { name: "Yes, remove" })
                    .click();
            },
        },
        {
            name: "Hide",
            removesPhotos: true,
            run: async (click: () => Promise<void>) => {
                await click();
            },
        },
        {
            name: "Delete",
            removesPhotos: true,
            run: async (click: () => Promise<void>) => {
                await click();
                await dialog
                    .getByRole("button", { name: "Move to trash" })
                    .click();
            },
        },
    ];

    const navigation = page.getByRole("navigation", {
        name: "Albums",
        exact: true,
    });
    for (const operation of shuffled(operations, random)) {
        const batchSize = random() < 0.5 ? 2 : 3;
        const useMenu = random() < 0.5;
        await test.step(`${operation.name} ${batchSize} photos (seed ${seed})`, async () => {
            await page.setViewportSize(desktop);
            await expect(thumbnails).toHaveCount(remaining);
            const selected = shuffled(
                Array.from({ length: remaining }, (_, index) => index),
                random,
            ).slice(0, batchSize);
            for (const index of selected) {
                const checkbox = thumbnails.nth(index);
                await expect(async () => {
                    await checkbox.locator("..").hover({ timeout: 1500 });
                    await checkbox.check({ timeout: 1500 });
                }).toPass({ timeout: 10_000 });
            }
            await expect(toolbar).toHaveAccessibleName(`${batchSize} selected`);
            const click = async () => {
                if (useMenu) {
                    await page.setViewportSize(mobile);
                    await toolbar
                        .getByRole("button", { name: "More options" })
                        .click();
                    await page
                        .getByRole("menuitem", {
                            name: operation.name,
                            exact: true,
                        })
                        .click();
                } else {
                    await toolbar
                        .getByRole("button", {
                            name: operation.name,
                            exact: true,
                        })
                        .click();
                }
            };
            await operation.run(click);
            if (operation.removesPhotos) remaining -= batchSize;
            await expectAlbumSize(page, remaining);
            if (operation.name === "Edit location") {
                await toolbar.getByRole("button", { name: "Close" }).click();
            }
            await expect(toolbar).toBeHidden();
            const destination =
                operation.name === "Favorite"
                    ? "Favorites"
                    : operation.name === "Add" || operation.name === "Move"
                      ? `${operation.name} destination`
                      : undefined;
            if (destination) {
                await page.setViewportSize(desktop);
                await navigation
                    .getByRole("button", { name: destination, exact: true })
                    .click();
                await expectAlbumSize(page, batchSize);
                await navigation
                    .getByRole("button", { name: albumName, exact: true })
                    .click();
                await expectAlbumSize(page, remaining);
            }
        });
    }
});
