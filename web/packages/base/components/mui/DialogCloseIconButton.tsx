import CloseIcon from "@mui/icons-material/Close";
import { IconButton } from "@mui/material";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { t } from "i18next";
import React from "react";

type DialogCloseIconButtonProps = Omit<ModalVisibilityProps, "open">;

export const DialogCloseIconButton: React.FC<DialogCloseIconButtonProps> = ({
    onClose,
}) => (
    <IconButton aria-label={t("close")} color="secondary" onClick={onClose}>
        <CloseIcon />
    </IconButton>
);
