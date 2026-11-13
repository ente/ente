export const clientPackageName = "io.ente.photos.desktop";

// Utility processes cannot import Electron's app module, so callers supply the version.
export const publicRequestHeaders = (desktopAppVersion: string) => ({
    "X-Client-Package": clientPackageName,
    "X-Client-Version": desktopAppVersion,
});

export const authenticatedRequestHeaders = (
    desktopAppVersion: string,
    authToken: string,
) => ({
    ...publicRequestHeaders(desktopAppVersion),
    "X-Auth-Token": authToken,
});
