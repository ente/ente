import { Dialog, DialogContent, DialogTitle, Stack } from "@mui/material";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { t } from "i18next";
import React from "react";

export type SecondFactorType = "totp" | "passkey";

type SecondFactorChoiceProps = ModalVisibilityProps & {
    onSelect: (factor: SecondFactorType) => void;
};

export const SecondFactorChoice: React.FC<SecondFactorChoiceProps> = ({
    open,
    onClose,
    onSelect,
}) => (
    <Dialog
        open={open}
        onClose={(_, reason) => {
            if (reason != "backdropClick") onClose();
        }}
        fullWidth
        slotProps={{ paper: { sx: { maxWidth: "360px", padding: "12px" } } }}
    >
        <DialogTitle>{t("two_factor")}</DialogTitle>
        <DialogContent>
            <Stack sx={{ gap: "12px" }}>
                <FocusVisibleButton
                    color="accent"
                    onClick={() => {
                        onClose();
                        onSelect("totp");
                    }}
                >
                    {t("totp_login")}
                </FocusVisibleButton>

                <FocusVisibleButton
                    color="accent"
                    onClick={() => {
                        onClose();
                        onSelect("passkey");
                    }}
                >
                    {t("passkey_login")}
                </FocusVisibleButton>
            </Stack>
        </DialogContent>
    </Dialog>
);
