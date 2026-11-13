import { compareVersions } from "compare-versions";
import { default as electronLog } from "electron-log";
import { autoUpdater } from "electron-updater";
import { app, BrowserWindow } from "electron/main";
import { allowWindowClose } from "../../main";
import { AppUpdate } from "../../types/ipc";
import log from "../log";
import { userPreferences } from "../stores/user-preferences";
import { isDev } from "../utils/electron";

export const setupAutoUpdater = (mainWindow: BrowserWindow) => {
    autoUpdater.logger = electronLog;
    autoUpdater.autoDownload = false;
    autoUpdater.disableWebInstaller = true;
    // Differential downloads currently break some Windows NSIS updates.
    // https://github.com/electron-userland/electron-builder/issues/9181
    autoUpdater.disableDifferentialDownload = true;
    // Dev builds use dev-app-update.yml for manual checks, but never poll.
    autoUpdater.forceDevUpdateConfig = isDev;
    if (isDev) return;

    const oneDay = 1 * 24 * 60 * 60 * 1000;
    setInterval(() => void checkForUpdatesAndNotify(mainWindow), oneDay);
    void checkForUpdatesAndNotify(mainWindow);
};

export const forceCheckForAppUpdates = (mainWindow: BrowserWindow) => {
    userPreferences.delete("skipAppVersion");
    userPreferences.delete("muteUpdateNotificationVersion");
    void checkForUpdatesAndNotify(mainWindow, { notifyImmediately: true });
};

interface CheckForUpdatesAndNotifyOpts {
    notifyImmediately?: boolean;
}

const checkForUpdatesAndNotify = async (
    mainWindow: BrowserWindow,
    opts?: CheckForUpdatesAndNotifyOpts,
) => {
    const updateCheckResult = await autoUpdater.checkForUpdates();
    if (!updateCheckResult) {
        log.error("Failed to check for updates");
        return;
    }

    const { version } = updateCheckResult.updateInfo;

    log.debug(() => `Update check found version ${version}`);

    if (!version)
        throw new Error("Unexpected empty version obtained from auto-updater");

    if (compareVersions(version, app.getVersion()) <= 0) {
        log.debug(() => "Skipping update, already at latest version");
        return;
    }

    if (version == userPreferences.get("skipAppVersion")) {
        log.info(`User chose to skip version ${version}`);
        return;
    }

    const mutedVersion = userPreferences.get("muteUpdateNotificationVersion");
    if (version == mutedVersion) {
        log.info(`User has muted update notifications for version ${version}`);
        return;
    }

    const showUpdateDialog = (update: AppUpdate) =>
        mainWindow.webContents.send("appUpdateAvailable", update);

    let timeout: ReturnType<typeof setTimeout>;
    const fiveMinutes = 5 * 60 * 1000;
    autoUpdater.on("update-downloaded", () => {
        log.info(`Update downloaded ${version}`);
        timeout = setTimeout(
            () => showUpdateDialog({ autoUpdatable: true, version }),
            opts?.notifyImmediately ? 0 : fiveMinutes,
        );
    });

    autoUpdater.on("error", (error) => {
        clearTimeout(timeout);
        log.error("Auto update failed", error);
        showUpdateDialog({ autoUpdatable: false, version });
    });

    log.info(`Downloading update ${version}`);
    await autoUpdater.downloadUpdate();
};

export const appVersion = () => `v${app.getVersion()}`;

export const updateAndRestart = () => {
    log.info("Restarting the app to apply update");
    allowWindowClose();
    autoUpdater.quitAndInstall();
};

export const updateOnNextRestart = (version: string) =>
    userPreferences.set("muteUpdateNotificationVersion", version);

export const skipAppUpdate = (version: string) =>
    userPreferences.set("skipAppVersion", version);
