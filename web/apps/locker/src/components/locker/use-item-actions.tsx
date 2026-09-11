import { updateItemCollections } from "@/services/collection-membership";
import {
    createInfoItem,
    setItemImportant,
    updateFileItem,
    updateInfoItem,
} from "@/services/items";
import { trashFiles } from "@/services/trash";
import type { LockerCollection, LockerItem, LockerItemType } from "@/types";
import { getItemTitle } from "@/types";
import { t } from "i18next";
import { useCallback, useEffect, useState } from "react";
import { Trans } from "react-i18next";
import type { CreateItemDialogEditItem } from "../create-item/use-create-item-dialog-state";
import type { ConfirmDialogState } from "./use-locker-confirmation";

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

interface UseItemActionsProps {
    collections: LockerCollection[];
    masterKey?: string;
    selectedCollectionID: number | null;
    refreshData: (masterKey?: string) => Promise<void>;
    setToast: (message: string | null) => void;
    requestConfirmation: (dialog: ConfirmDialogState) => void;
}

export const useItemActions = ({
    collections,
    masterKey,
    selectedCollectionID,
    refreshData,
    setToast,
    requestConfirmation,
}: UseItemActionsProps) => {
    const [editItem, setEditItem] = useState<CreateItemDialogEditItem | null>(
        null,
    );

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
        [masterKey, refreshData, setToast],
    );

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
                await updateFileItem(editItem.id, editedName);
            } else {
                await updateInfoItem(editItem.id, type, data);
            }

            await updateItemCollections(editItem.id, collectionIDs, masterKey);
            await refreshData();
            setToast(t("fileUpdatedSuccessfully"));
        },
        [editItem, masterKey, refreshData, setToast],
    );

    const handleDeleteItem = useCallback(
        (item: LockerItem) => {
            const collectionIDs = collectionIDsForItemMutation(
                item,
                selectedCollectionID,
            );

            requestConfirmation({
                illustration: "/images/file_delete_icon.png",
                title: t("areYouSure"),
                body: (
                    <Trans
                        i18nKey="deleteFileConfirmation"
                        components={{
                            fileName: <strong>{getItemTitle(item)}</strong>,
                        }}
                    />
                ),
                confirmLabel: t("yesDeleteFiles", { count: 1 }),
                tone: "critical",
                action: async () => {
                    for (const collectionID of collectionIDs) {
                        await trashFiles([item.id], collectionID);
                    }
                    await refreshData();
                    setToast(t("fileDeletedSuccessfully"));
                },
                loading: false,
            });
        },
        [refreshData, requestConfirmation, selectedCollectionID, setToast],
    );

    const handleDeleteItems = useCallback(
        (items: LockerItem[]) => {
            if (items.length === 0) {
                return;
            }

            requestConfirmation({
                illustration: "/images/file_delete_icon.png",
                title: t("areYouSure"),
                body: t("deleteMultipleFilesDialogBody", {
                    count: items.length,
                }),
                confirmLabel: t("yesDeleteFiles", { count: items.length }),
                tone: "critical",
                action: async () => {
                    const fileIDsByCollection = new Map<number, Set<number>>();
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
                        t("filesDeletedSuccessfully", { count: items.length }),
                    );
                },
                loading: false,
            });
        },
        [refreshData, requestConfirmation, selectedCollectionID, setToast],
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
        [masterKey, refreshData, setToast],
    );

    return {
        editItem,
        setEditItem,
        handleCreateItem,
        handleUpdateItem,
        handleDeleteItem,
        handleDeleteItems,
        handleEditItem,
        handleSetItemsImportant,
    };
};
