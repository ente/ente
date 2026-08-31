import {
    Dialog,
    DialogContent,
    DialogTitle,
    Stack,
    type ModalProps,
} from "@mui/material";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { t } from "i18next";
import React, { type ComponentType } from "react";

export type SecondFactorType = "totp" | "passkey";

export interface SecondFactorChoicePresentationProps {
    open: boolean;
    onDialogClose: ModalProps["onClose"];
    onSelect: (factor: SecondFactorType) => void;
}

type SecondFactorChoiceProps = ModalVisibilityProps & {
    onSelect: (factor: SecondFactorType) => void;
    presentation?: ComponentType<SecondFactorChoicePresentationProps>;
};

export const SecondFactorChoice: React.FC<SecondFactorChoiceProps> = ({
    open,
    onClose,
    onSelect,
    presentation: Presentation,
}) => {
    const handleDialogClose: ModalProps["onClose"] = (_, reason) => {
        if (reason != "backdropClick") onClose();
    };

    const handleSelect = (factor: SecondFactorType) => {
        onClose();
        onSelect(factor);
    };

    if (Presentation) {
        return (
            <Presentation
                open={open}
                onDialogClose={handleDialogClose}
                onSelect={handleSelect}
            />
        );
    }

    return (
        <Dialog
            open={open}
            onClose={handleDialogClose}
            fullWidth
            slotProps={{
                paper: { sx: { maxWidth: "360px", padding: "12px" } },
            }}
        >
            <DialogTitle>{t("two_factor")}</DialogTitle>
            <DialogContent>
                <Stack sx={{ gap: "12px" }}>
                    <FocusVisibleButton
                        color="accent"
                        onClick={() => handleSelect("totp")}
                    >
                        {t("totp_login")}
                    </FocusVisibleButton>

                    <FocusVisibleButton
                        color="accent"
                        onClick={() => handleSelect("passkey")}
                    >
                        {t("passkey_login")}
                    </FocusVisibleButton>
                </Stack>
            </DialogContent>
        </Dialog>
    );
};
