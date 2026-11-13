import {
    buildEnvAppName,
    buildEnvDesktopAppVersion,
    buildEnvIsDesktop,
} from "./env";

export const appNames = [
    "accounts",
    "albums",
    "auth",
    "cast",
    "embed",
    "share",
    "photos",
    "photobook",
    "ensu",
    "locker",
    "legacy",
    "space",
] as const;

export type AppName = (typeof appNames)[number];

// Build-time injection makes this available inside workers.
// The cast is unchecked; each app must validate the value during startup.
export const appName: AppName = buildEnvAppName as AppName;

// Unlike globalThis.electron, this also works inside workers.
// A browser pointed at the desktop dev server can produce a false positive.
export const isDesktop = buildEnvIsDesktop;

export const desktopAppVersion = buildEnvDesktopAppVersion;

export const staticAppTitle = {
    accounts: "Ente Accounts",
    albums: "Ente Photos",
    auth: "Ente Auth",
    cast: "Ente Photos",
    embed: "Ente Photos",
    share: "Ente Locker",
    photos: "Ente Photos",
    photobook: "Ente Photobook",
    ensu: "Ensu",
    locker: "Ente Locker",
    legacy: "Ente Legacy Kit",
    space: "Ente Space",
}[appName];

// Sent as the X-Client-Package header.
export const clientPackageName = (() => {
    if (isDesktop) {
        if (appName === "photos") return "io.ente.photos.desktop";
        if (appName === "ensu") return "io.ente.ensu.desktop";
        throw new Error(`Unsupported desktop appName ${appName}`);
    }
    return {
        accounts: "io.ente.accounts.web",
        albums: "io.ente.albums.web",
        auth: "io.ente.auth.web",
        cast: "io.ente.cast.web",
        embed: "io.ente.photos.web", // Use photos package name for embed app
        share: "io.ente.share.web",
        photos: "io.ente.photos.web",
        photobook: "io.ente.photobook.web",
        ensu: "io.ente.ensu",
        locker: "io.ente.locker.web",
        legacy: "io.ente.legacy.web",
        space: "io.ente.space.web",
    }[appName];
})();

export const clientIdentifier = (() => {
    if (isDesktop) {
        if (!desktopAppVersion)
            throw new Error(`desktopAppVersion is not defined`);

        if (appName === "photos") {
            return `io.ente.photos.desktop/${desktopAppVersion}`;
        }
        if (appName === "ensu") {
            return `io.ente.ensu.desktop/${desktopAppVersion}`;
        }

        throw new Error(`Unsupported desktop appName ${appName}`);
    }
    return clientPackageName;
})();
