import { LockerConfirmDialog } from "@/components/ui/LockerConfirmDialog";
import { t } from "i18next";

export interface EmptyTrashDialogState {
    loading: boolean;
    error?: string;
}

interface EmptyTrashDialogProps {
    dialogState: EmptyTrashDialogState | null;
    visibleDialogState: EmptyTrashDialogState | null;
    onClose: () => void;
    onConfirm: () => Promise<void> | void;
}

export function EmptyTrashDialog({
    dialogState,
    visibleDialogState,
    onClose,
    onConfirm,
}: EmptyTrashDialogProps) {
    return (
        <LockerConfirmDialog
            open={dialogState !== null}
            illustration="/images/collection_delete_icon.png"
            title={t("empty_trash_title")}
            body={t("empty_trash_message")}
            confirmLabel={t("empty_trash")}
            loading={visibleDialogState?.loading}
            error={visibleDialogState?.error}
            onClose={onClose}
            onConfirm={onConfirm}
        />
    );
}
