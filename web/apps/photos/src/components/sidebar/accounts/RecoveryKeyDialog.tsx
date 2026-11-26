import { PhotosFormDialog } from "@/components/PhotosFormDialog";
import { ButtonBase, Stack, Typography } from "@mui/material";
import { CopyButton } from "ente-accounts/components/CodeBlock";
import {
    RecoveryKeyContents,
    type RecoveryKeyPresentationProps,
} from "ente-accounts/components/RecoveryKey";
import {
    peopleActionFocusSx,
    v2CancelButtonSx,
    v2SubmitButtonSx,
} from "ente-base/components/SingleInput.styles";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import { t } from "i18next";
import { useId, type ComponentProps } from "react";

type RecoveryKeyDialogProps = Omit<
    ComponentProps<typeof RecoveryKeyContents>,
    "presentation"
>;

export function RecoveryKeyDialog(props: RecoveryKeyDialogProps) {
    const { open, onClose } = props;
    const descriptionID = useId();

    return (
        <PhotosFormDialog
            open={open}
            onClose={onClose}
            title={t("recovery_key")}
            descriptionID={descriptionID}
        >
            <Typography id={descriptionID} sx={{ color: "text.muted" }}>
                {t("recovery_key_description")}
            </Typography>
            <RecoveryKeyContents
                {...props}
                presentation={RecoveryKeyPresentation}
            />
        </PhotosFormDialog>
    );
}

function RecoveryKeyPresentation({
    recoveryKey,
    onClose,
    onSave,
}: RecoveryKeyPresentationProps) {
    return (
        <>
            <Stack
                direction="row"
                sx={{
                    alignItems: "center",
                    justifyContent: recoveryKey ? "space-between" : "center",
                    gap: 1,
                    p: 2,
                    minHeight: 96,
                    borderRadius: "16px",
                    bgcolor: "background.paper",
                }}
            >
                {recoveryKey ? (
                    <>
                        <Typography
                            component="code"
                            sx={{
                                fontFamily: "monospace",
                                fontSize: 14,
                                lineHeight: "22px",
                                overflowWrap: "anywhere",
                            }}
                        >
                            {recoveryKey}
                        </Typography>
                        <CopyButton
                            code={recoveryKey}
                            label={t("auth_copy_recovery_key")}
                            sx={{
                                color: "text.muted",
                                alignSelf: "flex-start",
                                flexShrink: 0,
                            }}
                        />
                    </>
                ) : (
                    <ActivityIndicator size={24} aria-label={t("loading")} />
                )}
            </Stack>
            <Typography variant="small" sx={{ color: "text.muted" }}>
                {t("key_not_stored_note")}
            </Typography>
            <Stack direction="row" sx={{ gap: "12px" }}>
                <ButtonBase
                    onClick={onClose}
                    sx={[v2CancelButtonSx, peopleActionFocusSx]}
                >
                    {t("do_this_later")}
                </ButtonBase>
                <ButtonBase
                    disabled={!recoveryKey}
                    onClick={onSave}
                    sx={[v2SubmitButtonSx, peopleActionFocusSx]}
                >
                    {t("save_key")}
                </ButtonBase>
            </Stack>
        </>
    );
}
