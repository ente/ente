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
import React, { useCallback } from "react";
import { SingleInputForm, type SingleInputFormProps } from "./SingleInputForm";

type SingleInputDialogProps = ModalVisibilityProps &
    Omit<SingleInputFormProps, "onCancel"> & {
        /** Title of the dialog. */
        title: string;
    };

/**
 * A dialog that can be used to ask for a single text input using a
 * {@link SingleInputForm}.
 *
 * The dialog closes when the promise returned by the {@link onSubmit} callback
 * fulfills.
 *
 * See also: {@link CollectionNamer}, its older sibling.
 */
export const SingleInputDialog: React.FC<SingleInputDialogProps> = ({
    open,
    onClose,
    onSubmit,
    title,
    variant = "default",
    ...rest
}) => {
    const handleSubmit: SingleInputFormProps["onSubmit"] = useCallback(
        async (value, setFieldError) => {
            await onSubmit(value, setFieldError);
            onClose();
        },
        [onClose, onSubmit],
    );

    if (variant === "v2") {
        return (
            <Dialog
                open={open}
                onClose={onClose}
                maxWidth={false}
                slotProps={{ paper: { sx: v2PaperSx } }}
            >
                <Stack sx={{ p: "20px", gap: "20px" }}>
                    <Stack direction="row" sx={v2HeaderRowSx}>
                        <Typography sx={v2TitleSx}>{title}</Typography>
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
                        variant="v2"
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

const surfaceStroke = "#e0e0e0";
const surfaceStrokeDark = "rgba(255 255 255 / 0.12)";

const v2PaperSx: SxProps<Theme> = (theme) => ({
    width: "min(444px, calc(100svw - 32px))",
    maxWidth: "444px",
    boxSizing: "content-box",
    m: 2,
    borderRadius: "20px",
    border: `1px solid ${surfaceStroke}`,
    backgroundColor: "#f4f4f4",
    backgroundImage: "none",
    boxShadow: "none",
    color: "text.base",
    ...theme.applyStyles("dark", {
        borderColor: surfaceStrokeDark,
        backgroundColor: "#1b1b1b",
    }),
});
const v2HeaderRowSx = {
    alignItems: "center",
    justifyContent: "space-between",
    gap: "12px",
};
const v2TitleSx = { fontSize: 24, lineHeight: "32px", fontWeight: 600 };
const v2CloseButtonSx = (theme: Theme) => ({
    width: 38,
    height: 38,
    p: 0,
    flexShrink: 0,
    color: "text.base",
    backgroundColor: "background.paper",
    "&:hover": { backgroundColor: "fill.faintHover" },
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255 255 255 / 0.12)",
    }),
});
