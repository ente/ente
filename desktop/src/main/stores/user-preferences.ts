import Store, { Schema } from "electron-store";
import type { SavedCloseAction, ThemeMode } from "../../types/ipc";

interface UserPreferences {
    hideDockIcon?: boolean;
    skipAppVersion?: string;
    muteUpdateNotificationVersion?: string;
    lastShownChangelogVersion?: number;
    windowBounds?: { x: number; y: number; width: number; height: number };
    isWindowMaximized?: boolean;
    themeMode?: ThemeMode;
    closeAction?: SavedCloseAction;
}

const userPreferencesSchema: Schema<UserPreferences> = {
    hideDockIcon: { type: "boolean" },
    skipAppVersion: { type: "string" },
    muteUpdateNotificationVersion: { type: "string" },
    lastShownChangelogVersion: { type: "number" },
    windowBounds: {
        properties: {
            x: { type: "number" },
            y: { type: "number" },
            width: { type: "number" },
            height: { type: "number" },
        },
    },
    isWindowMaximized: { type: "boolean" },
    themeMode: { type: "string", enum: ["light", "dark", "system"] },
    closeAction: { type: "string", enum: ["quit", "background"] },
};

export const userPreferences = new Store({
    name: "userPreferences",
    schema: userPreferencesSchema,
});
