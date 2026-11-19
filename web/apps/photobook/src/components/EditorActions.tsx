import { useBook } from "@/context/book";
import { useSpineTitlePrompt } from "@/hooks/useSpineTitlePrompt";
import { normalizeBookPages } from "@/lib/bookPages";
import {
    canInsertPage,
    DEFAULT_PRINT_SELECTION,
    getBindingPrintSelection,
    getPrintBinding,
    getPrintExportError,
} from "@/lib/printProducts";
import { editorToolbarButtonSx, headerButtonSx } from "@/theme/buttons";
import { toolbarColors } from "@/theme/colors";
import { Box, Button } from "@mui/material";
import { useState } from "react";
import EditorIconButton from "./EditorIconButton";
import {
    AddPageIcon,
    AddPhotosIcon,
    PreviewIcon,
    RedoIcon,
    UndoIcon,
} from "./icons";
import PrintValidationDialog, {
    type PrintValidation,
} from "./PrintValidationDialog";
import ResetBookButton from "./ResetBookButton";

export default function EditorActions({
    onAddPage,
    onAddPhotos,
}: {
    onAddPage: () => void;
    onAddPhotos: () => void;
}) {
    const { book, processingPhotos, undo, redo, canUndo, canRedo } = useBook(
        "book",
        "processingPhotos",
        "undo",
        "redo",
        "canUndo",
        "canRedo",
    );

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
                disabled={processingPhotos || !canInsertPage(book.pages.length)}
                sx={editorToolbarButtonSx}
            >
                Add pages
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
    const { book, setAppView, processingPhotos } = useBook(
        "book",
        "setAppView",
        "processingPhotos",
    );
    const [validation, setValidation] = useState<PrintValidation | null>(null);
    const { withSpineTitle, spineTitleDialog } = useSpineTitlePrompt();

    const handlePreview = () => {
        const binding = getPrintBinding(book.printSelection);
        const selection = binding
            ? getBindingPrintSelection(binding)
            : DEFAULT_PRINT_SELECTION;
        const pages = normalizeBookPages(book.pages);
        const error = getPrintExportError(selection, pages);
        if (error) {
            setValidation({ selection, pageCount: pages.length, error });
            return;
        }
        withSpineTitle(() => setAppView("results"));
    };

    return (
        <>
            <Button
                variant="contained"
                aria-label="Preview"
                startIcon={<PreviewIcon />}
                onClick={handlePreview}
                disabled={processingPhotos || book.pages.length === 0}
                sx={headerButtonSx}
            >
                <Box
                    component="span"
                    sx={{ display: { xs: "none", sm: "inline" } }}
                >
                    Preview
                </Box>
            </Button>
            {spineTitleDialog}
            {validation && (
                <PrintValidationDialog
                    validation={validation}
                    onClose={() => setValidation(null)}
                    actionLabel="Back to editing"
                />
            )}
        </>
    );
}
