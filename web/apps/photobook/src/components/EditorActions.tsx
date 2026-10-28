"use client";

import { useBook } from "@/context/book";
import { normalizeBookPages } from "@/lib/bookPages";
import {
    getBindingPrintSelection,
    getPrintBinding,
    getPrintExportError,
    getPrintProduct,
} from "@/lib/printProducts";
import {
    accentGreen,
    accentGreenHover,
    editorToolbarButtonSx,
    headerButtonSx,
} from "@/theme/buttons";
import { toolbarColors, uiColors } from "@/theme/colors";
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
import EditorIconButton from "./EditorIconButton";
import {
    AddPageIcon,
    AddPhotosIcon,
    CloseIcon,
    InfoIcon,
    PreviewIcon,
    RedoIcon,
    UndoIcon,
} from "./icons";
import ResetBookButton from "./ResetBookButton";

export default function EditorActions({
    onAddPage,
    onAddPhotos,
}: {
    onAddPage: () => void;
    onAddPhotos: () => void;
}) {
    const { book, processingPhotos, undo, redo, canUndo, canRedo } = useBook();

    return (
        <Box
            role="group"
            aria-label="Editing tools"
            sx={{
                display: "flex",
                flexWrap: "wrap",
                minWidth: 0,
                alignItems: "center",
                justifyContent: "center",
                gap: "var(--toolbar-inset)",
                "& .MuiButton-root, & .MuiIconButton-root": {
                    height: 40,
                    borderRadius:
                        "calc(var(--toolbar-radius) - var(--toolbar-inset))",
                },
                "& .MuiButton-root": {
                    px: "16px",
                    "& .MuiButton-startIcon": { mr: "8px" },
                },
                "& .MuiIconButton-root": { width: 40, minWidth: 40 },
            }}
        >
            <Button
                startIcon={<AddPhotosIcon />}
                onClick={onAddPhotos}
                disabled={processingPhotos}
                sx={editorToolbarButtonSx}
            >
                Add photos
            </Button>
            <Button
                startIcon={<AddPageIcon />}
                onClick={onAddPage}
                disabled={processingPhotos || book.pages.length < 2}
                sx={editorToolbarButtonSx}
            >
                Add page
            </Button>
            <Box
                role="group"
                aria-label="Edit history"
                sx={{
                    display: "flex",
                    gap: "var(--toolbar-inset)",
                    pl: "var(--toolbar-inset)",
                    borderLeft: `1px solid ${toolbarColors.border}`,
                }}
            >
                <EditorIconButton
                    label="Undo"
                    onClick={undo}
                    disabled={!canUndo || processingPhotos}
                >
                    <UndoIcon />
                </EditorIconButton>
                <EditorIconButton
                    label="Redo"
                    onClick={redo}
                    disabled={!canRedo || processingPhotos}
                >
                    <RedoIcon />
                </EditorIconButton>
            </Box>
            <Box
                sx={{
                    pl: "var(--toolbar-inset)",
                    borderLeft: `1px solid ${toolbarColors.border}`,
                }}
            >
                <ResetBookButton />
            </Box>
        </Box>
    );
}

export function EditorPreviewButton() {
    const { book, setAppView, processingPhotos } = useBook();
    const [validationError, setValidationError] = useState<{
        title: string;
        description: string;
    } | null>(null);
    const [validationOpen, setValidationOpen] = useState(false);
    const id = useId();
    // Keep the copy mounted while the dialog's exit transition runs.
    const closeValidation = () => setValidationOpen(false);

    const handlePreview = () => {
        const selection = getBindingPrintSelection(
            getPrintBinding(book.printSelection),
        );
        const pageCount = normalizeBookPages(book.pages).length;
        const error = getPrintExportError(selection, pageCount);
        if (error) {
            const { minPages, maxPages } = getPrintProduct(
                selection.productId,
            )!;
            if (pageCount < minPages) {
                const missing = minPages - pageCount;
                setValidationError({
                    title: `Add ${missing} more ${missing === 1 ? "page" : "pages"}`,
                    description: `Printed books need at least ${minPages} pages, including the covers.`,
                });
            } else if (pageCount > maxPages) {
                const extra = pageCount - maxPages;
                setValidationError({
                    title: `Remove ${extra} ${extra === 1 ? "page" : "pages"}`,
                    description: `Printed books can have up to ${maxPages} pages, including the covers.`,
                });
            } else {
                setValidationError({
                    title: "Update your book",
                    description: error,
                });
            }
            setValidationOpen(true);
            return;
        }
        setAppView("results");
    };

    return (
        <>
            <Button
                variant="contained"
                aria-label="Preview"
                startIcon={<PreviewIcon strokeWidth={2.2} />}
                onClick={handlePreview}
                disabled={processingPhotos || book.pages.length === 0}
                sx={{ ...headerButtonSx, fontWeight: 700 }}
            >
                <Box
                    component="span"
                    sx={{ display: { xs: "none", sm: "inline" } }}
                >
                    Preview
                </Box>
            </Button>
            <Dialog
                open={validationOpen}
                onClose={closeValidation}
                maxWidth={false}
                aria-labelledby={`${id}-title`}
                aria-describedby={`${id}-description`}
                slotProps={{
                    paper: { sx: dialogPaperSx },
                    backdrop: { sx: { bgcolor: "rgba(0,0,0,0.5)" } },
                }}
            >
                <Box sx={{ position: "relative", p: "48px 16px 16px" }}>
                    <IconButton
                        aria-label="Close"
                        onClick={closeValidation}
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
                                {validationError?.title}
                            </Typography>
                            <Typography
                                id={`${id}-description`}
                                sx={{ ...dialogDescriptionSx, px: 4 }}
                            >
                                {validationError?.description}
                            </Typography>
                        </Box>
                        <Button
                            variant="contained"
                            fullWidth
                            disableElevation
                            autoFocus
                            onClick={closeValidation}
                            sx={{
                                ...dialogActionSx,
                                color: "#FFFFFF",
                                bgcolor: accentGreen,
                                "&:hover": { bgcolor: accentGreenHover },
                            }}
                        >
                            Back to editing
                        </Button>
                    </Box>
                </Box>
            </Dialog>
        </>
    );
}
