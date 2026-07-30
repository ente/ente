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
    // This is going to be the default at some point, right now if we don't
    // explicitly set this to true then electron-builder prints a (harmless)
    // warning when updating on Windows.
    // See: https://github.com/electron-userland/electron-builder/pull/6575
    autoUpdater.disableWebInstaller = true;
    // Disable differential downloads to fix Windows NSIS update issues
    // See: https://github.com/electron-userland/electron-builder/issues/9181
    autoUpdater.disableDifferentialDownload = true;
    /**
     * [Note: Testing auto updates]
     *
     * By default, we skip checking for updates automatically in dev builds.
     * This is because even if installing updates would fail (at least on macOS)
     * because auto updates only work for signed builds.
     *
     * So an end to end testing for updates requires using a temporary GitHub
     * repository and signed builds therein. More on this later.
     *
     * ---------------
     *
     * [Note: Testing auto updates - Sanity checks]
     *
     * However, for partial checks of the UI flow, something like the following
     * can be used to do a test of the update process (up until the actual
     * installation itself).
     *
     * Create a `app/dev-app-update.yml` with:
     *
     *     provider: generic
     *     url: http://127.0.0.1:7777/
     *
     * and start a local webserver in some directory:
     *
     *     python3 -m http.server 7777
     *
     * In this directory, put `latest-mac.yml` and the DMG file that this YAML
     * file refers to.
     *
     * Alternatively, `dev-app-update.yml` can point to some arbitrary GitHub
     * repository too, e.g.:
     *
     *       provider: github
     *       owner: ente
     *       repo: test-desktop-updates
     *
     * Now we can use the "Check for updates..." menu option to trigger the
     * update flow.
     */
    autoUpdater.forceDevUpdateConfig = isDev;
    if (isDev) return;

    /**
     * [Note: Testing auto updates - End to end checks]
     *
     * Since end-to-end update testing can only be done with signed builds, the
     * easiest way is to create temporary builds in a test repository.
     *
     * Let us say we have v2.0.0 about to go out. We have builds artifacts for
     * v2.0.0 also in some draft release in our normal release repository.
     *
     * Create a new test repository, say `ente/test-desktop-updates`. In this
     * repository, create a release v2.0.0, attaching the actual build
     * artifacts. Make this release the latest.
     *
     * Now we need to create a old signed build.
     *
     * First, modify `package.json` to put in a version number older than the
     * new version number that we want to test updating to, e.g. `v1.0.0-test`.
     *
     * Then uncomment the following block of code. This tells the auto updater
     * to use `ente/test-desktop-updates` to get updates.
     *
     * With these two changes (older version and setFeedURL), create a new
     * release signed build on CI. Install this build - it will check for
     * updates in the temporary feed URL that we set, and we'll be able to check
     * the full update flow.
     */

    /*
    autoUpdater.setFeedURL({
        provider: "github",
        owner: "ente",
        repo: "test-desktop-updates",
    });
    */

    const oneDay = 1 * 24 * 60 * 60 * 1000;
    setInterval(() => void checkForUpdatesAndNotify(mainWindow), oneDay);
    void checkForUpdatesAndNotify(mainWindow);
};

/**
 * Check for app update check ignoring any previously saved skips / mutes.
 */
export const forceCheckForAppUpdates = (mainWindow: BrowserWindow) => {
    userPreferences.delete("skipAppVersion");
    userPreferences.delete("muteUpdateNotificationVersion");
    void checkForUpdatesAndNotify(mainWindow, { notifyImmediately: true });
};

interface CheckForUpdatesAndNotifyOpts {
    /**
     * By default, the updater waits for 5 minutes after an update has been
     * downloaded before notifying the user. This is so as to not get in their
     * way during an app launch.
     *
     * However, when the user clicks the "Check for updates..." menu action,
     * they would prefer more immediate feedback, so this flag allows us to
     * bypass this delay.
     */
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

/**
 * Return the version of the desktop app.
 *
 * The return value is of the form `v1.2.3`.
 */
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
