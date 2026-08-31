import type { NotificationAttributes } from "ente-base/components/Notification";
import type { SingleInputFormProps } from "ente-base/components/SingleInputForm";
import {
    HTTPError,
    isHTTP401Error,
    isHTTPErrorWithStatus,
} from "ente-base/http";
import { apiOrigin } from "ente-base/origins";
import { extractCollectionKeyFromShareURL } from "ente-gallery/services/share";
import type { PublicURL } from "ente-media/collection";
import { useRouter } from "next/router";
import { useCallback, useEffect, useRef, useState } from "react";
import {
    downloadPublicCollectionFile,
    fetchPublicCollectionShare,
    fetchPublicCollectionShareMetadata,
    type PublicCollectionShareInfo,
    type SharedCollectionItemInfo,
    verifyPublicCollectionPassword,
} from "../services/collection-share";

const extractCollectionTokenFromPath = (pathname: string): string | null => {
    const match = /^\/c\/([^/]+)\/?$/.exec(pathname);
    return match?.[1] ?? null;
};

const extractCollectionTokenFromURL = (url: URL): string | null =>
    extractCollectionTokenFromPath(url.pathname);

interface UseCollectionShareResult {
    loading: boolean;
    requiresPassword: boolean;
    downloadingItemID: number | null;
    downloadProgress: number | null;
    errorTitle: string | null;
    error: string | null;
    collectionInfo: PublicCollectionShareInfo | null;
    selectedItem: SharedCollectionItemInfo | null;
    notificationAttributes: NotificationAttributes | undefined;
    handleItemClick: (item: SharedCollectionItemInfo) => void;
    handleCloseItem: () => void;
    handleDownload: () => Promise<void>;
    handleSubmitPassword: SingleInputFormProps["onSubmit"];
    handleCopyContent: (content: string) => Promise<void>;
    setNotificationAttributes: (
        attributes: NotificationAttributes | undefined,
    ) => void;
}

interface CollectionShareLoadError {
    title: string;
    message: string;
}

const readLocalStorageItem = (key: string): string | null => {
    try {
        return window.localStorage.getItem(key);
    } catch {
        return null;
    }
};

const writeLocalStorageItem = (key: string, value: string) => {
    try {
        window.localStorage.setItem(key, value);
    } catch {
        // Ignore storage failures and continue with in-memory state.
    }
};

const removeLocalStorageItem = (key: string) => {
    try {
        window.localStorage.removeItem(key);
    } catch {
        // Ignore storage failures and continue with in-memory state.
    }
};

const accessTokenJWTStorageKey = (accessToken: string) =>
    `share-collection-access-token-jwt:${accessToken}`;

const savedAccessTokenJWT = (accessToken: string): string | null =>
    readLocalStorageItem(accessTokenJWTStorageKey(accessToken));

const saveAccessTokenJWT = (accessToken: string, accessTokenJWT: string) => {
    writeLocalStorageItem(
        accessTokenJWTStorageKey(accessToken),
        accessTokenJWT,
    );
};

const removeAccessTokenJWT = (accessToken: string) =>
    removeLocalStorageItem(accessTokenJWTStorageKey(accessToken));

const linkDeviceTokenStorageKey = (apiOrigin: string, accessToken: string) =>
    `share-collection-link-device-token:${apiOrigin}:${accessToken}`;

const savedLinkDeviceToken = (apiOrigin: string, accessToken: string) =>
    readLocalStorageItem(linkDeviceTokenStorageKey(apiOrigin, accessToken));

const saveLinkDeviceToken = (
    apiOrigin: string,
    accessToken: string,
    linkDeviceToken: string,
) => {
    writeLocalStorageItem(
        linkDeviceTokenStorageKey(apiOrigin, accessToken),
        linkDeviceToken,
    );
};

const collectionShareLoadError = async (
    err: unknown,
): Promise<CollectionShareLoadError> => {
    if (err instanceof HTTPError && err.res.status === 410) {
        try {
            const payload = (await err.res.clone().json()) as {
                error?: string;
            };
            if (payload.error === "expired token") {
                return {
                    title: "Link expired",
                    message:
                        "This link has either expired or has been disabled.",
                };
            }
        } catch {
            // Ignore payload parse failures and use the generic gone-state copy.
        }

        return {
            title: "Link expired",
            message: "This link has either expired or has been disabled.",
        };
    }

    if (isHTTPErrorWithStatus(err, 429)) {
        return {
            title: "Too many viewers",
            message:
                "This link has reached its device limit. Ask the owner to increase the limit or try again later.",
        };
    }

    if (
        isHTTP401Error(err) ||
        isHTTPErrorWithStatus(err, 403) ||
        isHTTPErrorWithStatus(err, 404)
    ) {
        return {
            title: "Unable to open this collection",
            message:
                "This collection link is no longer available. It may have been removed or expired.",
        };
    }

    return {
        title: "Unable to open this collection",
        message:
            "Unable to load this collection right now. Please try again later.",
    };
};

const ITEM_BACK_STATE_KEY = "__enteCollectionShareItemBack";
const RESUME_REVALIDATE_AFTER_MS = 30_000;

const addItemBackStateMarker = (state: unknown, marker: string) =>
    state && typeof state == "object"
        ? {
              ...(state as Record<string, unknown>),
              [ITEM_BACK_STATE_KEY]: marker,
          }
        : { [ITEM_BACK_STATE_KEY]: marker };

const hasItemBackStateMarker = (state: unknown, marker: string) =>
    !!state &&
    typeof state == "object" &&
    (state as Record<string, unknown>)[ITEM_BACK_STATE_KEY] == marker;

const getItemBackStateMarker = (state: unknown) =>
    state && typeof state == "object"
        ? (state as Record<string, unknown>)[ITEM_BACK_STATE_KEY]
        : undefined;

const shouldPreserveLoadedStateOnSilentRefreshError = (err: unknown) => {
    if (!(err instanceof HTTPError)) {
        return true;
    }

    return err.res.status >= 500;
};

export const useCollectionShare = (): UseCollectionShareResult => {
    const router = useRouter();
    const initialLoadStartedRef = useRef(false);
    const isRevalidatingRef = useRef(false);
    const lastResumeRevalidateAtRef = useRef(0);
    const browserBackStateRef = useRef<string | undefined>(undefined);
    const [loading, setLoading] = useState(true);
    const [downloadingItemID, setDownloadingItemID] = useState<number | null>(
        null,
    );
    const [downloadProgress, setDownloadProgress] = useState<number | null>(
        null,
    );
    const [errorTitle, setErrorTitle] = useState<string | null>(null);
    const [error, setError] = useState<string | null>(null);
    const [collectionInfo, setCollectionInfo] =
        useState<PublicCollectionShareInfo | null>(null);
    const [selectedItem, setSelectedItem] =
        useState<SharedCollectionItemInfo | null>(null);
    const [accessToken, setAccessToken] = useState<string | null>(null);
    const [accessTokenJWT, setAccessTokenJWT] = useState<string | null>(null);
    const [collectionKey, setCollectionKey] = useState<string | null>(null);
    const [passwordProtectedPublicURL, setPasswordProtectedPublicURL] =
        useState<PublicURL | null>(null);
    const [notificationAttributes, setNotificationAttributes] =
        useState<NotificationAttributes>();
    const requiresPassword = !!passwordProtectedPublicURL && !accessTokenJWT;
    const clearLoadedState = useCallback(() => {
        setCollectionInfo(null);
        setSelectedItem(null);
        setPasswordProtectedPublicURL(null);
    }, []);
    const setInvalidLinkState = useCallback(() => {
        clearLoadedState();
        setErrorTitle("Invalid collection link");
        setError("This collection link is invalid.");
    }, [clearLoadedState]);

    const loadCollection = useCallback(
        async (
            opts?: Partial<{
                accessToken: string;
                collectionKey: string;
                accessTokenJWT: string;
                silent: boolean;
            }>,
        ) => {
            try {
                if (!opts?.silent) {
                    setLoading(true);
                }
                setError(null);
                setErrorTitle(null);
                setPasswordProtectedPublicURL(null);

                const url = new URL(window.location.href);
                const token =
                    opts?.accessToken ?? extractCollectionTokenFromURL(url);
                if (!token) {
                    setInvalidLinkState();
                    return;
                }

                let resolvedCollectionKey: string | undefined;
                try {
                    resolvedCollectionKey =
                        opts?.collectionKey ??
                        (await extractCollectionKeyFromShareURL(url));
                } catch {
                    setInvalidLinkState();
                    return;
                }
                if (!resolvedCollectionKey) {
                    setInvalidLinkState();
                    return;
                }

                const storedAccessTokenJWT = savedAccessTokenJWT(token);
                const currentAPIOrigin = await apiOrigin();
                const storedLinkDeviceToken = savedLinkDeviceToken(
                    currentAPIOrigin,
                    token,
                );
                const resolvedAccessTokenJWT =
                    opts?.accessTokenJWT ?? storedAccessTokenJWT ?? undefined;
                const resolvedLinkDeviceToken =
                    storedLinkDeviceToken ?? undefined;

                setAccessToken(token);
                setCollectionKey(resolvedCollectionKey);
                setAccessTokenJWT(resolvedAccessTokenJWT ?? null);

                const metadata = await fetchPublicCollectionShareMetadata(
                    {
                        accessToken: token,
                        accessTokenJWT: resolvedAccessTokenJWT,
                        linkDeviceToken: resolvedLinkDeviceToken,
                    },
                    resolvedCollectionKey,
                );
                if (metadata.linkDeviceToken) {
                    saveLinkDeviceToken(
                        currentAPIOrigin,
                        token,
                        metadata.linkDeviceToken,
                    );
                }
                if (!metadata.passwordEnabled && resolvedAccessTokenJWT) {
                    removeAccessTokenJWT(token);
                    setAccessTokenJWT(null);
                }

                const activeAccessTokenJWT = metadata.passwordEnabled
                    ? resolvedAccessTokenJWT
                    : undefined;

                if (metadata.passwordEnabled && !activeAccessTokenJWT) {
                    setPasswordProtectedPublicURL(metadata.publicURL ?? null);
                    setCollectionInfo(null);
                    setSelectedItem(null);
                    return;
                }

                let info: PublicCollectionShareInfo;
                try {
                    info = await fetchPublicCollectionShare(
                        {
                            accessToken: token,
                            accessTokenJWT: activeAccessTokenJWT,
                            linkDeviceToken:
                                metadata.linkDeviceToken ??
                                resolvedLinkDeviceToken,
                        },
                        metadata,
                    );
                } catch (err) {
                    if (activeAccessTokenJWT && isHTTP401Error(err)) {
                        removeAccessTokenJWT(token);
                        setAccessTokenJWT(null);
                        setPasswordProtectedPublicURL(
                            metadata.publicURL ?? null,
                        );
                        setCollectionInfo(null);
                        setSelectedItem(null);
                        return;
                    }
                    throw err;
                }

                setPasswordProtectedPublicURL(null);
                setCollectionInfo(info);
            } catch (err) {
                if (
                    opts?.silent &&
                    shouldPreserveLoadedStateOnSilentRefreshError(err)
                ) {
                    return;
                }

                clearLoadedState();
                const loadError = await collectionShareLoadError(err);
                setErrorTitle(loadError.title);
                setError(loadError.message);
            } finally {
                if (!opts?.silent) {
                    setLoading(false);
                }
            }
        },
        [clearLoadedState, setInvalidLinkState],
    );

    useEffect(() => {
        if (router.isReady && !initialLoadStartedRef.current) {
            initialLoadStartedRef.current = true;
            void loadCollection();
        }
    }, [router.isReady, loadCollection]);

    useEffect(() => {
        if (!router.isReady) {
            return;
        }

        const revalidate = () => {
            if (
                document.visibilityState === "hidden" ||
                isRevalidatingRef.current
            ) {
                return;
            }

            const now = Date.now();
            if (
                now - lastResumeRevalidateAtRef.current <
                RESUME_REVALIDATE_AFTER_MS
            ) {
                return;
            }

            lastResumeRevalidateAtRef.current = now;
            isRevalidatingRef.current = true;
            void loadCollection({ silent: true }).finally(() => {
                isRevalidatingRef.current = false;
            });
        };

        const onVisibilityChange = () => {
            if (document.visibilityState === "visible") {
                revalidate();
            }
        };

        window.addEventListener("focus", revalidate);
        window.addEventListener("pageshow", revalidate);
        document.addEventListener("visibilitychange", onVisibilityChange);

        return () => {
            window.removeEventListener("focus", revalidate);
            window.removeEventListener("pageshow", revalidate);
            document.removeEventListener(
                "visibilitychange",
                onVisibilityChange,
            );
        };
    }, [router.isReady, loadCollection]);

    useEffect(() => {
        if (!selectedItem) {
            return;
        }

        const currentState: unknown = window.history.state;
        const existingMarker = getItemBackStateMarker(currentState);
        const stateMarker =
            typeof existingMarker == "string" && existingMarker
                ? existingMarker
                : `${selectedItem.id}-${Date.now()}-${Math.random()
                      .toString(36)
                      .slice(2)}`;
        browserBackStateRef.current = stateMarker;

        if (!existingMarker) {
            const itemState = addItemBackStateMarker(currentState, stateMarker);
            try {
                window.history.pushState(itemState, "", window.location.href);
            } catch {
                browserBackStateRef.current = undefined;
                return;
            }
        }

        const onPopState = () => {
            if (browserBackStateRef.current != stateMarker) {
                return;
            }

            browserBackStateRef.current = undefined;
            setSelectedItem(null);
        };

        window.addEventListener("popstate", onPopState);
        return () => {
            window.removeEventListener("popstate", onPopState);
            if (browserBackStateRef.current != stateMarker) {
                return;
            }

            browserBackStateRef.current = undefined;

            const latestHistoryState: unknown = window.history.state;
            if (hasItemBackStateMarker(latestHistoryState, stateMarker)) {
                window.history.back();
            }
        };
    }, [selectedItem]);

    const handleCloseItem = () => {
        setSelectedItem(null);
    };

    const handleDownloadItem = async (item: SharedCollectionItemInfo) => {
        const { fileDecryptionHeader, fileKey } = item;

        if (
            downloadingItemID !== null ||
            !accessToken ||
            !fileKey ||
            !fileDecryptionHeader
        ) {
            return;
        }

        setDownloadingItemID(item.id);
        setDownloadProgress(null);
        try {
            await downloadPublicCollectionFile(
                { accessToken, accessTokenJWT: accessTokenJWT ?? undefined },
                item.id,
                fileKey,
                item.fileName,
                fileDecryptionHeader,
                ({ loaded, total }) => {
                    if (total && total > 0) {
                        setDownloadProgress(
                            Math.min(100, Math.round((loaded / total) * 100)),
                        );
                    }
                },
            );
        } catch (err) {
            if (accessTokenJWT && collectionKey && isHTTP401Error(err)) {
                removeAccessTokenJWT(accessToken);
                setAccessTokenJWT(null);
                setSelectedItem(null);
                await loadCollection({ accessToken, collectionKey });
                return;
            }
            setNotificationAttributes({
                color: "critical",
                title:
                    err instanceof Error
                        ? err.message
                        : "Failed to download file",
            });
        } finally {
            setDownloadingItemID(null);
            setDownloadProgress(null);
        }
    };

    const handleItemClick = (item: SharedCollectionItemInfo) => {
        if (downloadingItemID !== null) {
            return;
        }

        setSelectedItem(item);
    };

    const handleDownload = async () => {
        if (!selectedItem) {
            return;
        }
        await handleDownloadItem(selectedItem);
    };

    const handleCopyContent = async (content: string) => {
        try {
            await navigator.clipboard.writeText(content);
        } catch {
            setNotificationAttributes({
                color: "critical",
                title: "Failed to copy",
            });
        }
    };

    const handleSubmitPassword: SingleInputFormProps["onSubmit"] = async (
        password,
        setFieldError,
    ) => {
        if (!passwordProtectedPublicURL || !accessToken || !collectionKey) {
            return;
        }

        try {
            const jwtToken = await verifyPublicCollectionPassword(
                passwordProtectedPublicURL,
                password,
                accessToken,
            );
            setAccessTokenJWT(jwtToken);
            saveAccessTokenJWT(accessToken, jwtToken);
            await loadCollection({
                accessToken,
                collectionKey,
                accessTokenJWT: jwtToken,
            });
        } catch (err) {
            if (isHTTP401Error(err)) {
                setFieldError("Incorrect password");
                return;
            }
            throw err;
        }
    };

    return {
        loading,
        requiresPassword,
        downloadingItemID,
        downloadProgress,
        errorTitle,
        error,
        collectionInfo,
        selectedItem,
        notificationAttributes,
        handleItemClick,
        handleCloseItem,
        handleDownload,
        handleSubmitPassword,
        handleCopyContent,
        setNotificationAttributes,
    };
};
