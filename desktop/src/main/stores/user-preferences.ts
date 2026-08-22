import Store, { Schema } from "electron-store";

interface UserPreferences {
    hideDockIcon?: boolean;
    skipAppVersion?: string;
    muteUpdateNotificationVersion?: string;
    lastShownChangelogVersion?: number;
    windowBounds?: { x: number; y: number; width: number; height: number };
    isWindowMaximized?: boolean;
    isDarkMode?: boolean;
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
    isDarkMode: { type: "boolean" },
};

export const userPreferences = new Store({
    name: "userPreferences",
    schema: userPreferencesSchema,
});
