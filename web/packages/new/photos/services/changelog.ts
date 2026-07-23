import type { Electron } from "ente-base/types/ipc";

/**
 * The current changelog version.
 *
 * [Note: Conditions for showing "What's new"]
 *
 * We maintain a "changelog version". This version is an incrementing positive
 * integer, we increment it whenever we want to show this dialog again. Usually
 * we'd do this for each app update, but not necessarily.
 *
 * The "What's new" dialog is shown when the saved changelog version is less
 * than the current {@link changelogVersion}.
 *
 * The shown changelog version is saved on the Node.js layer since there we can
 * store it in the user preferences store, which is not cleared on logout.
 *
 * On app start, we read the last saved version:
 *
 * - If it is not present, we set it to the current version _without_ showing
 *   the what's new dialog. This is to handle fresh installs.
 *
 * - If it is present and less than the current version, we show the what's new
 *   dialog. Otherwise do nothing.
 *
 * The what's new dialog sets the saved version to the current one whenever it
 * is shown.
 */
const changelogVersion = 12;

/**
 * Return true if we should show the {@link WhatsNew} dialog.
 *
 * It has the side affect of updating the persisted version (whilst returning
 * false) if there was no previous persisted changelog version version present.
 */
export const shouldShowWhatsNew = async (electron: Electron) => {
    const lastShownVersion = await electron.lastShownChangelogVersion();

    if (!lastShownVersion) {
        // On a fresh install, save the current version but don't show the
        // what's new dialog.
        await electron.setLastShownChangelogVersion(changelogVersion);
        return false;
    }
    // Show what's new if the saved version is older than the current one.
    return lastShownVersion < changelogVersion;
};

/**
 * Set the saved changelog version to the current changelog version.
 */
export const didShowWhatsNew = async (electron: Electron) =>
    electron.setLastShownChangelogVersion(changelogVersion);
