import {
    HTTPError,
    isHTTPErrorWithStatus,
    isMuseumHTTPError,
} from "ente-base/http";

export interface AlbumImportIssue {
    message: string;
    canRetry: boolean;
    retryAt?: number;
}

export class AlbumImportBlockedError extends Error {}

export async function albumImportIssue(
    error: unknown,
): Promise<AlbumImportIssue> {
    if (error instanceof AlbumImportBlockedError)
        return { message: error.message, canRetry: false };
    if (await isMuseumHTTPError(error, 403, "LINK_DEVICE_LIMIT_EXCEEDED"))
        return {
            message:
                "This album has reached its device limit. Increase the limit in the album's sharing settings, then try again.",
            canRetry: true,
        };
    if (await isMuseumHTTPError(error, 410, "LINK_EXPIRED"))
        return {
            message:
                "This album link has expired. Update its expiry in the album's sharing settings, then try again.",
            canRetry: true,
        };
    if (await isMuseumHTTPError(error, 410, "LINK_UNAVAILABLE"))
        return {
            message:
                "This album is currently unavailable. Please try again later or use a different album.",
            canRetry: true,
        };
    if (
        error instanceof HTTPError &&
        error.res.status === 401 &&
        !error.res.url.endsWith("/public-collection/info")
    )
        return {
            message: "Couldn't access this album. Please try again.",
            canRetry: true,
        };
    if (isHTTPErrorWithStatus(error, 401) || isHTTPErrorWithStatus(error, 410))
        return {
            message:
                "This album link is no longer available. Use a working link to import the album.",
            canRetry: false,
        };
    if (error instanceof HTTPError && error.res.status === 429) {
        const retryAfter = error.res.headers.get("Retry-After");
        const now = Date.now();
        const retryAt = retryAfter
            ? /^\d+$/.test(retryAfter)
                ? now + Number(retryAfter) * 1000
                : Date.parse(retryAfter)
            : NaN;
        return {
            message:
                "There have been too many attempts to open this album. Please wait a little and try again.",
            canRetry: true,
            retryAt: Number.isFinite(retryAt)
                ? Math.max(now, retryAt)
                : now + 30000,
        };
    }
    return {
        message:
            error instanceof Error &&
            !(error instanceof HTTPError) &&
            !(error instanceof TypeError)
                ? error.message
                : "Couldn't import this album right now. Please try again.",
        canRetry: true,
    };
}
