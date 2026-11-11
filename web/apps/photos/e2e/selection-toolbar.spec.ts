import { expect, test } from "../../../e2e/fixtures/test";

test("keeps album selection actions reachable across toolbar widths", async ({
    signedInPage: page,
}) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.getByText("Continue with free plan", { exact: true }).click();

    const albumName = "Toolbar test";
    const navigation = page.getByRole("navigation", {
        name: "Albums",
        exact: true,
    });
    for (const name of [albumName, "Destination album"]) {
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
    await (
        await chooser
    ).setFiles({
        name: "selection-toolbar.png",
        mimeType: "image/png",
        buffer: Buffer.from(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jp1sAAAAASUVORK5CYII=",
            "base64",
        ),
    });
    const uploadAlbum = page
        .getByRole("dialog")
        .filter({ has: page.getByText("Upload to album", { exact: true }) });
    await uploadAlbum.getByRole("button", { name: /^Toolbar test\b/ }).click();
    await expect(uploadAlbum).toBeHidden();
    await navigation
        .getByRole("button", { name: albumName, exact: true })
        .click();
    await expect(page.getByText("1 memory", { exact: true })).toBeVisible();

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

    // The sidebar can make the toolbar too narrow even above the mobile breakpoint.
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
