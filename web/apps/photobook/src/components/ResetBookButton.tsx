"use client";

import { useBook } from "@/context/book";
import { editorButtonSx } from "@/theme/buttons";
import { pageMenuColors, toolbarColors, uiColors } from "@/theme/colors";
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
import { useState } from "react";
import { CloseIcon, DeleteIcon } from "./icons";

export default function ResetBookButton() {
    const { startOver, processingPhotos, book } = useBook();
    const [open, setOpen] = useState(false);
    const [resetting, setResetting] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const close = () => {
        if (!resetting) setOpen(false);
    };

    const handleReset = async () => {
        if (resetting || !open) return;
        setResetting(true);
        setError(null);
        try {
            await startOver();
            setOpen(false);
        } catch {
            setError("Couldn't reset the photobook. Please try again.");
            setResetting(false);
        }
    };

    return (
        <>
            <Button
                variant="text"
                onClick={() => {
                    setError(null);
                    setOpen(true);
                }}
                disabled={
                    processingPhotos || resetting || book.pages.length === 0
                }
                sx={{
                    ...editorButtonSx,
                    color: toolbarColors.muted,
                    bgcolor: "transparent",
                    outline: "none",
                    transition: "color 120ms ease, background-color 120ms ease",
                    "&:hover": {
                        color: uiColors.danger,
                        bgcolor: pageMenuColors.dangerHover,
                    },
                    "&:focus-visible": {
                        color: uiColors.danger,
                        bgcolor: pageMenuColors.dangerHover,
                        outline: "none",
                    },
                    "&:active": {
                        color: uiColors.danger,
                        bgcolor: pageMenuColors.dangerActive,
                    },
                }}
            >
                Reset
            </Button>
            <Dialog
                open={open}
                onClose={close}
                aria-labelledby="reset-book-title"
                aria-describedby="reset-book-description"
                aria-busy={resetting}
                maxWidth={false}
                sx={{ zIndex: 1500 }}
                slotProps={{
                    paper: { sx: dialogPaperSx },
                    backdrop: { sx: { bgcolor: "rgba(0,0,0,0.5)" } },
                    // Keep interactions locked until the unchanged dialog has faded out.
                    transition: { onExited: () => setResetting(false) },
                }}
            >
                <Box sx={{ position: "relative", p: "48px 16px 16px" }}>
                    <IconButton
                        aria-label="Close"
                        onClick={close}
                        aria-disabled={resetting}
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
                                color: uiColors.danger,
                            }}
                        >
                            <DeleteIcon sx={{ fontSize: 72 }} />
                        </Box>
                        <Box sx={dialogHeaderSx}>
                            <Typography
                                component="h2"
                                id="reset-book-title"
                                sx={dialogTitleSx}
                            >
                                Reset this photobook
                            </Typography>
                            <Typography
                                id="reset-book-description"
                                sx={dialogDescriptionSx}
                            >
                                Remove all photos and edits from this photobook?
                                Your original photos will stay untouched.
                            </Typography>
                        </Box>
                        {error && (
                            <Typography
                                role="alert"
                                sx={{
                                    color: uiColors.danger,
                                    fontSize: 13,
                                    lineHeight: "18px",
                                    textAlign: "center",
                                }}
                            >
                                {error}
                            </Typography>
                        )}
                        <Box
                            sx={{
                                display: "flex",
                                flexDirection: "column",
                                gap: "12px",
                                width: "100%",
                            }}
                        >
                            {/* Guard clicks without changing labels, styling, or focus during reset. */}
                            <Button
                                variant="contained"
                                fullWidth
                                disableElevation
                                onClick={handleReset}
                                aria-disabled={resetting}
                                sx={{
                                    ...dialogActionSx,
                                    color: "#FFFFFF",
                                    bgcolor: "#F63A3A",
                                    "&:hover": { bgcolor: "#DD3434" },
                                }}
                            >
                                Reset
                            </Button>
                            <Button
                                variant="outlined"
                                fullWidth
                                autoFocus
                                onClick={close}
                                aria-disabled={resetting}
                                sx={dialogCancelButtonSx}
                            >
                                Cancel
                            </Button>
                        </Box>
                    </Box>
                </Box>
            </Dialog>
        </>
    );
}
