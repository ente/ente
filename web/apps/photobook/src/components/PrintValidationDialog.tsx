import { getPrintProduct, type PrintSelection } from "@/lib/printProducts";
import { uiColors } from "@/theme/colors";
import {
    dialogActionSx,
    dialogCloseButtonSx,
    dialogDescriptionSx,
    dialogHeaderSx,
    dialogPaperSx,
    dialogTitleSx,
} from "@/theme/dialogs";
import { Box, Button, Dialog, IconButton, Typography } from "@mui/material";
import { useId, useState } from "react";
import { CloseIcon, InfoIcon } from "./icons";

export interface PrintValidation {
    selection: PrintSelection;
    pageCount: number;
    error: string;
}

export default function PrintValidationDialog({
    validation,
    onClose,
    actionLabel = "Got it",
}: {
    validation: PrintValidation;
    onClose: () => void;
    actionLabel?: string;
}) {
    const id = useId();
    const [open, setOpen] = useState(true);
    const close = () => setOpen(false);
    const { selection, pageCount, error } = validation;
    const { minPages, maxPages } = getPrintProduct(selection.productId)!;
    let title = "Update your book";
    let description = error;
    if (pageCount < minPages) {
        title = "Too few pages";
        description = `At least ${minPages} pages are required, including the front and back covers.`;
    } else if (pageCount > maxPages) {
        title = "Too many pages";
        description = `The limit is ${maxPages} pages, including the front and back covers.`;
    }

    return (
        <Dialog
            open={open}
            onClose={close}
            maxWidth={false}
            aria-labelledby={`${id}-title`}
            aria-describedby={`${id}-description`}
            slotProps={{
                paper: { sx: dialogPaperSx },
                backdrop: { sx: { bgcolor: "rgba(0,0,0,0.5)" } },
                transition: { onExited: onClose },
            }}
        >
            <Box sx={{ position: "relative", p: "48px 16px 16px" }}>
                <IconButton
                    aria-label="Close"
                    onClick={close}
                    sx={dialogCloseButtonSx}
                >
                    <CloseIcon sx={{ fontSize: 20 }} />
                </IconButton>
                <Box
                    sx={{
                        display: "flex",
                        flexDirection: "column",
                        alignItems: "center",
                        gap: "16px",
                    }}
                >
                    <Box
                        aria-hidden="true"
                        sx={{
                            width: 126,
                            height: 121,
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                            mb: "8px",
                            color: uiColors.muted,
                        }}
                    >
                        <InfoIcon sx={{ fontSize: 72 }} />
                    </Box>
                    <Box sx={dialogHeaderSx}>
                        <Typography
                            component="h2"
                            id={`${id}-title`}
                            sx={dialogTitleSx}
                        >
                            {title}
                        </Typography>
                        <Typography
                            id={`${id}-description`}
                            sx={dialogDescriptionSx}
                        >
                            {description}
                        </Typography>
                    </Box>
                    <Button
                        variant="contained"
                        fullWidth
                        autoFocus
                        onClick={close}
                        sx={dialogActionSx}
                    >
                        {actionLabel}
                    </Button>
                </Box>
            </Box>
        </Dialog>
    );
}
