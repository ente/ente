import log from "ente-base/log";
import { t } from "i18next";
import { useCallback, useEffect, useRef, useState } from "react";

export interface ConfirmDialogState {
    illustration: string;
    title: string;
    body: React.ReactNode;
    confirmLabel: string;
    tone: "critical" | "primary";
    action: () => Promise<void>;
    loading: boolean;
    error?: string;
}

export const useLockerConfirmation = () => {
    const [confirmDialog, setConfirmDialog] =
        useState<ConfirmDialogState | null>(null);
    const confirmDialogRef = useRef<ConfirmDialogState | null>(null);

    useEffect(() => {
        if (confirmDialog) {
            confirmDialogRef.current = confirmDialog;
        }
    }, [confirmDialog]);

    const visibleConfirmDialog = confirmDialog ?? confirmDialogRef.current;

    const closeConfirmDialog = useCallback(() => {
        if (!confirmDialog?.loading) setConfirmDialog(null);
    }, [confirmDialog]);

    const handleConfirmDialogConfirm = useCallback(async () => {
        if (!confirmDialog || confirmDialog.loading) {
            return;
        }

        setConfirmDialog({ ...confirmDialog, loading: true, error: undefined });
        try {
            await confirmDialog.action();
            setConfirmDialog(null);
        } catch (error) {
            log.error("Failed to confirm Locker action", error);
            setConfirmDialog((current) =>
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
            setConfirmDialog((current) =>
                current ? { ...current, loading: false } : current,
            );
        }
    }, [confirmDialog]);

    return {
        confirmDialog,
        visibleConfirmDialog,
        requestConfirmation: setConfirmDialog,
        closeConfirmDialog,
        handleConfirmDialogConfirm,
    };
};
