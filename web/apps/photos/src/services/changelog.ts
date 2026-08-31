import type { Electron } from "ente-base/types/ipc";

const changelogVersion = 14;

export const shouldShowWhatsNew = async (electron: Electron) => {
    const lastShownVersion = await electron.lastShownChangelogVersion();

    if (!lastShownVersion) {
        // A fresh install saves the version without showing the dialog.
        await electron.setLastShownChangelogVersion(changelogVersion);
        return false;
    }
    return lastShownVersion < changelogVersion;
};

export const didShowWhatsNew = async (electron: Electron) =>
    electron.setLastShownChangelogVersion(changelogVersion);
