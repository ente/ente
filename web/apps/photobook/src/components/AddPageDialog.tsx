import { canInsertPage, MAX_PRINT_PAGES } from "@/lib/printProducts";
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
    onInsert: (
        pageIndex: number,
        position: PageInsertPosition,
        count: number,
    ) => void;
}

function FittedSelectValue({
    value,
    options,
}: {
    value: string;
    options: string[];
}) {
    return (
        <Box
            component="span"
            sx={{ display: "inline-grid", whiteSpace: "nowrap" }}
        >
            {options.map((option) => (
                <Box
                    component="span"
                    key={option}
                    aria-hidden="true"
                    sx={{ gridArea: "1 / 1", visibility: "hidden" }}
                >
                    {option}
                </Box>
            ))}
            <Box component="span" sx={{ gridArea: "1 / 1" }}>
                {value}
            </Box>
        </Box>
    );
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
    const [count, setCount] = useState(1);
    const [insertion, setInsertion] = useState<{
        pageIndex: number;
        position: PageInsertPosition;
        count: number;
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
    const remainingPages = Math.max(0, MAX_PRINT_PAGES - pages.length);
    const canInsert =
        !disabled && canInsertPage(pages.length, count) && !!targetPage;
    const countOptions = Array.from({ length: remainingPages }, (_, i) => ({
        value: i + 1,
        label: `${i + 1} ${i === 0 ? "page" : "pages"}`,
    }));
    const pageOptions = pages
        .slice(firstAllowedIndex, lastAllowedIndex + 1)
        .map((page, i) => ({
            value: page.id,
            label:
                i + firstAllowedIndex === 0
                    ? "Front cover"
                    : i + firstAllowedIndex === lastIndex
                      ? "Back cover"
                      : `Page ${i + firstAllowedIndex}`,
        }));

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
                        if (insertion && canInsert)
                            onInsert(
                                insertion.pageIndex,
                                insertion.position,
                                insertion.count,
                            );
                    },
                },
            }}
        >
            <Box
                component="form"
                onSubmit={(event) => {
                    event.preventDefault();
                    if (!open || !canInsert) return;
                    setInsertion({ pageIndex, position, count });
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
                            Add pages
                        </Typography>
                        <Typography
                            id={`${id}-description`}
                            sx={dialogDescriptionSx}
                        >
                            Choose how many pages to add and where.
                        </Typography>
                    </Box>
                    <Box
                        sx={{
                            display: "grid",
                            gridTemplateColumns: "repeat(3, max-content)",
                            justifyContent: "center",
                            gap: "8px",
                            width: "100%",
                        }}
                    >
                        <Select
                            autoFocus
                            inputProps={{ "aria-label": "Number of pages" }}
                            SelectDisplayProps={{ style: { paddingRight: 36 } }}
                            value={count}
                            renderValue={(value) => (
                                <FittedSelectValue
                                    value={`${value} ${value === 1 ? "page" : "pages"}`}
                                    options={countOptions.map(
                                        ({ label }) => label,
                                    )}
                                />
                            )}
                            onChange={(event) => setCount(event.target.value)}
                            disabled={disabled || remainingPages === 0}
                            sx={{ ...dialogSelectSx, minWidth: 0 }}
                            MenuProps={dialogSelectMenuProps}
                        >
                            {countOptions.map(({ value, label }) => (
                                <MenuItem key={value} value={value}>
                                    {label}
                                </MenuItem>
                            ))}
                        </Select>
                        <Box
                            sx={{
                                display: "flex",
                                flexDirection: "column",
                                gap: "8px",
                                minWidth: 0,
                            }}
                        >
                            <Select
                                inputProps={{ "aria-label": "Insert position" }}
                                value={position}
                                renderValue={(value) => (
                                    <FittedSelectValue
                                        value={
                                            value === "before"
                                                ? "Before"
                                                : "After"
                                        }
                                        options={["Before", "After"]}
                                    />
                                )}
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
                                renderValue={(value) => (
                                    <FittedSelectValue
                                        value={
                                            pageOptions.find(
                                                (option) =>
                                                    option.value === value,
                                            )?.label ?? ""
                                        }
                                        options={pageOptions.map(
                                            ({ label }) => label,
                                        )}
                                    />
                                )}
                                onChange={(event) =>
                                    setPageId(event.target.value)
                                }
                                disabled={!canInsert}
                                sx={dialogSelectSx}
                                MenuProps={dialogSelectMenuProps}
                            >
                                {pageOptions.map(({ value, label }) => (
                                    <MenuItem key={value} value={value}>
                                        {label}
                                    </MenuItem>
                                ))}
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
                            Add {count} {count === 1 ? "page" : "pages"}
                        </Button>
                    </Box>
                </Box>
            </Box>
        </Dialog>
    );
}
