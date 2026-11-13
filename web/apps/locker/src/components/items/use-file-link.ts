import {
    deleteLockerFileShareLink,
    getOrCreateLockerFileShareLink,
} from "@/services/file-links";
import type { LockerItem } from "@/types";
import { canShareLockerFileLink, getItemTitle } from "@/types";
import { isHTTPErrorWithStatus } from "ente-base/http";
import log from "ente-base/log";
import { t } from "i18next";
import { useCallback, useEffect, useMemo, useState } from "react";

interface FileLinkOptions {
    allItemsByID: Map<number, LockerItem>;
    currentUserID: number | undefined;
    setFeedbackMessage: (message: string | null) => void;
}
export function useFileLink({
    allItemsByID,
    currentUserID,
    setFeedbackMessage,
}: FileLinkOptions) {
    const [activeFileLinkItemID, setActiveFileLinkItemID] = useState<
        number | null
    >(null);
    const [activeFileLink, setActiveFileLink] = useState<{
        linkID: string;
        url: string;
    } | null>(null);
    const [isCreatingFileLink, setIsCreatingFileLink] = useState(false);
    const [isDeletingFileLink, setIsDeletingFileLink] = useState(false);
    const [isDeleteFileLinkConfirmOpen, setIsDeleteFileLinkConfirmOpen] =
        useState(false);
    const activeFileLinkItem = useMemo(
        () =>
            activeFileLinkItemID === null
                ? null
                : (allItemsByID.get(activeFileLinkItemID) ?? null),
        [activeFileLinkItemID, allItemsByID],
    );
    const canNativeShare =
        typeof navigator !== "undefined" &&
        typeof navigator.share === "function";

    useEffect(() => {
        if (activeFileLinkItemID !== null && !activeFileLinkItem) {
            setActiveFileLinkItemID(null);
            setActiveFileLink(null);
            setIsCreatingFileLink(false);
            setIsDeletingFileLink(false);
            setIsDeleteFileLinkConfirmOpen(false);
        }
    }, [activeFileLinkItem, activeFileLinkItemID]);

    const closeFileLinkDialog = useCallback(() => {
        if (
            isCreatingFileLink ||
            isDeletingFileLink ||
            isDeleteFileLinkConfirmOpen
        ) {
            return;
        }
        setActiveFileLinkItemID(null);
        setActiveFileLink(null);
    }, [isCreatingFileLink, isDeleteFileLinkConfirmOpen, isDeletingFileLink]);
    const openFileLinkDialog = useCallback(
        async (item: LockerItem) => {
            if (!canShareLockerFileLink(item, currentUserID)) {
                setFeedbackMessage(t("shareNotSupportedForSharedFiles"));
                return;
            }

            setActiveFileLinkItemID(item.id);
            setActiveFileLink(null);
            setIsCreatingFileLink(true);
            try {
                const link = await getOrCreateLockerFileShareLink(item.id);
                setActiveFileLink(link);
            } catch (error) {
                log.error(
                    `Failed to create share link for file ${item.id}`,
                    error,
                );
                setFeedbackMessage(
                    isHTTPErrorWithStatus(error, 402)
                        ? t("sharingRequiresPaidPlan")
                        : t("failedToCreateShareLink"),
                );
                setActiveFileLinkItemID(null);
            } finally {
                setIsCreatingFileLink(false);
            }
        },
        [currentUserID, setFeedbackMessage],
    );
    const copyActiveFileLink = useCallback(async () => {
        if (!activeFileLink?.url) {
            return;
        }
        await navigator.clipboard.writeText(activeFileLink.url);
        setFeedbackMessage(t("linkCopiedToClipboard"));
    }, [activeFileLink?.url, setFeedbackMessage]);
    const shareActiveFileLink = useCallback(async () => {
        if (!activeFileLink?.url) {
            return;
        }

        if (canNativeShare) {
            try {
                await navigator.share({
                    title: activeFileLinkItem
                        ? getItemTitle(activeFileLinkItem)
                        : undefined,
                    url: activeFileLink.url,
                });
                return;
            } catch (error) {
                if (
                    error instanceof DOMException &&
                    error.name === "AbortError"
                ) {
                    return;
                }
            }
        }

        await navigator.clipboard.writeText(activeFileLink.url);
        setFeedbackMessage(t("linkCopiedToClipboard"));
    }, [
        activeFileLink?.url,
        activeFileLinkItem,
        canNativeShare,
        setFeedbackMessage,
    ]);
    const deleteActiveFileLink = useCallback(async () => {
        if (!activeFileLinkItem) {
            return;
        }

        setIsDeletingFileLink(true);
        try {
            await deleteLockerFileShareLink(
                activeFileLinkItem.id,
                activeFileLink?.linkID,
            );
            setFeedbackMessage(t("shareLinkDeletedSuccessfully"));
            setActiveFileLinkItemID(null);
            setActiveFileLink(null);
        } catch (error) {
            log.error(
                `Failed to delete share link for file ${activeFileLinkItem.id}`,
                error,
            );
            setFeedbackMessage(t("failedToDeleteShareLink"));
        } finally {
            setIsDeletingFileLink(false);
            setIsDeleteFileLinkConfirmOpen(false);
        }
    }, [activeFileLink?.linkID, activeFileLinkItem, setFeedbackMessage]);
    return {
        activeFileLinkItem,
        activeFileLink,
        canNativeShare,
        isCreatingFileLink,
        isDeletingFileLink,
        isDeleteFileLinkConfirmOpen,
        setIsDeleteFileLinkConfirmOpen,
        closeFileLinkDialog,
        openFileLinkDialog,
        copyActiveFileLink,
        shareActiveFileLink,
        deleteActiveFileLink,
    };
}
