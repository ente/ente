import { nativeImage, shell } from "electron/common";
import {
    BrowserWindow,
    Menu,
    Tray,
    app,
    dialog,
    nativeTheme,
    protocol,
    type WebContents,
} from "electron/main";
import serveNextAt from "next-electron-server";
import { existsSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import {
    attachFSWatchIPCHandlers,
    attachIPCHandlers,
    attachLogoutIPCHandler,
    attachMainWindowIPCHandlers,
} from "./main/ipc";
import log, { initLogging } from "./main/log";
import { createApplicationMenu, createTrayContextMenu } from "./main/menu";
import { setupAutoUpdater } from "./main/services/app-update";
import autoLauncher from "./main/services/auto-launcher";
import { shouldHideDockIcon } from "./main/services/store";
import { createWatcher } from "./main/services/watch";
import { userPreferences } from "./main/stores/user-preferences";
import { registerStreamProtocol } from "./main/stream";
import { wait } from "./main/utils/common";
import { isDev } from "./main/utils/electron";

const rendererURL = "ente://app";

// Closing normally hides the window so exports and folder watches keep running.
// Quit paths set this flag to close it for real.
let shouldAllowWindowClose = false;

export const allowWindowClose = (): void => {
    shouldAllowWindowClose = true;
};

const main = () => {
    const gotTheLock = app.requestSingleInstanceLock();
    if (!gotTheLock) {
        app.quit();
        return;
    }

    let mainWindow: BrowserWindow | undefined;

    initLogging();
    logStartupBanner();
    registerForEnteLinks();

    // Electron keeps the last privileged-scheme registration. This must follow
    // next-electron-server's registration so both "ente" and "stream" survive.
    setupRendererServer();
    registerPrivilegedSchemes();

    const handleOpenEnteURLEnsuringWindow = (url: string) => {
        log.info(`Attempting to handle request to open URL: ${url}`);
        if (mainWindow) handleEnteLinks(mainWindow, url);
        else setTimeout(() => handleOpenEnteURLEnsuringWindow(url), 1000);
    };

    app.on("second-instance", (_, argv: string[]) => {
        if (mainWindow) {
            mainWindow.show();
            if (mainWindow.isMinimized()) mainWindow.restore();
            mainWindow.focus();
        }

        // Chromium may reorder or insert arguments, so the URL has no fixed index.
        const url = argv.find((arg) => arg.startsWith("ente://app"));
        if (url) handleOpenEnteURLEnsuringWindow(url);
    });

    void app.whenReady().then(() => {
        attachProcessHandlers();

        void (async () => {
            if (isDev) await waitForRendererDevServer();

            mainWindow = createMainWindow();

            const watcher = createWatcher(mainWindow);
            attachIPCHandlers();
            attachMainWindowIPCHandlers(mainWindow);
            attachFSWatchIPCHandlers(watcher);
            attachLogoutIPCHandler(watcher);
            registerStreamProtocol(mainWindow);

            const webContents = mainWindow.webContents;
            setDownloadPath(webContents);
            allowExternalLinks(webContents);
            handleBackOnStripeCheckout(mainWindow);
            allowAllCORSOrigins(webContents);
            allowOpenStreetMapRequestIdentification(webContents);

            void mainWindow.loadURL(rendererURL);

            Menu.setApplicationMenu(createApplicationMenu(mainWindow));
            setupTrayItem(mainWindow);
            setupAutoUpdater(mainWindow);
        })();
    });

    app.on("activate", () => mainWindow?.show());

    app.on("before-quit", () => {
        if (mainWindow) saveWindowBounds(mainWindow);
        allowWindowClose();
    });

    app.on("open-url", (_, url) => handleOpenEnteURLEnsuringWindow(url));
};

const logStartupBanner = () => {
    const version = isDev ? "dev" : app.getVersion();
    log.info(`Starting ente-photos-desktop ${version}`);

    const platform = process.platform;
    const osRelease = os.release();
    const systemVersion = process.getSystemVersion();
    log.info("Running on", { platform, osRelease, systemVersion });
};

const setupRendererServer = () => serveNextAt(rendererURL, { port: 3008 });

const registerPrivilegedSchemes = () => {
    protocol.registerSchemesAsPrivileged([
        {
            scheme: "ente",
            privileges: {
                standard: true,
                secure: true,
                allowServiceWorkers: true,
                supportFetchAPI: true,
                corsEnabled: true,
            },
        },
        {
            scheme: "stream",
            privileges: { supportFetchAPI: true, corsEnabled: true },
        },
    ]);
};

const registerForEnteLinks = () => app.setAsDefaultProtocolClient("ente");

const handleEnteLinks = (mainWindow: BrowserWindow, url: string) => {
    // Deep links and the bundled renderer deliberately share the ente:// scheme.
    mainWindow.webContents.send("openEnteURL", url);
};

const attachProcessHandlers = () => {
    // Electron's default SIGINT shutdown can lose recent storage writes in dev.
    process.on("SIGINT", () => app.quit());
};

// loadURL does not retry if the Next dev server returns ERR_CONNECTION_REFUSED.
const waitForRendererDevServer = () => wait(1000);

const createMainWindow = () => {
    const icon = nativeImage.createFromPath(
        path.join(isDev ? "build" : process.resourcesPath, "window-icon.png"),
    );
    const bounds = windowBounds();
    const shouldUseDarkColors =
        userPreferences.get("isDarkMode") ?? nativeTheme.shouldUseDarkColors;

    const window = new BrowserWindow({
        webPreferences: {
            preload: path.join(__dirname, "preload.js"),
            sandbox: true,
        },
        icon,
        ...(bounds ?? {}),
        ...minimumWindowSize(),
        // The overlay must be enabled on macOS too for its CSS dimensions.
        titleBarStyle: "hidden",
        titleBarOverlay:
            process.platform == "win32"
                ? {
                      color: shouldUseDarkColors ? "black" : "white",
                      symbolColor: shouldUseDarkColors ? "#cdcdcd" : "black",
                  }
                : true,
        // Match the initial paint to the OS theme to avoid a white or black flash.
        backgroundColor: shouldUseDarkColors ? "black" : "white",
        show: false,
    });

    const wasAutoLaunched = autoLauncher.wasAutoLaunched();
    if (wasAutoLaunched) {
        app.dock?.hide();
    } else {
        bounds ? window.show() : window.maximize();
    }

    if (isDev) window.webContents.openDevTools();

    window.webContents.on("render-process-gone", (_, details) => {
        log.error(`render-process-gone: ${details.reason}`);
        window.webContents.reload();
    });

    window.webContents.on("unresponsive", () => {
        log.warn("MainWindow's webContents are unresponsive");
    });

    window.on("close", (event) => {
        if (!shouldAllowWindowClose) {
            event.preventDefault();
            // macOS also emits "hide" for occlusion, so change the Dock here only.
            if (shouldHideDockIcon()) {
                app.dock?.hide();
            }
            window.hide();
        }
        return false;
    });

    window.on("show", () => void app.dock?.show());

    window.on("focus", () => window.webContents.send("mainWindowFocus"));
    window.on("blur", () => window.webContents.send("mainWindowBlur"));

    return window;
};

const windowBounds = () => {
    if (userPreferences.get("isWindowMaximized")) return undefined;

    const bounds = userPreferences.get("windowBounds");
    if (bounds) return bounds;

    return { width: 1170, height: 710 };
};

const minimumWindowSize = () => ({ minWidth: 200, minHeight: 200 });

const saveWindowBounds = (window: BrowserWindow) => {
    if (window.isMaximized()) {
        userPreferences.set("isWindowMaximized", true);
        userPreferences.delete("windowBounds");
    } else {
        userPreferences.delete("isWindowMaximized");
        userPreferences.set("windowBounds", window.getBounds());
    }
};

const setDownloadPath = (webContents: WebContents) => {
    webContents.session.on("will-download", (_, item) => {
        item.setSavePath(
            uniqueSavePath(app.getPath("downloads"), item.getFilename()),
        );
    });
};

const uniqueSavePath = (dirPath: string, fileName: string) => {
    const { name, ext } = path.parse(fileName);

    let savePath = path.join(dirPath, fileName);
    let n = 1;
    while (existsSync(savePath)) {
        const suffixedName = [`${name}(${n})`, ext].filter((x) => x).join(".");
        savePath = path.join(dirPath, suffixedName);
        n++;
    }
    return savePath;
};

const allowExternalLinks = (webContents: WebContents) =>
    webContents.setWindowOpenHandler(({ url }) => {
        if (!url.startsWith(rendererURL)) {
            const isAllowedScheme = (() => {
                try {
                    const u = new URL(url);
                    return (
                        u.protocol === "http:" ||
                        u.protocol === "https:" ||
                        u.protocol === "mailto:"
                    );
                } catch {
                    return false;
                }
            })();

            if (isAllowedScheme) {
                void shell.openExternal(url);
            } else {
                log.warn(`Blocked external open for disallowed scheme: ${url}`);
            }
            return { action: "deny" };
        } else {
            return { action: "allow" };
        }
    });

// Electron hides Stripe's beforeunload dialog, leaving an invisible modal that
// wedges navigation and quit. Recreate the browser prompt ourselves.
const handleBackOnStripeCheckout = (window: BrowserWindow) =>
    window.webContents.on("will-prevent-unload", (event) => {
        const url = new URL(window.webContents.getURL());

        if (url.host != "checkout.stripe.com") return;

        const choice = dialog.showMessageBoxSync(window, {
            type: "question",
            buttons: ["Leave", "Stay"],
            title: "Leave site?",
            message: "Changes that you made may not be saved.",
            defaultId: 0,
            cancelId: 1,
        });
        const leave = choice === 0;
        if (leave) event.preventDefault();
    });

// B2 answers ente://app uploads with Access-Control-Allow-Origin: null. Rewrite
// missing/null values only; wildcards break Stripe hCaptcha's credentialed calls.
const allowAllCORSOrigins = (webContents: WebContents) =>
    webContents.session.webRequest.onHeadersReceived(
        ({ responseHeaders }, callback) => {
            const headers: NonNullable<typeof responseHeaders> = {};

            headers["Access-Control-Allow-Origin"] = ["*"];
            for (const [key, value] of Object.entries(responseHeaders ?? {}))
                if (key.toLowerCase() == "access-control-allow-origin") {
                    headers["Access-Control-Allow-Origin"] =
                        value[0] == "null" ? ["*"] : value;
                } else {
                    headers[key] = value;
                }

            callback({ responseHeaders: headers });
        },
    );

// OSM requires application identification; custom-scheme requests lack one.
const allowOpenStreetMapRequestIdentification = (webContents: WebContents) =>
    webContents.session.webRequest.onBeforeSendHeaders(
        {
            urls: [
                "https://tile.openstreetmap.org/*",
                "https://nominatim.openstreetmap.org/*",
            ],
        },
        ({ requestHeaders }, callback) => {
            const existingUserAgent =
                requestHeaders["User-Agent"] ?? requestHeaders["user-agent"];
            delete requestHeaders["User-Agent"];
            delete requestHeaders["user-agent"];
            requestHeaders["User-Agent"] =
                openStreetMapUserAgent(existingUserAgent);
            delete requestHeaders.Referer;
            delete requestHeaders.referer;
            callback({ requestHeaders });
        },
    );

const openStreetMapUserAgent = (existingUserAgent: string | undefined) => {
    const appName = app.getName().trim() || "app";
    const version = isDev ? "dev" : app.getVersion();
    const appIdentifier = `${appName}-desktop/${version}`;
    return existingUserAgent
        ? `${appIdentifier} ${existingUserAgent}`
        : appIdentifier;
};

const setupTrayItem = (mainWindow: BrowserWindow) => {
    const iconName =
        process.platform == "darwin"
            ? "taskbar-icon-Template.png"
            : "taskbar-icon.png";
    const trayImgPath = path.join(
        isDev ? "build" : process.resourcesPath,
        iconName,
    );
    const trayIcon = nativeImage.createFromPath(trayImgPath);
    const tray = new Tray(trayIcon);
    tray.setToolTip("Ente Photos");
    tray.setContextMenu(createTrayContextMenu(mainWindow));
    if (process.platform === "linux") {
        tray.on("click", () => {
            if (mainWindow.isFocused()) {
                mainWindow.hide();
            } else {
                mainWindow.show();
            }
        });
    }
};

main();
