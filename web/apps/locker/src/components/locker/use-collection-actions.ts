import { deleteCollectionKeepingFiles } from "@/services/collection-membership";
import {
    leaveCollection as leaveCollectionAPI,
    shareCollection as shareCollectionAPI,
    unshareCollection as unshareCollectionAPI,
} from "@/services/collection-sharing";
import {
    createCollection as createCollectionAPI,
    deleteCollection as deleteCollectionAPI,
    renameCollection as renameCollectionAPI,
} from "@/services/collections";
import type { LockerCollection } from "@/types";
import { isCollectionOwner } from "@/types";
import { savedLocalUser } from "ente-accounts/services/accounts-db";
import log from "ente-base/log";
import { t } from "i18next";
import { useCallback, useEffect, useRef, useState } from "react";
import type { ConfirmDialogState } from "./use-locker-confirmation";

export interface DeleteCollectionDialogState {
    collectionID: number;
    collectionName: string;
    hasItems: boolean;
    deleteFromEverywhere: boolean;
    loading: boolean;
    error: string | null;
}

const COLLECTION_MUTATION_REFRESH_DELAY_MS = 750;

interface UseCollectionActionsProps {
    collections: LockerCollection[];
    masterKey?: string;
    selectedCollectionID: number | null;
    routerPathname: string;
    navigateHome: () => void;
    removeCollectionFromState: (collectionID: number) => void;
    refreshData: (masterKey?: string) => Promise<void>;
    setToast: (message: string | null) => void;
    requestConfirmation: (dialog: ConfirmDialogState) => void;
}

export const useCollectionActions = ({
    collections,
    masterKey,
    selectedCollectionID,
    routerPathname,
    navigateHome,
    removeCollectionFromState,
    refreshData,
    setToast,
    requestConfirmation,
}: UseCollectionActionsProps) => {
    const currentUserID = savedLocalUser()?.id;

    const [deleteCollectionDialog, setDeleteCollectionDialog] =
        useState<DeleteCollectionDialogState | null>(null);

    const deleteCollectionDialogRef =
        useRef<DeleteCollectionDialogState | null>(null);

    const [shareCollectionID, setShareCollectionID] = useState<number | null>(
        null,
    );

    const shareCollectionIDRef = useRef<number | null>(shareCollectionID);

    const selectedCollectionIDRef = useRef<number | null>(selectedCollectionID);

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

    const visibleDeleteCollectionDialog =
        deleteCollectionDialog ?? deleteCollectionDialogRef.current;

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
        [masterKey, refreshData, setToast],
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

    const handleRenameCollection = useCallback(
        async (collectionID: number, newName: string) => {
            await renameCollectionAPI(collectionID, newName);
            await refreshData();
            setToast(t("collectionRenamedSuccessfully"));
        },
        [refreshData, setToast],
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
        setToast,
    ]);

    const handleOpenShareCollection = useCallback(
        (collection: LockerCollection) => {
            setShareCollectionID(collection.id);
        },
        [],
    );

    const handleShareCollection = useCallback(
        async (collectionID: number, email: string) => {
            await shareCollectionAPI(collectionID, email);
            await refreshData();
            setToast(t("collectionSharedSuccessfully"));
        },
        [refreshData, setToast],
    );

    const handleUnshareCollection = useCallback(
        async (collectionID: number, email: string) => {
            await unshareCollectionAPI(collectionID, email);
            await refreshData();
            setToast(t("viewerRemovedSuccessfully"));
        },
        [refreshData, setToast],
    );

    const handleLeaveCollection = useCallback(
        (collection: LockerCollection) => {
            requestConfirmation({
                illustration: "/images/warning-grey.png",
                title: t("leaveCollection"),
                body: t("filesAddedByYouWillBeRemovedFromTheCollection"),
                confirmLabel: t("leaveCollection"),
                tone: "primary",
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
                loading: false,
            });
        },
        [
            navigateHome,
            refreshCollectionsAfterMutation,
            removeCollectionFromState,
            requestConfirmation,
            setToast,
        ],
    );

    return {
        deleteCollectionDialog,
        visibleDeleteCollectionDialog,
        setDeleteCollectionDialog,
        shareCollectionID,
        setShareCollectionID,
        handleCreateCollection,
        ensureCollectionsExist,
        handleRenameCollection,
        handleDeleteCollection,
        handleConfirmDeleteCollection,
        handleOpenShareCollection,
        handleShareCollection,
        handleUnshareCollection,
        handleLeaveCollection,
    };
};
