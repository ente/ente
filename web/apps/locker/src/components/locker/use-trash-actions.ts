import {
    emptyTrash as emptyTrashAPI,
    permanentlyDeleteFromTrash,
    restoreFromTrash,
} from "@/services/trash";
import type { LockerItem } from "@/types";
import log from "ente-base/log";
import { t } from "i18next";
import { useCallback, useEffect, useRef, useState } from "react";
import type { EmptyTrashDialogState } from "./EmptyTrashDialog";
import type { ConfirmDialogState } from "./use-locker-confirmation";

interface UseTrashActionsProps {
    refreshData: (masterKey?: string) => Promise<void>;
    requestConfirmation: (dialog: ConfirmDialogState) => void;
    setToast: (message: string | null) => void;
    trashLastUpdatedAt: number;
}

export const useTrashActions = ({
    refreshData,
    requestConfirmation,
    setToast,
    trashLastUpdatedAt,
}: UseTrashActionsProps) => {
    const [emptyTrashDialog, setEmptyTrashDialog] =
        useState<EmptyTrashDialogState | null>(null);
    const emptyTrashDialogRef = useRef<EmptyTrashDialogState | null>(null);

    useEffect(() => {
        if (emptyTrashDialog) {
            emptyTrashDialogRef.current = emptyTrashDialog;
        }
    }, [emptyTrashDialog]);

    const visibleEmptyTrashDialog =
        emptyTrashDialog ?? emptyTrashDialogRef.current;

    const handlePermanentlyDelete = useCallback(
        (items: LockerItem[]) => {
            requestConfirmation({
                illustration: "/images/warning-red.png",
                title: t("permanentlyDelete"),
                body: t("permanentlyDeleteFilesBody", { count: items.length }),
                confirmLabel: t("permanentlyDelete"),
                tone: "critical",
                action: async () => {
                    await permanentlyDeleteFromTrash(
                        items.map((item) => item.id),
                    );
                    await refreshData();
                    setToast(
                        t("filesDeletedPermanently", { count: items.length }),
                    );
                },
                loading: false,
            });
        },
        [refreshData, requestConfirmation, setToast],
    );

    const handleRestoreItem = useCallback(
        async (item: LockerItem, collectionID: number) => {
            await restoreFromTrash(
                [{ id: item.id, collectionID: item.collectionID }],
                collectionID,
            );
            await refreshData();
            setToast(t("filesRestoredSuccessfully", { count: 1 }));
        },
        [refreshData, setToast],
    );

    const handleEmptyTrash = useCallback(() => {
        setEmptyTrashDialog({ loading: false });
    }, []);

    const handleConfirmEmptyTrash = useCallback(async () => {
        if (!emptyTrashDialog || emptyTrashDialog.loading) {
            return;
        }

        setEmptyTrashDialog({ loading: true });
        try {
            await emptyTrashAPI(trashLastUpdatedAt);
            await refreshData();
            setToast(t("trashClearedSuccessfully"));
            setEmptyTrashDialog(null);
        } catch (error) {
            log.error("Failed to empty Locker trash", error);
            setEmptyTrashDialog((current) =>
                current
                    ? {
                          ...current,
                          error:
                              error instanceof Error
                                  ? error.message
                                  : t("generic_error"),
                      }
                    : current,
            );
        } finally {
            setEmptyTrashDialog((current) =>
                current ? { ...current, loading: false } : current,
            );
        }
    }, [emptyTrashDialog, refreshData, setToast, trashLastUpdatedAt]);

    return {
        emptyTrashDialog,
        visibleEmptyTrashDialog,
        setEmptyTrashDialog,
        handlePermanentlyDelete,
        handleRestoreItem,
        handleEmptyTrash,
        handleConfirmEmptyTrash,
    };
};
