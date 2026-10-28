"use client";

import { popupShadow, toolbarColors, uiColors } from "@/theme/colors";

import { useBook } from "@/context/book";
import { useSpreads } from "@/hooks/useSpreads";
import { normalizeBookPages } from "@/lib/bookPages";
import { downloadBlob, exportPdfX4Pages } from "@/lib/export";
import {
    getBindingPrintSelection,
    getPrintBinding,
    getPrintExportError,
    PrintExportValidationError,
} from "@/lib/printProducts";
import { getSpreadLabel } from "@/lib/spreads";
import { headerButtonSx } from "@/theme/buttons";
import {
    Alert,
    Box,
    Button,
    CircularProgress,
    Dialog,
    LinearProgress,
    Snackbar,
    Typography,
} from "@mui/material";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import BookBindingSelect from "./BookBindingSelect";
import BookHeader from "./BookHeader";
import BookViewer, { type BookViewerHandle } from "./BookViewer";
import {
    EDITOR_PANEL_BOTTOM_INSET,
    EDITOR_PANEL_INSET,
    EDITOR_PANEL_SX,
} from "./editorLayout";
import { DownloadIcon, EditIcon } from "./icons";

export default function ResultsPage() {
    const { book, photos, setAppView, waitForEnteOriginals } = useBook();
    const viewerRef = useRef<BookViewerHandle>(null);
    const [spreadIndex, setSpreadIndex] = useState(0);
    const [downloadPhase, setDownloadPhase] = useState<
        "idle" | "originals" | "exporting"
    >("idle");
    const downloadInProgress = useRef(false);
    const [exportProgress, setExportProgress] = useState(0);
    const [exportError, setExportError] = useState<string | null>(null);
    const waitingForOriginals = downloadPhase === "originals";
    const [originalsProgress, setOriginalsProgress] = useState({
        done: 0,
        total: 0,
    });
    const pages = book.pages;
    const binding = getPrintBinding(book.printSelection);
    const printSelection = useMemo(
        () => getBindingPrintSelection(binding),
        [binding],
    );
    const exportPages = useMemo(() => normalizeBookPages(pages), [pages]);
    const busy = downloadPhase !== "idle";
    const totalPages = pages.length;
    const spreads = useSpreads(totalPages);
    const photosRef = useRef(photos);
    photosRef.current = photos;

    const pageLabel = getSpreadLabel(spreads[spreadIndex], totalPages);
    const isAtStart = spreadIndex === 0;
    const isAtEnd = spreadIndex >= spreads.length - 1;

    const usedPhotoIds = useMemo(() => {
        const ids = new Set<string>();
        for (const page of pages) {
            for (const slot of page.slots) {
                if (slot.photoId) {
                    ids.add(slot.photoId);
                }
            }
        }
        return ids;
    }, [pages]);

    const handleSpreadChange = useCallback((idx: number) => {
        setSpreadIndex(idx);
    }, []);

    const getBlockedEntePhotos = useCallback(() => {
        return photosRef.current.filter(
            (photo) =>
                usedPhotoIds.has(photo.id) &&
                photo.source === "ente" &&
                photo.originalStatus !== "ready",
        );
    }, [usedPhotoIds]);

    // Keyboard navigation: left/right arrows flip pages
    useEffect(() => {
        const handleKeyDown = (e: KeyboardEvent) => {
            if (e.defaultPrevented) return;
            // Ignore if the user is typing into an input/textarea or a menu is open
            const target = e.target as HTMLElement | null;
            if (
                target &&
                (target.tagName === "INPUT" ||
                    target.tagName === "TEXTAREA" ||
                    target.isContentEditable ||
                    target.closest(
                        '[role="combobox"], [role="listbox"], [role="option"]',
                    ))
            ) {
                return;
            }
            if (e.key === "ArrowLeft" && !isAtStart) {
                e.preventDefault();
                viewerRef.current?.flipPrev();
            } else if (e.key === "ArrowRight" && !isAtEnd) {
                e.preventDefault();
                viewerRef.current?.flipNext();
            }
        };
        window.addEventListener("keydown", handleKeyDown);
        return () => window.removeEventListener("keydown", handleKeyDown);
    }, [isAtStart, isAtEnd]);

    const handleExport = useCallback(async () => {
        if (downloadInProgress.current) return;
        const validationError = getPrintExportError(
            printSelection,
            exportPages.length,
        );
        if (validationError) {
            setExportError(validationError);
            return;
        }

        const initiallyBlocked = getBlockedEntePhotos();
        const pendingIds = initiallyBlocked
            .filter((photo) => photo.originalStatus === "pending")
            .map((photo) => photo.id);

        downloadInProgress.current = true;
        setExportError(null);
        setExportProgress(0);
        setDownloadPhase(pendingIds.length > 0 ? "originals" : "exporting");
        const preparationShare = pendingIds.length > 0 ? 10 : 0;

        try {
            if (pendingIds.length > 0) {
                setOriginalsProgress({ done: 0, total: pendingIds.length });
                await waitForEnteOriginals(pendingIds, (done, total) => {
                    setOriginalsProgress({ done, total });
                    setExportProgress(
                        total
                            ? Math.round((done / total) * preparationShare)
                            : 0,
                    );
                });
            }

            const remainingBlocked = getBlockedEntePhotos();
            if (remainingBlocked.length > 0) {
                const failedCount = remainingBlocked.filter(
                    (photo) => photo.originalStatus === "failed",
                ).length;
                setExportError(
                    failedCount > 0
                        ? "Some Ente photos failed to prepare. Re-import the album before exporting."
                        : "Ente originals are still being prepared. Please wait a moment and try again.",
                );
                return;
            }

            setDownloadPhase("exporting");
            // Paint the persistent spinner before starting the canvas/WASM work.
            await new Promise<void>((resolve) =>
                requestAnimationFrame(() => setTimeout(resolve, 0)),
            );
            const blob = await exportPdfX4Pages(
                exportPages,
                printSelection,
                (progress) => {
                    setExportProgress(
                        preparationShare +
                            Math.round(
                                (progress * (100 - preparationShare)) / 100,
                            ),
                    );
                },
            );
            const filename = `photobook-${printSelection.sizeMm}mm.pdf`;

            downloadBlob(blob, filename);
        } catch (e) {
            console.error("Export failed:", e);
            setExportError(
                e instanceof PrintExportValidationError
                    ? e.message
                    : "Export failed. Please try again.",
            );
        } finally {
            downloadInProgress.current = false;
            setDownloadPhase("idle");
        }
    }, [
        getBlockedEntePhotos,
        exportPages,
        printSelection,
        waitForEnteOriginals,
    ]);

    return (
        <Box
            sx={{
                height: "100dvh",
                display: "flex",
                flexDirection: "column",
                px: EDITOR_PANEL_INSET,
                bgcolor: uiColors.background,
            }}
        >
            <BookHeader>
                <BookBindingSelect disabled={busy} />
                <Button
                    aria-label="Edit"
                    startIcon={<EditIcon />}
                    onClick={() => setAppView("edit")}
                    disabled={busy}
                    sx={{
                        ...headerButtonSx,
                        color: toolbarColors.text,
                        bgcolor: toolbarColors.control,
                        "&:hover": { bgcolor: toolbarColors.hover },
                        "&:active": { bgcolor: toolbarColors.active },
                    }}
                >
                    <Box
                        component="span"
                        sx={{ display: { xs: "none", sm: "inline" } }}
                    >
                        Edit
                    </Box>
                </Button>
                <Button
                    id="download-button"
                    variant="contained"
                    aria-label={
                        busy ? `Downloading, ${exportProgress}%` : "Download"
                    }
                    aria-busy={busy}
                    startIcon={
                        <Box
                            component="span"
                            sx={{
                                display: "grid",
                                width: 18,
                                height: 18,
                                flexShrink: 0,
                            }}
                        >
                            <DownloadIcon
                                strokeWidth={2.2}
                                sx={{
                                    gridArea: "1 / 1",
                                    visibility: busy ? "hidden" : "visible",
                                }}
                            />
                            <CircularProgress
                                disableShrink
                                size={18}
                                thickness={4}
                                color="inherit"
                                aria-hidden="true"
                                sx={{
                                    gridArea: "1 / 1",
                                    visibility: busy ? "visible" : "hidden",
                                    willChange: "transform",
                                    "& circle": { strokeLinecap: "round" },
                                }}
                            />
                        </Box>
                    }
                    disabled={busy || pages.length === 0}
                    onClick={handleExport}
                    sx={{
                        ...headerButtonSx,
                        fontWeight: 700,
                        gap: { xs: busy ? "6px" : 0, sm: "8px" },
                        ...(busy && { "&.Mui-disabled": { opacity: 1 } }),
                    }}
                >
                    <Box
                        component="span"
                        sx={{ display: { xs: "none", sm: "inline" } }}
                    >
                        {busy ? "Downloading" : "Download"}
                    </Box>
                    {busy && (
                        <Box
                            component="span"
                            sx={{
                                display: "inline-flex",
                                justifyContent: "center",
                                alignItems: "center",
                                flexShrink: 0,
                                width: "4.5ch",
                                py: 0.5,
                                borderRadius: "7px",
                                bgcolor: "rgba(0,0,0,0.12)",
                                fontSize: 12,
                                lineHeight: "16px",
                                fontWeight: 600,
                                fontVariantNumeric: "tabular-nums",
                            }}
                        >
                            {exportProgress}%
                        </Box>
                    )}
                </Button>
            </BookHeader>

            <Box
                component="main"
                aria-label={`Photobook preview: ${pageLabel}`}
                sx={{
                    ...EDITOR_PANEL_SX,
                    flex: 1,
                    minHeight: 0,
                    mb: EDITOR_PANEL_BOTTOM_INSET,
                    borderRadius: "20px",
                    display: "flex",
                    position: "relative",
                    overflow: "hidden",
                    px: { xs: 1, sm: 4 },
                }}
            >
                <BookViewer
                    ref={viewerRef}
                    pages={pages}
                    onSpreadChange={handleSpreadChange}
                />
            </Box>

            <Dialog
                open={waitingForOriginals}
                slotProps={{
                    backdrop: { sx: { bgcolor: "rgba(0,0,0,0.25)" } },
                    paper: {
                        sx: {
                            borderRadius: 3,
                            bgcolor: uiColors.surface,
                            minWidth: 360,
                            boxShadow: popupShadow,
                        },
                    },
                }}
            >
                <Box sx={{ textAlign: "center", px: 3.5, py: 3.5 }}>
                    <CircularProgress
                        sx={{ color: "#08C225", mb: 2 }}
                        size={36}
                    />
                    <Typography
                        sx={{
                            fontFamily: "var(--font-inter), sans-serif",
                            fontWeight: 700,
                            fontSize: "1.05rem",
                            color: uiColors.text,
                            mb: 0.5,
                        }}
                    >
                        Finishing your album download
                    </Typography>
                    <Typography
                        sx={{
                            fontFamily: "var(--font-inter), sans-serif",
                            color: uiColors.muted,
                            fontSize: "0.8rem",
                            lineHeight: 1.6,
                            mb: 2.5,
                        }}
                    >
                        We need the full-resolution photos before we can build a
                        print-ready file.
                    </Typography>
                    <LinearProgress
                        variant="determinate"
                        value={
                            originalsProgress.total
                                ? (originalsProgress.done /
                                      originalsProgress.total) *
                                  100
                                : 0
                        }
                        sx={{
                            height: 6,
                            borderRadius: 3,
                            mb: 1,
                            bgcolor: uiColors.control,
                            "& .MuiLinearProgress-bar": {
                                background: "#08C225",
                                borderRadius: 3,
                            },
                        }}
                    />
                    <Typography
                        sx={{
                            fontFamily: "var(--font-inter), sans-serif",
                            color: uiColors.muted,
                            fontSize: "0.8rem",
                        }}
                    >
                        {originalsProgress.done} / {originalsProgress.total}{" "}
                        photos
                    </Typography>
                </Box>
            </Dialog>

            <Snackbar
                open={Boolean(exportError)}
                autoHideDuration={6000}
                onClose={() => setExportError(null)}
                anchorOrigin={{ vertical: "bottom", horizontal: "center" }}
            >
                <Alert
                    onClose={() => setExportError(null)}
                    severity="error"
                    variant="filled"
                >
                    {exportError}
                </Alert>
            </Snackbar>
        </Box>
    );
}
