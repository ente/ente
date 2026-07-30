import {
    LOCKER_FILE_LIMIT_PAID,
    LOCKER_MAX_FILE_SIZE_BYTES,
    LOCKER_STORAGE_LIMIT_PAID_BYTES,
    lockerUploadAllowance,
    type LockerUploadLimitState,
    type LockerUploadPreflightFailure,
} from "@/services/locker-limits";
import {
    createCollection as createCollectionAPI,
    createInfoItem,
    deleteCollection as deleteCollectionAPI,
    deleteCollectionKeepingFiles,
    emptyTrash as emptyTrashAPI,
    leaveCollection as leaveCollectionAPI,
    permanentlyDeleteFromTrash,
    renameCollection as renameCollectionAPI,
    restoreFromTrash,
    setItemImportant,
    shareCollection as shareCollectionAPI,
    trashFiles,
    unshareCollection as unshareCollectionAPI,
    updateFileItem,
    updateInfoItem,
    updateItemCollections,
    uploadLockerFile,
    type LockerUploadProgress,
} from "@/services/remote";
import type {
    LockerCollection,
    LockerItem,
    LockerItemType,
    LockerUploadCandidate,
} from "@/types";
import { getItemTitle, isCollectionOwner } from "@/types";
import { Box } from "@mui/material";
import { savedLocalUser } from "ente-accounts-rs/services/accounts-db";
import type { MiniDialogAttributes } from "ente-base/components/MiniDialog";
import log from "ente-base/log";
import { t } from "i18next";
import type { DragEvent } from "react";
import { useCallback, useEffect, useRef, useState } from "react";
import { Trans } from "react-i18next";
import { filterNonEmptyUploadItems } from "../createItemDialog/fileUploadHelpers";
import type { CreateItemDialogEditItem } from "../createItemDialog/useCreateItemDialogState";

type DragDataTransferItem = DataTransferItem & {
    webkitGetAsEntry?: () => FileSystemEntry | null;
};

type FileSystemFileEntry = FileSystemEntry & {
    file: (
        successCallback: (file: File) => void,
        errorCallback?: (error: DOMException) => void,
    ) => void;
};

interface FileSystemDirectoryReader {
    readEntries: (
        successCallback: (entries: FileSystemEntry[]) => void,
        errorCallback?: (error: DOMException) => void,
    ) => void;
}

type FileSystemDirectoryEntry = FileSystemEntry & {
    createReader: () => FileSystemDirectoryReader;
};

export interface DeleteCollectionDialogState {
    collectionID: number;
    collectionName: string;
    hasItems: boolean;
    deleteFromEverywhere: boolean;
    loading: boolean;
    error: string | null;
}

const COLLECTION_MUTATION_REFRESH_DELAY_MS = 750;
const UPLOAD_REFRESH_DEBOUNCE_MS = 250;
const UPLOAD_REFRESH_FOLLOW_UP_DELAYS_MS = [1200, 3000, 6000] as const;

const fileFromEntry = (entry: FileSystemFileEntry) =>
    new Promise<File>((resolve, reject) => {
        entry.file(resolve, reject);
    });

const readDirectoryEntries = (entry: FileSystemDirectoryEntry) =>
    new Promise<FileSystemEntry[]>((resolve, reject) => {
        const reader = entry.createReader();
        const entries: FileSystemEntry[] = [];
        const readBatch = () => {
            reader.readEntries((batch) => {
                if (batch.length === 0) {
                    resolve(entries);
                    return;
                }
                entries.push(...batch);
                readBatch();
            }, reject);
        };
        readBatch();
    });

const collectionNamesFromRelativePath = (relativePath?: string) => [
    ...new Set((relativePath?.split("/").slice(0, -1) ?? []).filter(Boolean)),
];

const uploadCandidateFromFile = (
    file: File,
    relativePath?: string,
): LockerUploadCandidate => ({
    file,
    relativePath,
    suggestedCollectionNames: collectionNamesFromRelativePath(relativePath),
});

const droppedUploadCandidateKey = (file: File, relativePath?: string) =>
    `${relativePath ?? file.name}:${file.size}:${file.lastModified}`;

interface DropUploadScanOptions {
    remainingFileCount: number;
    freeStorage: number;
}

interface DropUploadScanResult {
    items: LockerUploadCandidate[];
    preflightFailure?: LockerUploadPreflightFailure;
    scannedNonEmptyFileCount: number;
    scannedTotalSize: number;
}

type PendingDroppedNode =
    | { type: "entry"; entry: FileSystemEntry; parentPath: string }
    | { type: "file"; file: File; relativePath: string };

const collectUploadCandidatesFromDrop = async (
    droppedItems: DragDataTransferItem[],
    fallbackFiles: File[],
    options: DropUploadScanOptions,
): Promise<DropUploadScanResult> => {
    const items: LockerUploadCandidate[] = [];
    const pendingNodes: PendingDroppedNode[] = [];
    const seenUploadCandidateKeys = new Set<string>();
    let scannedNonEmptyFileCount = 0;
    let scannedTotalSize = 0;

    const addFile = (
        file: File,
        relativePath: string,
    ): LockerUploadPreflightFailure | undefined => {
        if (file.size === 0) {
            return undefined;
        }

        const dedupeKey = droppedUploadCandidateKey(file, relativePath);
        if (seenUploadCandidateKeys.has(dedupeKey)) {
            return undefined;
        }
        seenUploadCandidateKeys.add(dedupeKey);

        if (file.size > LOCKER_MAX_FILE_SIZE_BYTES) {
            return { reason: "fileTooLarge", fileName: file.name };
        }

        scannedNonEmptyFileCount += 1;
        if (scannedNonEmptyFileCount > options.remainingFileCount) {
            return { reason: "fileCountLimit" };
        }

        scannedTotalSize += file.size;
        if (scannedTotalSize > options.freeStorage) {
            return { reason: "storageLimit" };
        }

        items.push(uploadCandidateFromFile(file, relativePath));
        return undefined;
    };

    for (let index = droppedItems.length - 1; index >= 0; index -= 1) {
        const item = droppedItems[index]!;
        if (item.kind !== "file") {
            continue;
        }

        const getAsEntry = item.webkitGetAsEntry;
        const entry =
            typeof getAsEntry === "function" ? getAsEntry.call(item) : null;
        if (entry) {
            pendingNodes.push({ type: "entry", entry, parentPath: "" });
            continue;
        }

        const file = item.getAsFile();
        if (file) {
            pendingNodes.push({
                type: "file",
                file,
                relativePath: file.webkitRelativePath || file.name,
            });
        }
    }

    if (pendingNodes.length === 0) {
        for (const file of fallbackFiles) {
            const preflightFailure = addFile(
                file,
                file.webkitRelativePath || file.name,
            );
            if (preflightFailure) {
                return {
                    items,
                    preflightFailure,
                    scannedNonEmptyFileCount,
                    scannedTotalSize,
                };
            }
        }
        return { items, scannedNonEmptyFileCount, scannedTotalSize };
    }

    while (pendingNodes.length > 0) {
        const node = pendingNodes.pop()!;

        if (node.type === "file") {
            const preflightFailure = addFile(node.file, node.relativePath);
            if (preflightFailure) {
                return {
                    items,
                    preflightFailure,
                    scannedNonEmptyFileCount,
                    scannedTotalSize,
                };
            }
            continue;
        }

        if (node.entry.isFile) {
            const file = await fileFromEntry(node.entry as FileSystemFileEntry);
            const relativePath = node.parentPath
                ? `${node.parentPath}/${file.name}`
                : file.name;
            const preflightFailure = addFile(file, relativePath);
            if (preflightFailure) {
                return {
                    items,
                    preflightFailure,
                    scannedNonEmptyFileCount,
                    scannedTotalSize,
                };
            }
            continue;
        }

        if (node.entry.isDirectory) {
            const directoryPath = node.parentPath
                ? `${node.parentPath}/${node.entry.name}`
                : node.entry.name;
            const directoryEntries = await readDirectoryEntries(
                node.entry as FileSystemDirectoryEntry,
            );
            for (
                let index = directoryEntries.length - 1;
                index >= 0;
                index -= 1
            ) {
                pendingNodes.push({
                    type: "entry",
                    entry: directoryEntries[index]!,
                    parentPath: directoryPath,
                });
            }
        }
    }

    return { items, scannedNonEmptyFileCount, scannedTotalSize };
};

const collectionIDsForItemMutation = (
    item: LockerItem,
    selectedCollectionID: number | null,
) =>
    Array.from(
        new Set(
            selectedCollectionID === null
                ? item.collectionIDs.length > 0
                    ? item.collectionIDs
                    : [item.collectionID]
                : [item.collectionID],
        ),
    );

interface UseLockerActionsProps {
    collections: LockerCollection[];
    masterKey?: string;
    selectedCollectionID: number | null;
    routerPathname: string;
    ensureUploadLimitState: () => Promise<
        { userDetails: LockerUploadLimitState } | undefined
    >;
    refreshData: (masterKey?: string) => Promise<void>;
    navigateHome: () => void;
    removeCollectionFromState: (collectionID: number) => void;
    showMiniDialog: (attributes: MiniDialogAttributes) => void;
    trashLastUpdatedAt: number;
}

export const useLockerActions = ({
    collections,
    ensureUploadLimitState,
    masterKey,
    selectedCollectionID,
    routerPathname,
    refreshData,
    navigateHome,
    removeCollectionFromState,
    showMiniDialog,
    trashLastUpdatedAt,
}: UseLockerActionsProps) => {
    const currentUserID = savedLocalUser()?.id;
    const [createDialogOpen, setCreateDialogOpen] = useState(false);
    const [prefilledUploadItems, setPrefilledUploadItems] = useState<
        LockerUploadCandidate[]
    >([]);
    const [editItem, setEditItem] = useState<CreateItemDialogEditItem | null>(
        null,
    );
    const [deleteCollectionDialog, setDeleteCollectionDialog] =
        useState<DeleteCollectionDialogState | null>(null);
    const deleteCollectionDialogRef =
        useRef<DeleteCollectionDialogState | null>(null);
    const [toast, setToast] = useState<string | null>(null);
    const [shareCollectionID, setShareCollectionID] = useState<number | null>(
        null,
    );
    const [isDragActive, setIsDragActive] = useState(false);
    const dragDepthRef = useRef(0);
    const shareCollectionIDRef = useRef<number | null>(shareCollectionID);
    const selectedCollectionIDRef = useRef<number | null>(selectedCollectionID);
    const uploadRefreshTimeoutRef = useRef<number | null>(null);
    const uploadFollowUpRefreshTimeoutsRef = useRef<number[]>([]);

    useEffect(() => {
        if (deleteCollectionDialog) {
            deleteCollectionDialogRef.current = deleteCollectionDialog;
        }
    }, [deleteCollectionDialog]);

    useEffect(() => {
        shareCollectionIDRef.current = shareCollectionID;
    }, [shareCollectionID]);

    useEffect(() => {
        selectedCollectionIDRef.current = selectedCollectionID;
    }, [selectedCollectionID]);

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

    useEffect(() => {
        if (
            shareCollectionID !== null &&
            !collections.some(
                (collection) => collection.id === shareCollectionID,
            )
        ) {
            setShareCollectionID(null);
        }
    }, [collections, shareCollectionID]);

    useEffect(() => {
        if (
            editItem &&
            !collections.some((collection) =>
                collection.items.some((item) => item.id === editItem.id),
            )
        ) {
            setEditItem(null);
        }
    }, [collections, editItem]);

    const visibleDeleteCollectionDialog =
        deleteCollectionDialog ?? deleteCollectionDialogRef.current;

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

    const refreshCollectionsAfterMutation = useCallback(async () => {
        await new Promise((resolve) =>
            setTimeout(resolve, COLLECTION_MUTATION_REFRESH_DELAY_MS),
        );
        try {
            await refreshData();
        } catch (error) {
            log.error(
                "Failed to refresh locker data after collection mutation",
                error,
            );
        }
    }, [refreshData]);

    const scheduleUploadRefresh = useCallback(
        (delayMs: number) => {
            clearUploadRefreshTimeout();
            uploadRefreshTimeoutRef.current = window.setTimeout(() => {
                uploadRefreshTimeoutRef.current = null;
                void refreshData(masterKey);
            }, delayMs);
        },
        [clearUploadRefreshTimeout, masterKey, refreshData],
    );

    const scheduleUploadFollowUpRefreshes = useCallback(() => {
        clearUploadFollowUpRefreshes();
        uploadFollowUpRefreshTimeoutsRef.current =
            UPLOAD_REFRESH_FOLLOW_UP_DELAYS_MS.map((delayMs) =>
                window.setTimeout(() => {
                    void refreshData(masterKey);
                }, delayMs),
            );
    }, [clearUploadFollowUpRefreshes, masterKey, refreshData]);

    const handleCreateItem = useCallback(
        async (
            type: LockerItemType,
            data: Record<string, unknown>,
            collectionIDs: number[],
        ) => {
            if (!masterKey) {
                throw new Error("No master key");
            }
            await createInfoItem(collectionIDs, type, data, masterKey);
            await refreshData();
            setToast(t("recordSavedSuccessfully"));
        },
        [masterKey, refreshData],
    );

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
            await refreshData(masterKey);
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
            masterKey,
            refreshData,
            scheduleUploadFollowUpRefreshes,
        ],
    );

    const handleUploadItemComplete = useCallback(() => {
        scheduleUploadRefresh(UPLOAD_REFRESH_DEBOUNCE_MS);
    }, [scheduleUploadRefresh]);

    const handleUpdateItem = useCallback(
        async (
            type: LockerItemType,
            data: Record<string, unknown>,
            collectionIDs: number[],
        ) => {
            if (!masterKey || !editItem) {
                throw new Error("No master key or item");
            }

            if (type === "file") {
                const editedName =
                    typeof data.name === "string" ? data.name : "";
                await updateFileItem(editItem.id, editedName, masterKey);
            } else {
                await updateInfoItem(editItem.id, type, data, masterKey);
            }

            await updateItemCollections(editItem.id, collectionIDs, masterKey);
            await refreshData();
            setToast(t("fileUpdatedSuccessfully"));
        },
        [editItem, masterKey, refreshData],
    );

    const handleDeleteItem = useCallback(
        (item: LockerItem) => {
            const collectionIDs = collectionIDsForItemMutation(
                item,
                selectedCollectionID,
            );

            showMiniDialog({
                title: t("delete"),
                message: (
                    <Trans
                        i18nKey="deleteFileConfirmation"
                        components={{
                            fileName: (
                                <Box
                                    component="span"
                                    sx={{ fontWeight: 700, color: "text.base" }}
                                >
                                    {getItemTitle(item)}
                                </Box>
                            ),
                        }}
                    />
                ),
                continue: {
                    text: t("delete"),
                    color: "critical",
                    action: async () => {
                        for (const collectionID of collectionIDs) {
                            await trashFiles([item.id], collectionID);
                        }
                        await refreshData();
                        setToast(t("fileDeletedSuccessfully"));
                    },
                },
            });
        },
        [refreshData, selectedCollectionID, showMiniDialog],
    );

    const handleDeleteItems = useCallback(
        (items: LockerItem[]) => {
            if (items.length === 0) {
                return;
            }

            showMiniDialog({
                title: t("delete"),
                message: t("deleteMultipleFilesDialogBody", {
                    count: items.length,
                }),
                continue: {
                    text: t("yesDeleteFiles", { count: items.length }),
                    color: "critical",
                    action: async () => {
                        const fileIDsByCollection = new Map<
                            number,
                            Set<number>
                        >();
                        for (const item of items) {
                            const collectionIDs = collectionIDsForItemMutation(
                                item,
                                selectedCollectionID,
                            );
                            for (const collectionID of collectionIDs) {
                                const existing =
                                    fileIDsByCollection.get(collectionID) ??
                                    new Set<number>();
                                existing.add(item.id);
                                fileIDsByCollection.set(collectionID, existing);
                            }
                        }

                        for (const [
                            collectionID,
                            fileIDs,
                        ] of fileIDsByCollection.entries()) {
                            await trashFiles([...fileIDs], collectionID);
                        }

                        await refreshData();
                        setToast(
                            t("filesDeletedSuccessfully", {
                                count: items.length,
                            }),
                        );
                    },
                },
            });
        },
        [refreshData, selectedCollectionID, showMiniDialog],
    );

    const handleEditItem = useCallback(
        (item: LockerItem) => {
            const fullCollectionIDs = Array.from(
                new Set([
                    ...item.collectionIDs,
                    item.collectionID,
                    ...collections
                        .filter((collection) =>
                            collection.items.some(
                                (candidate) => candidate.id === item.id,
                            ),
                        )
                        .map((collection) => collection.id),
                ]),
            );

            setEditItem({
                id: item.id,
                type: item.type,
                data:
                    item.type === "file"
                        ? { name: getItemTitle(item) }
                        : (item.data as unknown as Record<string, unknown>),
                collectionID: item.collectionID,
                collectionIDs: fullCollectionIDs,
            });
        },
        [collections],
    );

    const handlePermanentlyDelete = useCallback(
        (items: LockerItem[]) => {
            showMiniDialog({
                title: t("permanentlyDelete"),
                message: t("permanentlyDeleteFilesBody", {
                    count: items.length,
                }),
                continue: {
                    text: t("permanentlyDelete"),
                    color: "critical",
                    action: async () => {
                        await permanentlyDeleteFromTrash(
                            items.map((item) => item.id),
                        );
                        await refreshData();
                        setToast(
                            t("filesDeletedPermanently", {
                                count: items.length,
                            }),
                        );
                    },
                },
            });
        },
        [refreshData, showMiniDialog],
    );

    const handleRestoreItem = useCallback(
        async (item: LockerItem, collectionID: number) => {
            if (!masterKey) {
                return;
            }
            await restoreFromTrash(
                [{ id: item.id, collectionID: item.collectionID }],
                collectionID,
                masterKey,
            );
            await refreshData();
            setToast(t("filesRestoredSuccessfully", { count: 1 }));
        },
        [masterKey, refreshData],
    );

    const handleEmptyTrash = useCallback(() => {
        showMiniDialog({
            title: t("empty_trash_title"),
            message: t("empty_trash_message"),
            continue: {
                text: t("empty_trash"),
                color: "critical",
                action: async () => {
                    await emptyTrashAPI(trashLastUpdatedAt);
                    await refreshData();
                    setToast(t("trashClearedSuccessfully"));
                },
            },
        });
    }, [refreshData, showMiniDialog, trashLastUpdatedAt]);

    const handleCreateCollection = useCallback(
        async (name: string): Promise<number> => {
            if (!masterKey) {
                throw new Error("No master key");
            }
            const id = await createCollectionAPI(name, masterKey);
            await refreshData();
            setToast(t("createCollectionSuccess"));
            return id;
        },
        [masterKey, refreshData],
    );

    const ensureCollectionsExist = useCallback(
        async (names: string[]) => {
            if (!masterKey) {
                throw new Error("No master key");
            }

            const normalizedNameToID = new Map(
                collections
                    .filter(
                        (collection) =>
                            currentUserID !== undefined &&
                            isCollectionOwner(collection, currentUserID),
                    )
                    .map((collection) => [
                        collection.name.trim().toLocaleLowerCase(),
                        collection.id,
                    ]),
            );
            let createdCollection = false;

            for (const name of names) {
                const normalizedName = name.trim().toLocaleLowerCase();
                if (!normalizedName || normalizedNameToID.has(normalizedName)) {
                    continue;
                }

                const id = await createCollectionAPI(name, masterKey);
                normalizedNameToID.set(normalizedName, id);
                createdCollection = true;
            }

            if (createdCollection) {
                await refreshData();
            }

            return normalizedNameToID;
        },
        [collections, currentUserID, masterKey, refreshData],
    );

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
        ],
    );

    const handleRenameCollection = useCallback(
        async (collectionID: number, newName: string) => {
            if (!masterKey) {
                return;
            }
            await renameCollectionAPI(collectionID, newName, masterKey);
            await refreshData();
            setToast(t("collectionRenamedSuccessfully"));
        },
        [masterKey, refreshData],
    );

    const handleDeleteCollection = useCallback(
        (collectionID: number) => {
            const collection = collections.find(
                (candidate) => candidate.id === collectionID,
            );
            if (!collection) {
                log.warn(
                    `Ignoring delete for missing collection ${collectionID}`,
                );
                return;
            }

            setDeleteCollectionDialog({
                collectionID,
                collectionName: collection.name,
                hasItems: collection.items.length > 0,
                deleteFromEverywhere: false,
                loading: false,
                error: null,
            });
        },
        [collections],
    );

    const handleConfirmDeleteCollection = useCallback(async () => {
        const dialogState = deleteCollectionDialog;
        if (!dialogState) {
            return;
        }

        const collection = collections.find(
            (candidate) => candidate.id === dialogState.collectionID,
        );
        if (!collection) {
            setDeleteCollectionDialog((current) =>
                current
                    ? { ...current, error: t("collectionNotFoundError") }
                    : current,
            );
            return;
        }

        const shouldNavigateHome =
            routerPathname === "/collection" &&
            selectedCollectionID === collection.id;

        setDeleteCollectionDialog((current) =>
            current ? { ...current, loading: true, error: null } : current,
        );

        try {
            if (dialogState.deleteFromEverywhere) {
                await deleteCollectionAPI(collection.id);
            } else if (collection.items.length > 0) {
                if (!masterKey) {
                    throw new Error("Missing master key");
                }
                await deleteCollectionKeepingFiles(collection, masterKey);
            } else {
                await deleteCollectionAPI(collection.id, { keepFiles: true });
            }

            if (shouldNavigateHome) {
                navigateHome();
            }
            removeCollectionFromState(collection.id);
            setDeleteCollectionDialog(null);
            setToast(t("collectionDeletedSuccessfully"));
            void refreshCollectionsAfterMutation();
        } catch (error) {
            log.error("Failed to delete collection", error);
            setDeleteCollectionDialog((current) =>
                current
                    ? {
                          ...current,
                          loading: false,
                          error:
                              error instanceof Error
                                  ? error.message
                                  : t("failedToDeleteCollection"),
                      }
                    : current,
            );
        }
    }, [
        collections,
        deleteCollectionDialog,
        masterKey,
        navigateHome,
        refreshCollectionsAfterMutation,
        removeCollectionFromState,
        routerPathname,
        selectedCollectionID,
    ]);

    const handleOpenShareCollection = useCallback(
        (collection: LockerCollection) => {
            setShareCollectionID(collection.id);
        },
        [],
    );

    const handleShareCollection = useCallback(
        async (collectionID: number, email: string) => {
            if (!masterKey) {
                throw new Error("No master key");
            }
            await shareCollectionAPI(collectionID, email, masterKey);
            await refreshData();
            setToast(t("collectionSharedSuccessfully"));
        },
        [masterKey, refreshData],
    );

    const handleUnshareCollection = useCallback(
        async (collectionID: number, email: string) => {
            await unshareCollectionAPI(collectionID, email);
            await refreshData();
            setToast(t("viewerRemovedSuccessfully"));
        },
        [refreshData],
    );

    const handleLeaveCollection = useCallback(
        (collection: LockerCollection) => {
            showMiniDialog({
                title: t("leaveCollection"),
                message: t("filesAddedByYouWillBeRemovedFromTheCollection"),
                continue: {
                    text: t("leaveCollection"),
                    color: "critical",
                    action: async () => {
                        await leaveCollectionAPI(collection.id);
                        if (shareCollectionIDRef.current === collection.id) {
                            setShareCollectionID(null);
                        }
                        if (selectedCollectionIDRef.current === collection.id) {
                            navigateHome();
                        }
                        removeCollectionFromState(collection.id);
                        setToast(t("leaveCollectionSuccessfully"));
                        void refreshCollectionsAfterMutation();
                    },
                },
            });
        },
        [
            navigateHome,
            refreshCollectionsAfterMutation,
            removeCollectionFromState,
            showMiniDialog,
        ],
    );

    const handleSetItemsImportant = useCallback(
        async (items: LockerItem[], shouldBeImportant: boolean) => {
            if (!masterKey) {
                throw new Error("No master key");
            }
            if (items.length === 0) {
                return;
            }

            let changedCount = 0;
            let pendingError: unknown;
            try {
                for (const item of items) {
                    if (
                        await setItemImportant(
                            item.id,
                            shouldBeImportant,
                            masterKey,
                        )
                    ) {
                        changedCount += 1;
                    }
                }
            } catch (error) {
                pendingError = error;
            }

            if (changedCount > 0) {
                await refreshData();
            }
            if (pendingError) {
                throw pendingError instanceof Error
                    ? pendingError
                    : new Error(t("failedToUpdateImportantStatus"));
            }

            if (changedCount === 0) {
                if (shouldBeImportant) {
                    setToast(t("allItemsAlreadyMarkedAsImportant"));
                }
                return;
            }

            if (shouldBeImportant) {
                setToast(
                    changedCount === 1
                        ? t("fileMarkedAsImportant")
                        : t("itemsMarkedAsImportant", { count: changedCount }),
                );
                return;
            }

            setToast(
                changedCount === 1
                    ? t("fileRemovedFromImportant")
                    : t("itemsRemovedFromImportant", { count: changedCount }),
            );
        },
        [masterKey, refreshData],
    );

    return {
        createDialogOpen,
        deleteCollectionDialog,
        editItem,
        ensureCollectionsExist,
        handleConfirmDeleteCollection,
        handleCreateCollection,
        handleCreateDialogClose,
        handleCreateItem,
        handleDeleteCollection,
        handleDeleteItem,
        handleDeleteItems,
        handleDragEnter,
        handleDragLeave,
        handleDragOver,
        handleDrop,
        handleEditItem,
        handleEmptyTrash,
        handleOpenShareCollection,
        handlePermanentlyDelete,
        handleLeaveCollection,
        handleRenameCollection,
        handleRestoreItem,
        handleSetItemsImportant,
        handleShareCollection,
        handleUnshareCollection,
        handleUpdateItem,
        handleUploadFileWithProgress,
        handleUploadItemComplete,
        handleUploadsFinished,
        isDragActive,
        openCreateDialog,
        prefilledUploadItems,
        setDeleteCollectionDialog,
        setEditItem,
        setShareCollectionID,
        shareCollectionID,
        toast,
        setToast,
        visibleDeleteCollectionDialog,
    };
};
