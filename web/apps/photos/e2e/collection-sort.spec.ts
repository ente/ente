import type { Locator, Page } from "@playwright/test";
import { expect, test } from "../../../e2e/fixtures/test";

const albumNames = /^Sort (Alpha|Beta|Gamma)$/;
const galleryKey = "collectionsSortBy";
const selectorKey = "collectionSelectorSortBy";

test.beforeEach(async ({ signedInPage: page }) => {
    await page.getByText("Continue with free plan", { exact: true }).click();
    const navigation = page.getByRole("navigation", {
        name: "Albums",
        exact: true,
    });
    for (const name of ["Sort Beta", "Sort Alpha", "Sort Gamma"]) {
        await navigation.getByRole("button", { name: "New album" }).click();
        const dialog = page.getByRole("dialog", { name: "New album" });
        await dialog.getByRole("textbox", { name: "Album name" }).fill(name);
        await dialog
            .getByRole("button", { name: "Create", exact: true })
            .click();
        await expect(dialog).toBeHidden();
        await expect(
            navigation.getByRole("button", { name, exact: true }),
        ).toBeVisible();
    }
    await page.goto("/gallery");
    await expect(
        navigation.getByRole("button", { name: albumNames }),
    ).toHaveCount(3);
});

const savedSorts = (page: Page) =>
    page.evaluate(
        ({ galleryKey, selectorKey }) => ({
            gallery: localStorage.getItem(galleryKey),
            selector: localStorage.getItem(selectorKey),
        }),
        { galleryKey, selectorKey },
    );

const openSelector = async (page: Page) => {
    await page.getByRole("button", { name: "Upload", exact: true }).click();
    const chooser = page.waitForEvent("filechooser");
    await page.getByRole("button", { name: "Files", exact: true }).click();
    await (
        await chooser
    ).setFiles({
        name: "sort-preferences.png",
        mimeType: "image/png",
        buffer: Buffer.from(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jp1sAAAAASUVORK5CYII=",
            "base64",
        ),
    });
    const dialog = page
        .getByRole("dialog")
        .filter({
            has: page.getByRole("textbox", { name: "Search for albums..." }),
        });
    await expect(dialog).toBeVisible();
    return dialog;
};

const chooseSort = async (page: Page, scope: Locator, category: string) => {
    await scope.getByRole("button", { name: "Sort by" }).click();
    await page
        .getByRole("menuitem", { name: new RegExp(`^${category}(?: |$)`) })
        .click();
};

test("keeps gallery and selector sorting independent and persistent", async ({
    signedInPage: page,
}) => {
    const navigation = page.getByRole("navigation", {
        name: "Albums",
        exact: true,
    });
    const albums = navigation.getByRole("button", { name: albumNames });
    await expect(albums).toHaveText(["Sort Gamma", "Sort Alpha", "Sort Beta"]);
    await navigation.getByRole("button", { name: "Sort by" }).click();
    await expect(
        page.getByRole("menuitem", { name: /^Updated.*Newest$/ }),
    ).toBeVisible();
    await page.keyboard.press("Escape");
    expect(await savedSorts(page)).toEqual({ gallery: null, selector: null });

    for (const { category, value, order } of [
        {
            category: "Name",
            value: "name-asc",
            order: ["Alpha", "Beta", "Gamma"],
        },
        {
            category: "Name",
            value: "name-desc",
            order: ["Gamma", "Beta", "Alpha"],
        },
        {
            category: "Created",
            value: "creation-time-desc",
            order: ["Gamma", "Alpha", "Beta"],
        },
        {
            category: "Created",
            value: "creation-time-asc",
            order: ["Beta", "Alpha", "Gamma"],
        },
        {
            category: "Updated",
            value: "updation-time-desc",
            order: ["Gamma", "Alpha", "Beta"],
        },
        {
            category: "Updated",
            value: "updation-time-asc",
            order: ["Beta", "Alpha", "Gamma"],
        },
    ]) {
        await chooseSort(page, navigation, category);
        await expect(albums).toHaveText(order.map((name) => `Sort ${name}`));
        expect(await savedSorts(page)).toEqual({
            gallery: value,
            selector: null,
        });
        await page.reload();
        await expect(albums).toHaveText(order.map((name) => `Sort ${name}`));
    }

    const dialog = await openSelector(page);
    const selectorAlbums = dialog.getByRole("button", {
        name: /^Sort (Alpha|Beta|Gamma) 0 items$/,
    });
    await expect(selectorAlbums).toHaveText([
        /Sort Alpha/,
        /Sort Beta/,
        /Sort Gamma/,
    ]);

    for (const { category, value, order } of [
        {
            category: "Name",
            value: "name-desc",
            order: ["Gamma", "Beta", "Alpha"],
        },
        {
            category: "Name",
            value: "name-asc",
            order: ["Alpha", "Beta", "Gamma"],
        },
        {
            category: "Created",
            value: "creation-time-desc",
            order: ["Gamma", "Alpha", "Beta"],
        },
        {
            category: "Created",
            value: "creation-time-asc",
            order: ["Beta", "Alpha", "Gamma"],
        },
        {
            category: "Updated",
            value: "updation-time-desc",
            order: ["Gamma", "Alpha", "Beta"],
        },
        {
            category: "Updated",
            value: "updation-time-asc",
            order: ["Beta", "Alpha", "Gamma"],
        },
    ]) {
        await chooseSort(page, dialog, category);
        await expect(selectorAlbums).toHaveText(
            order.map((name) => new RegExp(`Sort ${name}`)),
        );
        expect(await savedSorts(page)).toEqual({
            gallery: "updation-time-asc",
            selector: value,
        });
    }
    await chooseSort(page, dialog, "Name");
    await expect(selectorAlbums).toHaveText([
        /Sort Alpha/,
        /Sort Beta/,
        /Sort Gamma/,
    ]);
    await dialog.getByRole("button", { name: "Close", exact: true }).click();
    await expect(dialog).toBeHidden();
    await page.reload();
    await expect(albums).toHaveText(["Sort Beta", "Sort Alpha", "Sort Gamma"]);
    await openSelector(page);
    await expect(selectorAlbums).toHaveText([
        /Sort Alpha/,
        /Sort Beta/,
        /Sort Gamma/,
    ]);
    expect(await savedSorts(page)).toEqual({
        gallery: "updation-time-asc",
        selector: "name-asc",
    });
});

test("ignores invalid saved preferences without overwriting either key", async ({
    signedInPage: page,
}) => {
    await page.evaluate(
        ({ galleryKey, selectorKey }) => {
            localStorage.setItem(galleryKey, "invalid");
            localStorage.setItem(selectorKey, "NAME-ASC");
        },
        { galleryKey, selectorKey },
    );
    await page.reload();
    const navigation = page.getByRole("navigation", {
        name: "Albums",
        exact: true,
    });
    await expect(
        navigation.getByRole("button", { name: albumNames }),
    ).toHaveText(["Sort Gamma", "Sort Alpha", "Sort Beta"]);
    await navigation.getByRole("button", { name: "Sort by" }).click();
    await expect(
        page.getByRole("menuitem", { name: /^Updated.*Newest$/ }),
    ).toBeVisible();
    await page.keyboard.press("Escape");
    const dialog = await openSelector(page);
    await expect(
        dialog.getByRole("button", {
            name: /^Sort (Alpha|Beta|Gamma) 0 items$/,
        }),
    ).toHaveText([/Sort Alpha/, /Sort Beta/, /Sort Gamma/]);
    expect(await savedSorts(page)).toEqual({
        gallery: "invalid",
        selector: "NAME-ASC",
    });
    await chooseSort(page, dialog, "Name");
    await expect
        .poll(() => savedSorts(page))
        .toEqual({ gallery: "invalid", selector: "name-desc" });
});
