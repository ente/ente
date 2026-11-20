import { accentGreen } from "@/theme/buttons";
import { uiColors } from "@/theme/colors";
import {
    dialogActionSx,
    dialogCancelButtonSx,
    dialogCloseButtonSx,
    dialogDescriptionSx,
    dialogHeaderSx,
    dialogPaperSx,
    dialogTitleSx,
} from "@/theme/dialogs";
import { Box, Button, Dialog, IconButton, Typography } from "@mui/material";
import { useId, type ReactNode } from "react";
import {
    AddPhotosIcon,
    BookIcon,
    CloseIcon,
    LockIcon,
    WarningIcon,
} from "./icons";

export default function PhotoChoiceDialog({
    open,
    title,
    description,
    primary,
    secondary,
    onClose,
    children,
    icon = "photos",
}: {
    open: boolean;
    title: string;
    description: string;
    primary: { label: string; onClick: () => void; disabled?: boolean };
    secondary?: { label: string; onClick: () => void };
    onClose?: () => void;
    children?: ReactNode;
    icon?: "photos" | "warning" | "lock" | "book";
}) {
    const id = useId();
    const Icon = {
        photos: AddPhotosIcon,
        warning: WarningIcon,
        lock: LockIcon,
        book: BookIcon,
    }[icon];
    return (
        <Dialog
            open={open}
            onClose={onClose}
            maxWidth={false}
            aria-labelledby={id + "-title"}
            aria-describedby={id + "-description"}
            slotProps={{
                paper: { sx: dialogPaperSx },
                backdrop: { sx: { bgcolor: "rgba(0,0,0,0.5)" } },
            }}
        >
            <Box
                sx={{
                    position: "relative",
                    display: "grid",
                    justifyItems: "center",
                    gap: 1.5,
                    p: "48px 16px 16px",
                }}
            >
                <IconButton
                    aria-label="Close"
                    disabled={!onClose}
                    onClick={onClose}
                    sx={dialogCloseButtonSx}
                >
                    <CloseIcon sx={{ fontSize: 20 }} />
                </IconButton>
                <Icon
                    aria-hidden
                    sx={{
                        fontSize: 72,
                        my: 3,
                        color: icon === "photos" ? accentGreen : uiColors.muted,
                    }}
                />
                <Box sx={dialogHeaderSx}>
                    <Typography
                        component="h2"
                        id={id + "-title"}
                        sx={dialogTitleSx}
                    >
                        {title}
                    </Typography>
                    <Typography
                        id={id + "-description"}
                        sx={dialogDescriptionSx}
                    >
                        {description}
                    </Typography>
                </Box>
                {children}
                <Button
                    variant="contained"
                    fullWidth
                    onClick={primary.onClick}
                    disabled={primary.disabled}
                    sx={dialogActionSx}
                >
                    {primary.label}
                </Button>
                {secondary && (
                    <Button
                        variant="outlined"
                        fullWidth
                        onClick={secondary.onClick}
                        sx={dialogCancelButtonSx}
                    >
                        {secondary.label}
                    </Button>
                )}
            </Box>
        </Dialog>
    );
}
