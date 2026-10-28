"use client";

import type { BookPage } from "@/lib/types";
import { accentGreen, accentGreenHover } from "@/theme/buttons";
import {
    dialogActionSx,
    dialogCloseButtonSx,
    dialogDescriptionSx,
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
import { AddPageIcon, CloseIcon } from "./icons";
import type { PageInsertPosition } from "./PageMenu";

interface AddPageDialogProps {
    pages: BookPage[];
    initialPageId?: string;
    disabled: boolean;
    onClose: () => void;
    onInsert: (pageIndex: number, position: PageInsertPosition) => void;
}

export default function AddPageDialog({
    pages,
    initialPageId,
    disabled,
    onClose,
    onInsert,
}: AddPageDialogProps) {
    const id = useId();
    const [open, setOpen] = useState(true);
    const [insertion, setInsertion] = useState<{
        pageIndex: number;
        position: PageInsertPosition;
    } | null>(null);
    const [pageId, setPageId] = useState(
        initialPageId ?? pages.at(0)?.id ?? "",
    );
    const [position, setPosition] = useState<PageInsertPosition>(() =>
        pages.length >= 2 && initialPageId === pages.at(-1)?.id
            ? "before"
            : "after",
    );
    const lastIndex = pages.length - 1;
    const firstAllowedIndex = position === "before" ? 1 : 0;
    const lastAllowedIndex = position === "after" ? lastIndex - 1 : lastIndex;
    const pageIndex = Math.min(
        lastAllowedIndex,
        Math.max(
            firstAllowedIndex,
            pages.findIndex((page) => page.id === pageId),
        ),
    );
    const targetPage = pages.at(pageIndex);
    const canInsert = !disabled && pages.length >= 2 && !!targetPage;

    return (
        <Dialog
            open={open}
            onClose={() => setOpen(false)}
            maxWidth={false}
            aria-labelledby={`${id}-title`}
            aria-describedby={`${id}-description`}
            slotProps={{
                paper: { sx: dialogPaperSx },
                backdrop: { sx: { bgcolor: "rgba(0,0,0,0.5)" } },
                transition: {
                    onExited: () => {
                        onClose();
                        if (insertion)
                            onInsert(insertion.pageIndex, insertion.position);
                    },
                },
            }}
        >
            <Box
                component="form"
                onSubmit={(event) => {
                    event.preventDefault();
                    if (!open || !canInsert) return;
                    setInsertion({ pageIndex, position });
                    setOpen(false);
                }}
                sx={{ position: "relative", p: "48px 16px 16px" }}
            >
                <IconButton
                    type="button"
                    aria-label="Close"
                    onClick={() => setOpen(false)}
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
                        <AddPageIcon sx={{ fontSize: 72 }} />
                    </Box>
                    <Box sx={dialogHeaderSx}>
                        <Typography
                            component="h2"
                            id={`${id}-title`}
                            sx={dialogTitleSx}
                        >
                            Add page
                        </Typography>
                        <Typography
                            id={`${id}-description`}
                            sx={dialogDescriptionSx}
                        >
                            Choose where to add a blank page.
                        </Typography>
                    </Box>
                    <Box
                        sx={{
                            display: "grid",
                            gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
                            gap: "12px",
                            width: "100%",
                        }}
                    >
                        <Box
                            sx={{
                                display: "flex",
                                flexDirection: "column",
                                gap: "8px",
                                minWidth: 0,
                            }}
                        >
                            <Select
                                autoFocus
                                inputProps={{ "aria-label": "Insert position" }}
                                value={position}
                                onChange={(event) => {
                                    const nextPosition = event.target.value;
                                    const nextIndex =
                                        nextPosition === "before"
                                            ? Math.max(1, pageIndex)
                                            : Math.min(
                                                  lastIndex - 1,
                                                  pageIndex,
                                              );
                                    setPosition(nextPosition);
                                    setPageId(pages[nextIndex]?.id ?? "");
                                }}
                                disabled={!canInsert}
                                sx={dialogSelectSx}
                                MenuProps={dialogSelectMenuProps}
                            >
                                <MenuItem value="before">Before</MenuItem>
                                <MenuItem value="after">After</MenuItem>
                            </Select>
                        </Box>
                        <Box
                            sx={{
                                display: "flex",
                                flexDirection: "column",
                                gap: "8px",
                                minWidth: 0,
                            }}
                        >
                            <Select
                                inputProps={{ "aria-label": "Page" }}
                                value={targetPage?.id ?? ""}
                                onChange={(event) =>
                                    setPageId(event.target.value)
                                }
                                disabled={!canInsert}
                                sx={dialogSelectSx}
                                MenuProps={dialogSelectMenuProps}
                            >
                                {pages.map((page, index) =>
                                    index < firstAllowedIndex ||
                                    index > lastAllowedIndex ? null : (
                                        <MenuItem key={page.id} value={page.id}>
                                            {index === 0
                                                ? "Front cover"
                                                : index === lastIndex
                                                  ? "Back cover"
                                                  : `Page ${index}`}
                                        </MenuItem>
                                    ),
                                )}
                            </Select>
                        </Box>
                    </Box>
                    <Box
                        sx={{
                            display: "flex",
                            flexDirection: "column",
                            gap: "12px",
                            width: "100%",
                        }}
                    >
                        <Button
                            type="submit"
                            variant="contained"
                            fullWidth
                            disableElevation
                            disabled={!canInsert}
                            sx={{
                                ...dialogActionSx,
                                color: "#FFFFFF",
                                bgcolor: accentGreen,
                                "&:hover": { bgcolor: accentGreenHover },
                            }}
                        >
                            Add page
                        </Button>
                    </Box>
                </Box>
            </Box>
        </Dialog>
    );
}
