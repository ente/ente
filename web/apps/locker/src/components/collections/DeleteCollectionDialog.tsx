import { LockerConfirmDialog } from "@/components/ui/LockerConfirmDialog";
import { t } from "i18next";
import React from "react";
import type { DeleteCollectionDialogState } from "../locker/use-collection-actions";

interface DeleteCollectionDialogProps {
    dialogState: DeleteCollectionDialogState | null;
    visibleDialogState: DeleteCollectionDialogState | null;
    onClose: () => void;
    onConfirm: () => Promise<void> | void;
    onToggleDeleteFromEverywhere: (checked: boolean) => void;
}

export const DeleteCollectionDialog: React.FC<DeleteCollectionDialogProps> = ({
    dialogState,
    visibleDialogState,
    onClose,
    onConfirm,
    onToggleDeleteFromEverywhere,
}) => (
    <LockerConfirmDialog
        open={dialogState !== null}
        illustration="/images/collection_delete_icon.png"
        title={t("deleteCollectionTitle")}
        body={t("deleteCollectionDialogBody", {
            collectionName: visibleDialogState?.collectionName ?? "",
        })}
        confirmLabel={t("delete")}
        checkbox={
            visibleDialogState?.hasItems
                ? {
                      label: t("deleteCollectionFromEverywhere"),
                      checked: visibleDialogState.deleteFromEverywhere,
                      onChange: onToggleDeleteFromEverywhere,
                  }
                : undefined
        }
        loading={visibleDialogState?.loading}
        error={visibleDialogState?.error ?? undefined}
        onClose={onClose}
        onConfirm={onConfirm}
    />
);
