import { lockerDialogPaperSx } from "@/components/lockerDialogStyles";
import {
    Checkbox,
    Dialog,
    DialogContent,
    DialogTitle,
    FormControlLabel,
    Stack,
    Typography,
} from "@mui/material";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { t } from "i18next";
import React from "react";
import type { DeleteCollectionDialogState } from "./useLockerActions";

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
    <Dialog
        open={dialogState !== null}
        onClose={() => {
            if (!dialogState?.loading) {
                onClose();
            }
        }}
        fullWidth
        maxWidth="xs"
        slotProps={{
            paper: {
                sx: { ...lockerDialogPaperSx, width: "min(100%, 420px)" },
            },
        }}
    >
        <DialogTitle sx={{ pb: 1 }}>{t("deleteCollectionTitle")}</DialogTitle>
        <DialogContent>
            <Stack sx={{ gap: 2.25 }}>
                <Typography sx={{ color: "text.muted" }}>
                    {t("deleteCollectionDialogBody", {
                        collectionName:
                            visibleDialogState?.collectionName ?? "",
                    })}
                </Typography>
                {visibleDialogState?.hasItems && (
                    <FormControlLabel
                        control={
                            <Checkbox
                                checked={
                                    visibleDialogState.deleteFromEverywhere
                                }
                                disabled={visibleDialogState.loading}
                                onChange={(event) =>
                                    onToggleDeleteFromEverywhere(
                                        event.target.checked,
                                    )
                                }
                            />
                        }
                        label={t("deleteCollectionFromEverywhere")}
                        sx={{ alignItems: "center", m: 0 }}
                    />
                )}
                {visibleDialogState?.error && (
                    <Typography variant="small" sx={{ color: "critical.main" }}>
                        {visibleDialogState.error}
                    </Typography>
                )}
                <Stack direction="row" sx={{ gap: 1 }}>
                    <FocusVisibleButton
                        fullWidth
                        color="secondary"
                        disabled={visibleDialogState?.loading}
                        onClick={onClose}
                    >
                        {t("cancel")}
                    </FocusVisibleButton>
                    <LoadingButton
                        fullWidth
                        color="critical"
                        loading={visibleDialogState?.loading}
                        onClick={onConfirm}
                    >
                        {t("delete")}
                    </LoadingButton>
                </Stack>
            </Stack>
        </DialogContent>
    </Dialog>
);
