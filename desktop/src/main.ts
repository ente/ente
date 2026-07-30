/**
 * @file Entry point for the main (Node.js) process of our Electron app.
 *
 * The code in this file is invoked by Electron when our app starts -
 * Conceptually (after all the transpilation etc has happened) this can be
 * thought of `electron main.ts`. We're running in the context of the so called
 * "main" process which runs in a Node.js environment.
 *
 * https://www.electronjs.org/docs/latest/tutorial/process-model#the-main-process
 */

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

/**
 * The URL where the renderer HTML is being served from.
 */
const rendererURL = "ente://app";

/**
 * We want to hide our window instead of closing it when the user presses the
 * cross button on the window.
 *
 * > This is because there is 1. a perceptible initial window creation time for
 * > our app, and 2. because the long running processes like export and watch
 * > folders are tied to the lifetime of the window and otherwise won't run in
 * > the background.
 *
 * Intercepting the window close event and using that to instead hide it is
 * easy, however that prevents the actual app quit to stop working (since the
 * window never gets closed).
 *
 * So to achieve our original goal (hide window instead of closing) without
 * disabling expected app quits, we keep a flag, and we turn it on when we're
 * part of the quit sequence. When this flag is on, we bypass the code that
 * prevents the window from being closed.
 */
let shouldAllowWindowClose = false;

export const allowWindowClose = (): void => {
    shouldAllowWindowClose = true;
};

/**
 * The app's entry point.
 *
 * We call this at the end of this file.
 */
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
    // The order of the next two calls is important
    setupRendererServer();
    registerPrivilegedSchemes();

    /**
     * Handle an open URL request, but ensuring that we have a mainWindow.
     */
    const handleOpenEnteURLEnsuringWindow = (url: string) => {
        log.info(`Attempting to handle request to open URL: ${url}`);
        if (mainWindow) handleEnteLinks(mainWindow, url);
        else setTimeout(() => handleOpenEnteURLEnsuringWindow(url), 1000);
    };

    app.on("second-instance", (_, argv: string[]) => {
        // Someone tried to run a second instance, we should focus our window.
        if (mainWindow) {
            mainWindow.show();
            if (mainWindow.isMinimized()) mainWindow.restore();
            mainWindow.focus();
        }
        // On Windows and Linux, this is how we get deeplinks.
        //
        // See: registerForEnteLinks
        //
        // Note that Chromium reserves the right to fudge with the order of the
        // command line arguments, including inserting things in arbitrary
        // places, so we need to go through the args to find the one that is
        // pertinent to us (if any) instead of looking at a fixed position.
        const url = argv.find((arg) => arg.startsWith("ente://app"));
        if (url) handleOpenEnteURLEnsuringWindow(url);
    });

    // Emitted once, when Electron has finished initializing.
    //
    // Note that some Electron APIs can only be used after this event occurs.
    void app.whenReady().then(() => {
        attachProcessHandlers();

        void (async () => {
            if (isDev) await waitForRendererDevServer();

            // Create window and prepare for the renderer.
            mainWindow = createMainWindow();

            // Setup IPC and streams.
            const watcher = createWatcher(mainWindow);
            attachIPCHandlers();
            attachMainWindowIPCHandlers(mainWindow);
            attachFSWatchIPCHandlers(watcher);
            attachLogoutIPCHandler(watcher);
            registerStreamProtocol(mainWindow);

            // Configure the renderer's environment.
            const webContents = mainWindow.webContents;
            setDownloadPath(webContents);
            allowExternalLinks(webContents);
            handleBackOnStripeCheckout(mainWindow);
            allowAllCORSOrigins(webContents);
            allowOpenStreetMapRequestIdentification(webContents);

            // Start loading the renderer.
            void mainWindow.loadURL(rendererURL);

            // Continue on with the rest of the startup sequence.
            Menu.setApplicationMenu(createApplicationMenu(mainWindow));
            setupTrayItem(mainWindow);
            setupAutoUpdater(mainWindow);
        })();
    });

    // This is a macOS only event. Show our window when the user activates the
    // app, e.g. by clicking on its dock icon.
    app.on("activate", () => mainWindow?.show());

    app.on("before-quit", () => {
        if (mainWindow) saveWindowBounds(mainWindow);
        allowWindowClose();
    });

    // On macOS, this is how we get deeplinks. See: registerForEnteLinks
    app.on("open-url", (_, url) => handleOpenEnteURLEnsuringWindow(url));
};

/**
 * Log a standard startup banner.
 *
 * This helps us identify app starts and other environment details in the logs.
 */
const logStartupBanner = () => {
    const version = isDev ? "dev" : app.getVersion();
    log.info(`Starting ente-photos-desktop ${version}`);

    const platform = process.platform;
    const osRelease = os.release();
    const systemVersion = process.getSystemVersion();
    log.info("Running on", { platform, osRelease, systemVersion });
};

/**
 * next-electron-server allows up to directly use the output of `next build` in
 * production mode and `next dev` in development mode, whilst keeping the rest
 * of our code the same.
 *
 * It uses protocol handlers to serve files from the "ente://" protocol.
 *
 * - In development this is proxied to http://localhost:3008
 * - In production it serves files from the `/out` directory
 *
 * For more details, see this comparison:
 * https://github.com/HaNdTriX/next-electron-server/issues/5
 */
const setupRendererServer = () => serveNextAt(rendererURL, { port: 3008 });

/**
 * Register privileged schemes.
 *
 * We have two privileged schemes:
 *
 * 1. "ente", used for serving our web app (@see {@link setupRendererServer}).
 *
 * 2. "stream", used for streaming IPC (@see {@link registerStreamProtocol}).
 *
 * Both of these need some privileges, however, the documentation for Electron's
 * [registerSchemesAsPrivileged](https://www.electronjs.org/docs/latest/api/protocol)
 * says:
 *
 * > This method ... can be called only once.
 *
 * The library we use for the "ente" scheme, next-electron-server, already calls
 * it once when we invoke {@link setupRendererServer}.
 *
 * In practice calling it multiple times just causes the values to be
 * overwritten, and the last call wins. So we don't need to modify
 * next-electron-server to prevent it from calling registerSchemesAsPrivileged.
 * Instead, we (a) repeat what next-electron-server had done here, and (b)
 * ensure that we're called after {@link setupRendererServer}.
 */
const registerPrivilegedSchemes = () => {
    protocol.registerSchemesAsPrivileged([
        {
            // Taken verbatim from next-electron-server's code (index.js)
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

/**
 * Register a handler for deeplinks, for the "ente://" protocol.
 *
 * See: [Note: Passkey verification in the desktop app].
 *
 * Implementation notes:
 * - https://www.electronjs.org/docs/latest/tutorial/launch-app-from-url-in-another-app
 * - This works only when the app is packaged.
 * - On Windows and Linux, we get the deeplink in the "second-instance" event.
 * - On macOS, we get the deeplink in the "open-url" event.
 */
const registerForEnteLinks = () => app.setAsDefaultProtocolClient("ente");

/** Sibling of {@link registerForEnteLinks}. */
const handleEnteLinks = (mainWindow: BrowserWindow, url: string) => {
    // [Note: Using deeplinks to navigate in desktop app]
    //
    // Both
    //
    // - our deeplink protocol, and
    // - the protocol we're using to serve/ our bundled web app
    //
    // use the same scheme ("ente://"), so the URL can directly be forwarded.
    mainWindow.webContents.send("openEnteURL", url);
};

/** Attach handlers to the (node) process. */
const attachProcessHandlers = () => {
    // Gracefully quit the app if we get a SIGINT.
    //
    // This is meant to allow graceful shutdowns during development, when the
    // app is launched using `npm run dev`. In such cases, pressing CTRL-C sends a
    // SIGINT to the process. The default handling of SIGINT is not graceful
    // enough (apparently), since I can observe that sometimes recent writes to
    // local storage are lost. This has also been reported by other people:
    // https://github.com/electron/electron/issues/22048
    //
    // Hopefully handling SIGINT prevents that issue. But beyond that, it allows
    // us to also write out `userPreferences.json` (as would happen during a
    // normal quit sequence), so this is an improvement either ways.
    process.on("SIGINT", () => app.quit());
};

/**
 * Wait for the renderer process' dev server to be ready.
 *
 * After creating the main window, we load the web app into it using `loadURL`.
 * In production, these are served directly from the SSR-ed static files bundled
 * with the app, and so can be served instantly. However, during development, we
 * start a dev server for serving the HMR-ed files.
 *
 * This Next.js HMR server takes time to startup and is sometimes not ready to
 * handle incoming requests when the main window tries to load it. In such
 * cases, Electron just hangs with this:
 *
 *     [main] Error: net::ERR_CONNECTION_REFUSED
 *      [main]     at SimpleURLLoaderWrapper.<anonymous> (node:electron/js2c/browser_init:2:114482)
 *      [main]     at SimpleURLLoaderWrapper.emit (node:events:519:28)
 *
 * As a workaround, we wait for 1 second.
 *
 * I'd also tried fancier workaround - polling the URL - but waits until the dev
 * server has the response ready, delaying everything many seconds (we just want
 * to see if the dev server can accept connections). The 1 second delay seems to
 * get the job done for now.
 *
 * This workaround can likely be removed when we migrate to Vite.
 */
const waitForRendererDevServer = () => wait(1000);

/**
 * Create an return the {@link BrowserWindow} that will form our app's UI.
 *
 * This window will show the HTML served from {@link rendererURL}.
 */
const createMainWindow = () => {
    const icon = nativeImage.createFromPath(
        path.join(isDev ? "build" : process.resourcesPath, "window-icon.png"),
    );
    const bounds = windowBounds();

    // Create the main window. This'll show our web content.
    const window = new BrowserWindow({
        webPreferences: {
            preload: path.join(__dirname, "preload.js"),
            sandbox: true,
        },
        icon,
        // Set the window's position and size (if we have one saved).
        ...(bounds ?? {}),
        // Enforce a minimum size
        ...minimumWindowSize(),
        // [Note: Customize the desktop title bar]
        //
        // 1. Remove the default title bar.
        // 2. Reintroduce the title bar controls.
        // 3. Show a custom title bar in the renderer.
        //
        // For step 3, we use `app-region: drag` to allow dragging the window by
        // the title bar, and use the Window Controls Overlay CSS environment
        // variables to determine its dimensions. Note that these overlay CSS
        // environment vars are only available when titleBarOverlay is true, so
        // unlike the tutorial which enables it only for Windows and Linux, we
        // do it (Step 2) unconditionally (i.e., on macOS too).
        //
        // https://www.electronjs.org/docs/latest/tutorial/custom-title-bar#create-a-custom-title-bar
        //
        // Note that by default on Windows, the color of the WCO title bar
        // overlay (three buttons - minimize, maximize, close - on the top
        // right) is static, and unlike Linux, doesn't adapt to the theme /
        // content. Explicitly choosing a dark background, while it won't work
        // always (if the user's theme is light), is better than picking a light
        // background since the main image viewer is always dark.
        titleBarStyle: "hidden",
        titleBarOverlay:
            process.platform == "win32"
                ? { color: "black", symbolColor: "#cdcdcd" }
                : true,
        // The color to show in the window until the web content gets loaded.
        // https://www.electronjs.org/docs/latest/api/browser-window#setting-the-backgroundcolor-property
        //
        // To avoid a flash, we want to use the same background color as the
        // theme of their choice. Unless the user has modified their preference
        // to not follow the system, we can deduce it from the current OS theme.
        //
        // See: https://www.electronjs.org/docs/latest/tutorial/dark-mode
        backgroundColor: nativeTheme.shouldUseDarkColors ? "black" : "white",
        // We'll show it conditionally depending on `wasAutoLaunched` later.
        show: false,
    });

    const wasAutoLaunched = autoLauncher.wasAutoLaunched();
    if (wasAutoLaunched) {
        // Don't automatically show the app's window if we were auto-launched.
        // On macOS, also hide the dock icon.
        app.dock?.hide();
    } else {
        // Show our window otherwise, maximizing it if we're not asked to set it
        // to a specific size.
        bounds ? window.show() : window.maximize();
    }

    // Open the DevTools automatically when running in dev mode
    if (isDev) window.webContents.openDevTools();

    window.webContents.on("render-process-gone", (_, details) => {
        log.error(`render-process-gone: ${details.reason}`);
        window.webContents.reload();
    });

    // "The unresponsive event is fired when Chromium detects that your
    //  webContents is not responding to input messages for > 30 seconds."
    window.webContents.on("unresponsive", () => {
        // There is a known case when this can happen: When the user to select a
        // folder to upload (Upload > Folder), the browser callback to us takes
        // some time. When trying to upload very large folders on slower Windows
        // machines, this can take up to 30 seconds.
        log.warn("MainWindow's webContents are unresponsive");
    });

    window.on("close", (event) => {
        if (!shouldAllowWindowClose) {
            event.preventDefault();
            // Only hide the dock icon when we are intercepting an explicit
            // close action. On macOS, the generic "hide" event is also emitted
            // for occlusion changes, so reacting there causes the dock icon to
            // disappear when the window is fully covered by another window.
            if (shouldHideDockIcon()) {
                app.dock?.hide();
            }
            window.hide();
        }
        return false;
    });

    window.on("show", () => void app.dock?.show());

    // Let ipcRenderer know when mainWindow is in the foreground so that it can
    // in turn inform the renderer process.
    window.on("focus", () => window.webContents.send("mainWindowFocus"));
    window.on("blur", () => window.webContents.send("mainWindowBlur"));

    return window;
};

/**
 * The position and size to use when showing the main window.
 *
 * The return value is `undefined` if the app's window was maximized the last
 * time around, and so if we should restore it to the maximized state.
 *
 * Otherwise it returns the position and size of the window the last time the
 * app quit.
 *
 * If there is no such saved value (or if it is the first time the user is
 * running the app), return a default size.
 */
const windowBounds = () => {
    if (userPreferences.get("isWindowMaximized")) return undefined;

    const bounds = userPreferences.get("windowBounds");
    if (bounds) return bounds;

    // Default size. Picked arbitrarily as something that should look good on
    // first launch. We don't provide a position to let Electron center the app.
    return { width: 1170, height: 710 };
};

/**
 * If for some reason {@link windowBounds} is outside the screen's bounds (e.g.
 * if the user's screen resolution has changed), then the previously saved
 * bounds might not be appropriate.
 *
 * Luckily, if we try to set an x/y position that is outside the screen's
 * bounds, then Electron automatically clamps x + width and y + height to lie
 * within the screen's available space, and we do not need to tackle such out of
 * bounds cases specifically.
 *
 * However there is no minimum window size the Electron enforces by default. As
 * a safety valve, provide an (arbitrary) minimum size so that the user can
 * resize it back to sanity if something I cannot currently anticipate happens.
 */
const minimumWindowSize = () => ({ minWidth: 200, minHeight: 200 });

/**
 * Sibling of {@link windowBounds}, see that function's documentation for more
 * details.
 */
const saveWindowBounds = (window: BrowserWindow) => {
    if (window.isMaximized()) {
        userPreferences.set("isWindowMaximized", true);
        userPreferences.delete("windowBounds");
    } else {
        userPreferences.delete("isWindowMaximized");
        userPreferences.set("windowBounds", window.getBounds());
    }
};

/**
 * Automatically set the save path for user initiated downloads to the system's
 * "downloads" directory instead of asking the user to select a save location.
 */
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

/**
 * Allow opening external links, e.g. when the user clicks on the "Feature
 * requests" button in the sidebar (to open our GitHub repository), or when they
 * click the "Support" button to send an email to support.
 *
 * Security: Only allow http/https/mailto schemes to be opened externally.
 * Disallow other protocols (e.g. custom OS handlers) to avoid potential RCE
 * vectors on some platforms when delegating to the OS via shell.openExternal.
 *
 * @param webContents The renderer to configure.
 */
const allowExternalLinks = (webContents: WebContents) =>
    // By default, if the user were open a link, say
    // https://github.com/ente/ente/discussions, then it would open a _new_
    // BrowserWindow within our app.
    //
    // This is not the behaviour we want; what we want is to ask the system to
    // handle the link (e.g. open the URL in the default browser, or if it is a
    // mailto: link, then open the user's mail client).
    //
    // Returning `action` "deny" accomplishes this.
    webContents.setWindowOpenHandler(({ url }) => {
        if (!url.startsWith(rendererURL)) {
            // Only allow http/https/mailto external links for safety.
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
                // This does not work in Ubuntu currently: mailto links seem to just
                // get ignored, and HTTP links open in the text editor instead of in
                // the browser.
                // https://github.com/electron/electron/issues/31485
                void shell.openExternal(url);
            } else {
                log.warn(`Blocked external open for disallowed scheme: ${url}`);
            }
            return { action: "deny" };
        } else {
            return { action: "allow" };
        }
    });

/**
 * Handle back button presses on the Stripe checkout page.
 *
 * For payments, we show the Stripe checkout page to the user in the app's
 * window. On this page there is a back button that allows the user to get back
 * to the app's contents. Since we're not showing the browser controls, this is
 * the only way to get back to the app.
 *
 * If the user enters something in the text fields on this page (e.g. if they
 * start entering their credit card number), and then press back, then the
 * browser shows the user a dialog asking them to confirm if they want to
 * discard their unsaved changes. However, when running in the context of an
 * Electron app, this dialog is not shown, and instead the app just gets stuck
 * (the back button stops working, and quitting the app also doesn't work since
 * there is an invisible modal dialog).
 *
 * So we instead intercept these back button presses, and show the same dialog
 * that the browser would've shown.
 */
const handleBackOnStripeCheckout = (window: BrowserWindow) =>
    window.webContents.on("will-prevent-unload", (event) => {
        const url = new URL(window.webContents.getURL());
        // Only intercept on Stripe checkout pages.
        if (url.host != "checkout.stripe.com") return;

        // The dialog copy is similar to what Chrome would've shown.
        // https://www.electronjs.org/docs/latest/api/web-contents#event-will-prevent-unload
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

/**
 * Allow uploads to arbitrary S3 buckets.
 *
 * The embedded web app within in the desktop app is served over the ente://
 * protocol. When pages in that web app make requests, their originate from this
 * "ente://app" origin, which thus serves as the value for the
 * "Access-Control-Allow-Origin" header in the CORS preflight requests.
 *
 * Some S3 providers (B2 is the motivating example for this workaround) do not
 * allow whitelisting custom URI schemes. That is, even if we set
 * "`allowedOrigin: ["*"]` in our B2 bucket CORS configuration, when the web
 * code makes a CORS request with ACAO "ente://app", it gets back
 * "Access-Control-Allow-Origin" set to `null` in the response, and thus the
 * request fails (since it does not match the origin we sent).
 *
 * This is not an issue for production apps since they fetches or uploads via a
 * worker instead of directly touching an S3 provider.
 *
 * This is not also an issue for fetches in the self hosted apps since those
 * involve a redirection, and during a redirection Chromium sets the ACAO in the
 * request to `null` (this is the correct behaviour as per the spec, for more
 * details See: [Note: Passing credentials for self-hosted file fetches]).
 *
 * But this is an issue for uploads in the self hosted apps (or when we
 * ourselves are trying to test things by with an arbitrary S3 bucket without
 * going via a worker). During upload, there is no redirection, so the request
 * ACAO is "ente://app" but the response ACAO is `null` which don't match,
 * causing the request to fail.
 *
 * As a workaround, we intercept the ACAO header and set it to `*`.
 *
 * However, an unconditional interception causes problems with requests that use
 * credentials, since "*" is not a valid value in such cases. One such example
 * is the HCaptcha requests made by Stripe when we initiate a payment within the
 * desktop app:
 *
 * > Access to XMLHttpRequest at 'https://api2.hcaptcha.com/getcaptcha/xxx' from
 * > origin 'https://newassets.hcaptcha.com' has been blocked by CORS policy:
 * > The value of the 'Access-Control-Allow-Origin' header in the response must
 * > not be the wildcard '*' when the request's credentials mode is 'include'.
 * > The credentials mode of requests initiated by the XMLHttpRequest is
 * > controlled by the withCredentials attribute.
 *
 * So we only do this workaround if there was either no ACAO specified in the
 * response, or if the ACAO in the response was "null" (the string serialization
 * of `null`).
 */
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

/**
 * OSM services expect requests to identify the originating app. Our desktop
 * renderer is served from the custom "ente://app" origin, so requests from the
 * Electron session do not naturally carry an app-specific browser identity.
 *
 * Prefix OSM requests with a truthful desktop app User-Agent token instead of
 * forging a web Referer. This applies to both map tiles and Nominatim lookups.
 */
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

/**
 * Add an icon for our app in the system tray.
 *
 * For example, these are the small icons that appear on the top right of the
 * screen in the main menu bar on macOS.
 */
const setupTrayItem = (mainWindow: BrowserWindow) => {
    // There are a total of 6 files corresponding to this tray icon.
    //
    // On macOS, use template images (filename needs to end with "Template.ext")
    // https://www.electronjs.org/docs/latest/api/native-image#template-image-macos
    //
    // And for each (template or otherwise), there are 3 "retina" variants
    // https://www.electronjs.org/docs/latest/api/native-image#high-resolution-image
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

// Go for it.
main();
