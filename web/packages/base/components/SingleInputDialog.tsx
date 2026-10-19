import CloseIcon from "@mui/icons-material/Close";
import {
    Dialog,
    DialogContent,
    DialogTitle,
    IconButton,
    Stack,
    Typography,
    type SxProps,
    type Theme,
} from "@mui/material";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { t } from "i18next";
import React, { useCallback, useId } from "react";
import {
    v2CloseButtonSx,
    v2HeaderRowSx,
    v2PaperSx,
    v2TitleSx,
} from "./SingleInput.styles";
import { SingleInputForm, type SingleInputFormProps } from "./SingleInputForm";

type SingleInputDialogProps = ModalVisibilityProps &
    Omit<SingleInputFormProps, "onCancel"> & {
        title: string;
        sx?: SxProps<Theme>;
    };

export const SingleInputDialog: React.FC<SingleInputDialogProps> = ({
    open,
    onClose,
    onSubmit,
    title,
    sx,
    variant = "default",
    ...rest
}) => {
    const titleID = useId();
    const handleSubmit: SingleInputFormProps["onSubmit"] = useCallback(
        async (value, setFieldError) => {
            await onSubmit(value, setFieldError);
            onClose();
        },
        [onClose, onSubmit],
    );

    if (variant !== "default") {
        return (
            <Dialog
                open={open}
                onClose={onClose}
                maxWidth={false}
                aria-labelledby={variant === "people" ? titleID : undefined}
                sx={sx}
                slotProps={{ paper: { sx: v2PaperSx } }}
            >
                <Stack sx={{ p: "20px", gap: "20px" }}>
                    <Stack direction="row" sx={v2HeaderRowSx}>
                        <Typography
                            id={variant === "people" ? titleID : undefined}
                            sx={v2TitleSx}
                        >
                            {title}
                        </Typography>
                        <IconButton
                            aria-label={t("close")}
                            onClick={onClose}
                            sx={v2CloseButtonSx}
                        >
                            <CloseIcon sx={{ fontSize: 18 }} />
                        </IconButton>
                    </Stack>
                    <SingleInputForm
                        key={open ? "open" : "closed"}
                        variant={variant}
                        onCancel={onClose}
                        onSubmit={handleSubmit}
                        {...rest}
                    />
                </Stack>
            </Dialog>
        );
    }

    return (
        <Dialog
            open={open}
            onClose={onClose}
            maxWidth="xs"
            fullWidth
            sx={sx}
            slotProps={{ paper: { sx: { p: "8px 4px 4px 4px" } } }}
        >
            <DialogTitle>{title}</DialogTitle>
            <DialogContent sx={{ "&&&": { pt: 0 } }}>
                <SingleInputForm
                    onCancel={onClose}
                    onSubmit={handleSubmit}
                    {...rest}
                />
            </DialogContent>
        </Dialog>
    );
};
