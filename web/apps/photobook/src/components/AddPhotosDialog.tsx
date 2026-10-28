"use client";

import {
    MAX_PAGE_PHOTOS,
    photoDestinationError,
    type PhotoDestination,
} from "@/lib/photoPlacement";
import type { BookPage } from "@/lib/types";
import { accentGreen, accentGreenHover } from "@/theme/buttons";
import { uiColors } from "@/theme/colors";
import {
    dialogActionSx,
    dialogCloseButtonSx,
    dialogHeaderSx,
    dialogPaperSx,
    dialogSelectMenuProps,
    dialogSelectSx,
    dialogTitleSx,
} from "@/theme/dialogs";
import {
    Box,
    Button,
    Dialog,
    IconButton,
    MenuItem,
    Select,
    Typography,
} from "@mui/material";
import { useId, useState } from "react";
import { AddPhotosIcon, CloseIcon } from "./icons";

interface AddPhotosDialogProps {
    pages: BookPage[];
    photoCount: number;
    busy: boolean;
    progress: number;
    onClose: () => void;
    onAdd: (destination: PhotoDestination) => Promise<void>;
}

export default function AddPhotosDialog({
    pages,
    photoCount,
    busy,
    progress,
    onClose,
    onAdd,
}: AddPhotosDialogProps) {
    const id = useId();
    const [open, setOpen] = useState(true);
    const [submitting, setSubmitting] = useState(false);
    const [target, setTarget] = useState("");
    const [error, setError] = useState<string | null>(null);
    const destination: PhotoDestination | null = !target
        ? null
        : target === "end"
          ? { kind: "end" }
          : { kind: "page", pageId: target };
    const validationError =
        destination && !submitting
            ? photoDestinationError(pages, destination, photoCount)
            : null;
    const isCover = target === pages[0]?.id;
    const newPageCount = Math.ceil(photoCount / MAX_PAGE_PHOTOS);
    const loading = busy || submitting;
    const close = () => {
        if (!loading) setOpen(false);
    };

    return (
        <Dialog
            open={open}
            onClose={close}
            maxWidth={false}
            aria-labelledby={`${id}-title`}
            aria-busy={loading}
            slotProps={{
                paper: { sx: dialogPaperSx },
                backdrop: { sx: { bgcolor: "rgba(0,0,0,0.5)" } },
                transition: { onExited: onClose },
            }}
        >
            <Box
                component="form"
                sx={{ position: "relative", p: "48px 16px 16px" }}
                onSubmit={async (event) => {
                    event.preventDefault();
                    if (!open || loading || !destination || validationError)
                        return;
                    setSubmitting(true);
                    setError(null);
                    try {
                        await onAdd(destination);
                        setOpen(false);
                    } catch (cause) {
                        setSubmitting(false);
                        setError(
                            cause instanceof Error
                                ? cause.message
                                : "Couldn't add these photos. Please try again.",
                        );
                    }
                }}
            >
                <IconButton
                    type="button"
                    aria-label="Close"
                    onClick={close}
                    disabled={loading}
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
                            color: accentGreen,
                        }}
                    >
                        <AddPhotosIcon sx={{ fontSize: 72 }} />
                    </Box>
                    <Box sx={dialogHeaderSx}>
                        <Typography
                            component="h2"
                            id={`${id}-title`}
                            sx={dialogTitleSx}
                        >
                            {isCover ? "Cover image" : "Add photos"}
                        </Typography>
                    </Box>
                    <Select
                        autoFocus
                        fullWidth
                        displayEmpty
                        inputProps={{ "aria-label": "Add photos to" }}
                        value={target}
                        disabled={loading}
                        renderValue={
                            target === "" ? () => "Choose page" : undefined
                        }
                        onChange={(event) => {
                            setTarget(event.target.value);
                            setError(null);
                        }}
                        sx={dialogSelectSx}
                        MenuProps={dialogSelectMenuProps}
                    >
                        <MenuItem value="end">
                            New {newPageCount === 1 ? "page" : "pages"} at end
                        </MenuItem>
                        {pages.slice(0, -1).map((page, index) => (
                            <MenuItem
                                key={page.id}
                                value={page.id}
                                disabled={
                                    !!photoDestinationError(
                                        pages,
                                        { kind: "page", pageId: page.id },
                                        photoCount,
                                    )
                                }
                            >
                                {index === 0 ? "Front cover" : `Page ${index}`}
                            </MenuItem>
                        ))}
                    </Select>
                    {(error || validationError) && (
                        <Typography
                            role="alert"
                            sx={{
                                color: uiColors.danger,
                                fontSize: 13,
                                textAlign: "center",
                            }}
                        >
                            {error || validationError}
                        </Typography>
                    )}
                    <Button
                        type="submit"
                        variant="contained"
                        fullWidth
                        disableElevation
                        disabled={loading || !destination || !!validationError}
                        sx={{
                            ...dialogActionSx,
                            color: "#FFFFFF",
                            bgcolor: accentGreen,
                            "&:hover": { bgcolor: accentGreenHover },
                        }}
                    >
                        {loading
                            ? `Adding photos… ${progress}%`
                            : isCover
                              ? "Use as cover"
                              : `Add ${photoCount} photo${photoCount === 1 ? "" : "s"}`}
                    </Button>
                </Box>
            </Box>
        </Dialog>
    );
}
