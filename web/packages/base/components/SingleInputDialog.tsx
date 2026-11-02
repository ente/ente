import CloseIcon from "@mui/icons-material/Close";
import {
    Dialog,
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
        description?: string;
        sx?: SxProps<Theme>;
    };

export const SingleInputDialog: React.FC<SingleInputDialogProps> = ({
    open,
    onClose,
    onSubmit,
    title,
    description,
    inputProps,
    sx,
    ...rest
}) => {
    const titleID = useId();
    const descriptionID = useId();
    const handleSubmit: SingleInputFormProps["onSubmit"] = useCallback(
        async (value, setFieldError) => {
            const submission = { hasError: false };
            await onSubmit(value, (message) => {
                submission.hasError = true;
                setFieldError(message);
            });
            if (!submission.hasError) onClose();
        },
        [onClose, onSubmit],
    );

    return (
        <Dialog
            open={open}
            onClose={onClose}
            maxWidth={false}
            aria-labelledby={titleID}
            aria-describedby={description ? descriptionID : undefined}
            sx={sx}
            slotProps={{ paper: { sx: v2PaperSx } }}
        >
            <Stack sx={{ p: "20px", gap: "20px" }}>
                <Stack direction="row" sx={v2HeaderRowSx}>
                    <Typography id={titleID} sx={v2TitleSx}>
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
                {description && (
                    <Typography id={descriptionID} sx={{ color: "text.muted" }}>
                        {description}
                    </Typography>
                )}
                <SingleInputForm
                    key={open ? "open" : "closed"}
                    onCancel={onClose}
                    onSubmit={handleSubmit}
                    inputProps={{
                        ...inputProps,
                        "aria-describedby":
                            [
                                inputProps?.["aria-describedby"],
                                description ? descriptionID : undefined,
                            ]
                                .filter(Boolean)
                                .join(" ") || undefined,
                    }}
                    {...rest}
                    disabled={!open || rest.disabled}
                />
            </Stack>
        </Dialog>
    );
};
