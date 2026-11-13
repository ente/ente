import type { PublicAlbumsCredentials } from "ente-base/http";
import type { Collection } from "ente-media/collection";
import type { RefObject } from "react";

export interface JoinPublicAlbumRedirectProps {
    publicCollection?: Collection;
    accessToken?: string;
    collectionKey?: string;
    credentials?: RefObject<PublicAlbumsCredentials | undefined>;
}

const buildWebRedirectURL = (
    accessToken: string,
    collectionId: number,
    currentHash: string,
    jwtToken?: string,
): string => {
    const hashSuffix = jwtToken ? `&jwt=${encodeURIComponent(jwtToken)}` : "";
    return `https://photos.ente.com/?joinAlbum=${accessToken}&collectionId=${collectionId}#${currentHash}${hashSuffix}`;
};

const handleWebFallback = (
    accessToken: string,
    collectionId: number,
    currentHash: string,
    jwtToken?: string,
): void => {
    const redirectURL = buildWebRedirectURL(
        accessToken,
        collectionId,
        currentHash,
        jwtToken,
    );
    window.location.href = redirectURL;
};

const tryDeepLinkWithFallback = (
    deepLinkURL: string,
    fallbackFn: () => void | Promise<void>,
    timeoutMs = 2500,
): (() => void) => {
    let appOpened = false;

    const onVisibilityChange = () => {
        if (document.visibilityState === "hidden") {
            appOpened = true;
        }
    };

    const onPageHide = () => {
        appOpened = true;
    };

    document.addEventListener("visibilitychange", onVisibilityChange);
    window.addEventListener("pagehide", onPageHide);

    window.location.assign(deepLinkURL);

    const timeoutId = setTimeout(() => {
        if (!appOpened) {
            void fallbackFn();
        }
        cleanup();
    }, timeoutMs);

    const cleanup = () => {
        clearTimeout(timeoutId);
        document.removeEventListener("visibilitychange", onVisibilityChange);
        window.removeEventListener("pagehide", onPageHide);
    };

    return cleanup;
};

export const joinPublicAlbumViaRedirect = ({
    publicCollection,
    accessToken,
    collectionKey,
    credentials,
}: JoinPublicAlbumRedirectProps) => {
    if (!publicCollection || !accessToken || !collectionKey) {
        return;
    }

    const currentHash = window.location.hash.slice(1);
    const jwtToken = credentials?.current?.accessTokenJWT;
    const collectionId = publicCollection.id;

    const fallbackToWeb = () => {
        handleWebFallback(accessToken, collectionId, currentHash, jwtToken);
    };

    if (navigator.userAgent.includes("Android")) {
        // Older Android clients only recognize albums.ente.io in ente://
        // public-album join links. Newer ones also support albums.ente.com.
        const deepLinkURL = `ente://albums.ente.io/?action=join&t=${encodeURIComponent(accessToken)}#${currentHash}`;

        tryDeepLinkWithFallback(deepLinkURL, fallbackToWeb);
    } else {
        handleWebFallback(accessToken, collectionId, currentHash, jwtToken);
    }
};
