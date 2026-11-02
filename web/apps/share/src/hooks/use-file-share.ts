import { useNotification } from "ente-base/components/utils/hooks-app";
import { apiOrigin } from "ente-base/origins";
import { useRouter } from "next/router";
import { useEffect, useState } from "react";
import {
    decryptFileInfo,
    downloadFile,
    extractFileKeyFromURL,
    fetchFileInfo,
} from "../services/file-share";
import type { DecryptedFileInfo } from "../types/file-share";

const linkDeviceTokenStorageKey = (apiOrigin: string, accessToken: string) =>
    `share-file-link-device-token:${apiOrigin}:${accessToken}`;

const savedLinkDeviceToken = (apiOrigin: string, accessToken: string) => {
    try {
        return window.localStorage.getItem(
            linkDeviceTokenStorageKey(apiOrigin, accessToken),
        );
    } catch {
        return null;
    }
};

const saveLinkDeviceToken = (
    apiOrigin: string,
    accessToken: string,
    linkDeviceToken: string,
) => {
    try {
        window.localStorage.setItem(
            linkDeviceTokenStorageKey(apiOrigin, accessToken),
            linkDeviceToken,
        );
    } catch {
        // Ignore storage failures and continue with in-memory state.
    }
};

interface UseFileShareResult {
    loading: boolean;
    downloading: boolean;
    error: string | null;
    fileInfo: DecryptedFileInfo | null;
    accessToken: string | null;
    notificationProps: ReturnType<typeof useNotification>["notificationProps"];
    handleDownload: () => Promise<void>;
    handleCopyContent: (content: string) => Promise<void>;
}

export const useFileShare = (): UseFileShareResult => {
    const router = useRouter();
    const [loading, setLoading] = useState(true);
    const [downloading, setDownloading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [fileInfo, setFileInfo] = useState<DecryptedFileInfo | null>(null);
    const [accessToken, setAccessToken] = useState<string | null>(null);
    const { showNotification, notificationProps } = useNotification();

    useEffect(() => {
        const loadFileInfo = async () => {
            try {
                const token = window.location.pathname.slice(1);

                if (!token) {
                    setError("Invalid file link. Missing access token.");
                    setLoading(false);
                    return;
                }

                const currentURL = new URL(window.location.href);
                const keyMaterial = await extractFileKeyFromURL(currentURL);

                if (!keyMaterial) {
                    setError("Invalid file link. Missing secret.");
                    setLoading(false);
                    return;
                }

                setAccessToken(token);

                const currentAPIOrigin = await apiOrigin();
                const storedLinkDeviceToken = savedLinkDeviceToken(
                    currentAPIOrigin,
                    token,
                );
                const { fileLinkInfo: encryptedInfo, linkDeviceToken } =
                    await fetchFileInfo(
                        token,
                        storedLinkDeviceToken ?? undefined,
                    );
                if (linkDeviceToken) {
                    saveLinkDeviceToken(
                        currentAPIOrigin,
                        token,
                        linkDeviceToken,
                    );
                }
                const decryptedInfo = await decryptFileInfo(
                    encryptedInfo,
                    keyMaterial,
                );

                if (
                    decryptedInfo.fileName === "Unknown file" ||
                    decryptedInfo.fileName === "Encrypted file" ||
                    decryptedInfo.fileName === "Error: No file data"
                ) {
                    setError("File not found");
                    setFileInfo(null);
                } else {
                    setFileInfo(decryptedInfo);
                }
            } catch (err) {
                setError(
                    err instanceof Error
                        ? err.message
                        : "Failed to load file information",
                );
            } finally {
                setLoading(false);
            }
        };

        if (router.isReady) {
            void loadFileInfo();
        }
    }, [router.isReady]);

    const handleDownload = async () => {
        if (!accessToken || !fileInfo?.fileKey) return;

        setDownloading(true);
        try {
            await downloadFile(
                accessToken,
                fileInfo.fileKey,
                fileInfo.fileName,
                fileInfo.fileDecryptionHeader,
                fileInfo.fileNonce,
            );
        } catch (err) {
            setError(
                err instanceof Error ? err.message : "Failed to download file",
            );
        } finally {
            setDownloading(false);
        }
    };

    const handleCopyContent = async (content: string) => {
        try {
            await navigator.clipboard.writeText(content);
        } catch {
            showNotification({ color: "critical", title: "Failed to copy" });
        }
    };

    return {
        loading,
        downloading,
        error,
        fileInfo,
        accessToken,
        notificationProps,
        handleDownload,
        handleCopyContent,
    };
};
