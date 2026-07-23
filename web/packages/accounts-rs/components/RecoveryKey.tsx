import {
    Dialog,
    DialogActions,
    DialogContent,
    DialogTitle,
    Stack,
    Typography,
} from "@mui/material";
import type { MiniDialogAttributes } from "ente-base/components/MiniDialog";
import { SpacedRow } from "ente-base/components/containers";
import { DialogCloseIconButton } from "ente-base/components/mui/DialogCloseIconButton";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { errorDialogAttributes } from "ente-base/components/utils/dialog";
import { useIsSmallWidth } from "ente-base/components/utils/hooks";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import log from "ente-base/log";
import { saveStringAsFile } from "ente-base/utils/web";
import { t } from "i18next";
import { useCallback, useEffect, useState } from "react";
import {
    getUserRecoveryKey,
    recoveryKeyToMnemonic,
} from "../services/recovery-key";
import { CodeBlock } from "./CodeBlock";

type RecoveryKeyProps = ModalVisibilityProps & {
    showMiniDialog: (attributes: MiniDialogAttributes) => void;
};

export const RecoveryKey: React.FC<RecoveryKeyProps> = ({
    open,
    onClose,
    showMiniDialog,
}) => {
    const [recoveryKey, setRecoveryKey] = useState<string | undefined>();
    const fullScreen = useIsSmallWidth();

    const handleLoadError = useCallback(
        (e: unknown) => {
            log.error("Failed to generate recovery key", e);
            showMiniDialog(
                errorDialogAttributes(t("recovery_key_generation_failed")),
            );
            onClose();
        },
        [onClose, showMiniDialog],
    );

    useEffect(() => {
        if (!open) return;

        void getUserRecoveryKeyMnemonic()
            .then((key) => setRecoveryKey(key))
            .catch(handleLoadError);
    }, [open, handleLoadError]);

    const handleSaveClick = () => {
        saveRecoveryKeyMnemonicAsFile(recoveryKey!);
        onClose();
    };

    return (
        <Dialog
            fullScreen={fullScreen}
            open={open}
            onClose={onClose}
            // [Note: maxWidth "xs" on MUI dialogs]
            //
            // While logically the "xs" breakpoint doesn't make sense as a
            // maxWidth value (since as a breakpoint it's value is 0), in
            // practice MUI has hardcoded its value to a reasonable 444px.
            // https://github.com/mui/material-ui/issues/34646.
            maxWidth="xs"
            fullWidth
        >
            <SpacedRow sx={{ p: "8px 4px 8px 0" }}>
                <DialogTitle variant="h3">{t("recovery_key")}</DialogTitle>
                <DialogCloseIconButton {...{ onClose }} />
            </SpacedRow>
            <DialogContent>
                <Typography sx={{ mb: 3 }}>
                    {t("recovery_key_description")}
                </Typography>
                <Stack
                    sx={{
                        border: "1px dashed",
                        borderColor: "stroke.muted",
                        borderRadius: 1,
                    }}
                >
                    <CodeBlock code={recoveryKey} />
                    <Typography sx={{ m: 2 }}>
                        {t("key_not_stored_note")}
                    </Typography>
                </Stack>
            </DialogContent>
            <DialogActions>
                <FocusVisibleButton
                    color="secondary"
                    fullWidth
                    onClick={onClose}
                >
                    {t("do_this_later")}
                </FocusVisibleButton>
                <FocusVisibleButton
                    color="accent"
                    fullWidth
                    onClick={handleSaveClick}
                >
                    {t("save_key")}
                </FocusVisibleButton>
            </DialogActions>
        </Dialog>
    );
};

const getUserRecoveryKeyMnemonic = async () =>
    recoveryKeyToMnemonic(await getUserRecoveryKey());

const saveRecoveryKeyMnemonicAsFile = (key: string) =>
    saveStringAsFile(key, "ente-recovery-key.txt");
