import { accentGreen } from "@/theme/buttons";
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
import { useId } from "react";
import { AddPhotosIcon, CloseIcon } from "./icons";

export default function PhotoChoiceDialog({
    open,
    title,
    description,
    primary,
    secondary,
    onClose,
}: {
    open: boolean;
    title: string;
    description: string;
    primary: { label: string; onClick: () => void };
    secondary?: { label: string; onClick: () => void };
    onClose: () => void;
}) {
    const id = useId();
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
                    onClick={onClose}
                    sx={dialogCloseButtonSx}
                >
                    <CloseIcon sx={{ fontSize: 20 }} />
                </IconButton>
                <AddPhotosIcon
                    aria-hidden
                    sx={{ fontSize: 72, my: 3, color: accentGreen }}
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
                <Button
                    variant="contained"
                    fullWidth
                    autoFocus
                    onClick={primary.onClick}
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
