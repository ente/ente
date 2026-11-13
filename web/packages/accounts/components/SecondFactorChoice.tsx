import type { ModalProps } from "@mui/material";
import { SecondFactorChoiceDialog } from "ente-accounts/components/auth/SecondFactorChoiceDialog";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import type React from "react";

export type SecondFactorType = "totp" | "passkey";

export interface SecondFactorChoicePresentationProps {
    open: boolean;
    onDialogClose: ModalProps["onClose"];
    onSelect: (factor: SecondFactorType) => void;
}

type SecondFactorChoiceProps = ModalVisibilityProps & {
    onSelect: (factor: SecondFactorType) => void;
};

export const SecondFactorChoice: React.FC<SecondFactorChoiceProps> = ({
    open,
    onClose,
    onSelect,
}) => {
    const handleDialogClose: ModalProps["onClose"] = (_, reason) => {
        if (reason != "backdropClick") onClose();
    };

    const handleSelect = (factor: SecondFactorType) => {
        onClose();
        onSelect(factor);
    };

    return (
        <SecondFactorChoiceDialog
            open={open}
            onDialogClose={handleDialogClose}
            onSelect={handleSelect}
        />
    );
};
