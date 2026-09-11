import {
    LOCKER_FILE_LIMIT_PAID,
    LOCKER_STORAGE_LIMIT_PAID_BYTES,
    lockerUploadAllowance,
    type LockerUploadLimitState,
    type LockerUploadPreflightFailure,
} from "@/services/locker-limits";
import {
    uploadLockerFile,
    type LockerUploadProgress,
} from "@/services/uploads";
import type { LockerUploadCandidate } from "@/types";
import log from "ente-base/log";
import { t } from "i18next";
import type { DragEvent } from "react";
import { useCallback, useEffect, useRef, useState } from "react";
import { filterNonEmptyUploadItems } from "../create-item/file-upload-helpers";
import {
    collectUploadCandidatesFromDrop,
    type DragDataTransferItem,
} from "../create-item/scan-dropped-files";

const UPLOAD_REFRESH_DEBOUNCE_MS = 250;

const UPLOAD_REFRESH_FOLLOW_UP_DELAYS_MS = [1200, 3000, 6000] as const;

interface UseLockerUploadsProps {
    masterKey?: string;
    ensureUploadLimitState: () => Promise<
        { userDetails: LockerUploadLimitState } | undefined
    >;
    refreshData: (masterKey?: string) => Promise<void>;
    setToast: (message: string | null) => void;
}

export const useLockerUploads = ({
    masterKey,
    ensureUploadLimitState,
    refreshData,
    setToast,
}: UseLockerUploadsProps) => {
    const [createDialogOpen, setCreateDialogOpen] = useState(false);

    const [prefilledUploadItems, setPrefilledUploadItems] = useState<
        LockerUploadCandidate[]
    >([]);

    const [isDragActive, setIsDragActive] = useState(false);

    const dragDepthRef = useRef(0);

    const uploadRefreshTimeoutRef = useRef<number | null>(null);

    const uploadFollowUpRefreshTimeoutsRef = useRef<number[]>([]);

    const clearUploadRefreshTimeout = useCallback(() => {
        if (uploadRefreshTimeoutRef.current !== null) {
            window.clearTimeout(uploadRefreshTimeoutRef.current);
            uploadRefreshTimeoutRef.current = null;
        }
    }, []);

    const clearUploadFollowUpRefreshes = useCallback(() => {
        uploadFollowUpRefreshTimeoutsRef.current.forEach((timeoutID) => {
            window.clearTimeout(timeoutID);
        });
        uploadFollowUpRefreshTimeoutsRef.current = [];
    }, []);

    useEffect(
        () => () => {
            clearUploadRefreshTimeout();
            clearUploadFollowUpRefreshes();
        },
        [clearUploadFollowUpRefreshes, clearUploadRefreshTimeout],
    );

    const uploadPreflightFailureMessage = useCallback(
        (
            failure: LockerUploadPreflightFailure,
            projectedFileCount: number,
            projectedUsage: number,
        ) => {
            if (
                (projectedFileCount > LOCKER_FILE_LIMIT_PAID ||
                    projectedUsage > LOCKER_STORAGE_LIMIT_PAID_BYTES) &&
                (failure.reason === "fileCountLimit" ||
                    failure.reason === "storageLimit")
            ) {
                return t("uploadLockerHardCapErrorBody");
            }
            switch (failure.reason) {
                case "fileCountLimit":
                    return t("uploadFileCountLimitErrorBody");
                case "fileTooLarge":
                    return t("uploadFileTooLargeErrorBody", {
                        fileName: failure.fileName ?? "",
                    });
                case "storageLimit":
                    return t("uploadStorageLimitErrorBody");
            }
        },
        [],
    );

    const scheduleUploadRefresh = useCallback(
        (delayMs: number) => {
            clearUploadRefreshTimeout();
            uploadRefreshTimeoutRef.current = window.setTimeout(() => {
                uploadRefreshTimeoutRef.current = null;
                void refreshData();
            }, delayMs);
        },
        [clearUploadRefreshTimeout, refreshData],
    );

    const scheduleUploadFollowUpRefreshes = useCallback(() => {
        clearUploadFollowUpRefreshes();
        uploadFollowUpRefreshTimeoutsRef.current =
            UPLOAD_REFRESH_FOLLOW_UP_DELAYS_MS.map((delayMs) =>
                window.setTimeout(() => {
                    void refreshData();
                }, delayMs),
            );
    }, [clearUploadFollowUpRefreshes, refreshData]);

    const handleUploadFileWithProgress = useCallback(
        async (
            file: File,
            collectionIDs: number[],
            onProgress: (progress: LockerUploadProgress) => void,
        ) => {
            if (!masterKey) {
                throw new Error("No master key");
            }
            await uploadLockerFile(file, collectionIDs, masterKey, onProgress);
        },
        [masterKey],
    );

    const handleUploadsFinished = useCallback(
        async (uploadedCount: number) => {
            clearUploadRefreshTimeout();
            clearUploadFollowUpRefreshes();
            await refreshData();
            scheduleUploadFollowUpRefreshes();
            setToast(
                uploadedCount === 1
                    ? t("uploadComplete")
                    : t("uploadMultipleComplete", { count: uploadedCount }),
            );
        },
        [
            clearUploadFollowUpRefreshes,
            clearUploadRefreshTimeout,
            refreshData,
            scheduleUploadFollowUpRefreshes,
            setToast,
        ],
    );

    const handleUploadItemComplete = useCallback(() => {
        scheduleUploadRefresh(UPLOAD_REFRESH_DEBOUNCE_MS);
    }, [scheduleUploadRefresh]);

    const handleCreateDialogClose = useCallback(() => {
        setCreateDialogOpen(false);
        setPrefilledUploadItems([]);
    }, []);

    const openUploadDialogForItems = useCallback(
        (items: LockerUploadCandidate[]) => {
            const nonEmptyItems = filterNonEmptyUploadItems(items);
            if (nonEmptyItems.length === 0) {
                return;
            }
            setPrefilledUploadItems(nonEmptyItems);
            setCreateDialogOpen(true);
        },
        [],
    );

    const openCreateDialog = useCallback(() => {
        setPrefilledUploadItems([]);
        setCreateDialogOpen(true);
    }, []);

    const handleDragEnter = useCallback((event: DragEvent<HTMLElement>) => {
        if (!event.dataTransfer.types.includes("Files")) {
            return;
        }
        event.preventDefault();
        event.stopPropagation();
        dragDepthRef.current += 1;
        setIsDragActive(true);
    }, []);

    const handleDragOver = useCallback((event: DragEvent<HTMLElement>) => {
        if (!event.dataTransfer.types.includes("Files")) {
            return;
        }
        event.preventDefault();
        event.stopPropagation();
        event.dataTransfer.dropEffect = "copy";
    }, []);

    const handleDragLeave = useCallback((event: DragEvent<HTMLElement>) => {
        if (!event.dataTransfer.types.includes("Files")) {
            return;
        }
        event.preventDefault();
        event.stopPropagation();
        dragDepthRef.current = Math.max(0, dragDepthRef.current - 1);
        if (dragDepthRef.current === 0) {
            setIsDragActive(false);
        }
    }, []);

    const handleDrop = useCallback(
        async (event: DragEvent<HTMLElement>) => {
            event.preventDefault();
            event.stopPropagation();
            dragDepthRef.current = 0;
            setIsDragActive(false);

            try {
                const uploadLimitState = await ensureUploadLimitState();
                if (!uploadLimitState) {
                    setToast(t("generic_error_retry"));
                    return;
                }

                const allowance = lockerUploadAllowance(
                    uploadLimitState.userDetails,
                );
                const droppedItems = Array.from(
                    event.dataTransfer.items,
                ) as DragDataTransferItem[];
                const scanResult = await collectUploadCandidatesFromDrop(
                    droppedItems,
                    Array.from(event.dataTransfer.files),
                    {
                        remainingFileCount: allowance.remainingFileCount,
                        freeStorage: allowance.freeStorage,
                    },
                );

                if (scanResult.preflightFailure) {
                    setToast(
                        uploadPreflightFailureMessage(
                            scanResult.preflightFailure,
                            lockerUploadAllowance(uploadLimitState.userDetails)
                                .currentFileCount +
                                scanResult.scannedNonEmptyFileCount,
                            uploadLimitState.userDetails.usage +
                                scanResult.scannedTotalSize,
                        ),
                    );
                    return;
                }

                openUploadDialogForItems(scanResult.items);
            } catch (error) {
                log.error("Failed to process dropped Locker files", error);
                setToast(t("generic_error_retry"));
            }
        },
        [
            ensureUploadLimitState,
            openUploadDialogForItems,
            uploadPreflightFailureMessage,
            setToast,
        ],
    );

    return {
        createDialogOpen,
        prefilledUploadItems,
        isDragActive,
        handleCreateDialogClose,
        openCreateDialog,
        handleUploadFileWithProgress,
        handleUploadsFinished,
        handleUploadItemComplete,
        handleDragEnter,
        handleDragOver,
        handleDragLeave,
        handleDrop,
    };
};
