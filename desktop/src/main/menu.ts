import {
    app,
    BrowserWindow,
    Menu,
    MenuItemConstructorOptions,
    shell,
} from "electron";
import { allowWindowClose } from "../main";
import { forceCheckForAppUpdates } from "./services/app-update";
import { setShouldHideDockIcon, shouldHideDockIcon } from "./services/store";

export const createApplicationMenu = (mainWindow: BrowserWindow) => {
    let hideDockIcon = shouldHideDockIcon();

    const macOSOnly = (options: MenuItemConstructorOptions[]) =>
        process.platform == "darwin" ? options : [];

    const handleCheckForUpdates = () => forceCheckForAppUpdates(mainWindow);

    const toggleHideDockIcon = () => {
        setShouldHideDockIcon(!hideDockIcon);
        hideDockIcon = !hideDockIcon;
    };

    const handleHelp = () =>
        void shell.openExternal("https://ente.com/help/photos/");

    return Menu.buildFromTemplate([
        {
            label: "Ente Photos",
            submenu: [
                ...macOSOnly([{ label: "About Ente", role: "about" }]),
                { type: "separator" },
                { label: "Check for Updates...", click: handleCheckForUpdates },
                { type: "separator" },

                ...macOSOnly([
                    {
                        label: "Preferences",
                        submenu: [
                            {
                                label: "Hide Dock Icon",
                                type: "checkbox",
                                checked: hideDockIcon,
                                click: toggleHideDockIcon,
                            },
                        ],
                    },
                ]),

                { type: "separator" },
                ...macOSOnly([
                    { label: "Hide Ente", role: "hide" },
                    { label: "Hide Others", role: "hideOthers" },
                    { type: "separator" },
                ]),
                { label: "Quit", role: "quit" },
            ],
        },
        {
            label: "Edit",
            submenu: [
                { label: "Undo", role: "undo" },
                { label: "Redo", role: "redo" },
                { type: "separator" },
                { label: "Cut", role: "cut" },
                { label: "Copy", role: "copy" },
                { label: "Paste", role: "paste" },
                { label: "Select All", role: "selectAll" },
                ...macOSOnly([
                    { type: "separator" },
                    {
                        label: "Speech",
                        submenu: [
                            { role: "startSpeaking", label: "Start Speaking" },
                            { role: "stopSpeaking", label: "Stop Speaking" },
                        ],
                    },
                ]),
            ],
        },
        {
            label: "View",
            submenu: [
                { label: "Reload", role: "reload" },
                { label: "Toggle Dev Tools", role: "toggleDevTools" },
                { type: "separator" },
                { label: "Toggle Full Screen", role: "togglefullscreen" },
            ],
        },
        {
            label: "Window",
            submenu: [
                { label: "Minimize", role: "minimize" },
                { label: "Zoom", role: "zoom" },
                { label: "Close", role: "close" },
                ...macOSOnly([
                    { type: "separator" },
                    { label: "Bring All to Front", role: "front" },
                    { type: "separator" },
                    { label: "Ente Photos", role: "window" },
                ]),
            ],
        },
        { label: "Help", submenu: [{ label: "Ente Help", click: handleHelp }] },
    ]);
};

export const createTrayContextMenu = (mainWindow: BrowserWindow) => {
    const handleOpen = () => {
        mainWindow.show();
    };

    const handleClose = () => {
        allowWindowClose();
        app.quit();
    };

    return Menu.buildFromTemplate([
        { label: "Open Ente", click: handleOpen },
        { label: "Quit Ente", click: handleClose },
    ]);
};
