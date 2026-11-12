import { useBook } from "@/context/book";
import { useSpreads } from "@/hooks/useSpreads";
import { normalizeBookPages } from "@/lib/bookPages";
import { exportPdfX4Pages } from "@/lib/export";
import {
    getBindingPrintSelection,
    getPrintBinding,
    getPrintExportError,
    PrintExportValidationError,
} from "@/lib/printProducts";
import { getSpreadLabel } from "@/lib/spreads";
import { editorButtonSx, headerButtonSx } from "@/theme/buttons";
import { popupShadow, toolbarColors, uiColors } from "@/theme/colors";
import {
    Alert,
    Box,
    Button,
    CircularProgress,
    Dialog,
    LinearProgress,
    Snackbar,
    Typography,
    useMediaQuery,
} from "@mui/material";
import { saveAsFileAndRevokeObjectURL } from "ente-base/utils/web";
import { memo, useCallback, useEffect, useMemo, useRef, useState } from "react";
import BookBindingSelect from "./BookBindingSelect";
import BookHeader from "./BookHeader";
import BookSidebar from "./BookSidebar";
import BookTitleInput from "./BookTitleInput";
import BookViewer, { type BookViewerHandle } from "./BookViewer";
import DesktopEditingDialog from "./DesktopEditingDialog";
import {
    EDITOR_HEADER_HEIGHT,
    EDITOR_PANEL_BOTTOM_INSET,
    EDITOR_PANEL_INSET,
    EDITOR_PANEL_SX,
    MOBILE_QUERY,
} from "./editorLayout";
import { DownloadIcon, EditIcon } from "./icons";
import PrintValidationDialog, {
    type PrintValidation,
} from "./PrintValidationDialog";
import ResetBookButton from "./ResetBookButton";

function ResultsPage({
    sidebarOpen,
    onToggleSidebar,
}: {
    sidebarOpen: boolean;
    onToggleSidebar: () => void;
}) {
    const mobile = useMediaQuery(MOBILE_QUERY, { noSsr: true });
    const { book, photos, setAppView, waitForEnteOriginals } = useBook(
        "book",
        "photos",
        "setAppView",
        "waitForEnteOriginals",
    );
    const viewerRef = useRef<BookViewerHandle>(null);
    const [spreadIndex, setSpreadIndex] = useState(0);
    const [desktopEditingOpen, setDesktopEditingOpen] = useState(false);
    const [downloadPhase, setDownloadPhase] = useState<
        "idle" | "originals" | "exporting"
    >("idle");
    const downloadInProgress = useRef(false);
    const [exportProgress, setExportProgress] = useState(0);
    const [exportError, setExportError] = useState<string | null>(null);
    const [printValidation, setPrintValidation] =
        useState<PrintValidation | null>(null);
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

    useEffect(() => {
        const handleKeyDown = (e: KeyboardEvent) => {
            if (e.defaultPrevented) return;
            const target = e.target as HTMLElement | null;
            if (
                target &&
                (target.tagName === "INPUT" ||
                    target.tagName === "TEXTAREA" ||
                    target.isContentEditable ||
                    target.closest(
                        '[role="dialog"], [role="combobox"], [role="listbox"], [role="option"]',
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
            setPrintValidation({
                selection: printSelection,
                pageCount: exportPages.length,
                error: validationError,
            });
            return;
        }

        const pendingIds = getBlockedEntePhotos().map((photo) => photo.id);

        downloadInProgress.current = true;
        setExportError(null);
        setExportProgress(0);
        setDownloadPhase(pendingIds.length > 0 ? "originals" : "exporting");
        const preparationShare = pendingIds.length > 0 ? 10 : 0;

        try {
            if (pendingIds.length > 0) {
                setOriginalsProgress({ done: 0, total: pendingIds.length });
                const ready = await waitForEnteOriginals(
                    pendingIds,
                    (done, total) => {
                        setOriginalsProgress({ done, total });
                        setExportProgress(
                            total
                                ? Math.round((done / total) * preparationShare)
                                : 0,
                        );
                    },
                );
                if (!ready) {
                    setExportError(
                        "Some photos couldn't download. Click Download to try again. Your edits are unchanged.",
                    );
                    return;
                }
            }

            setDownloadPhase("exporting");
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

            saveAsFileAndRevokeObjectURL(URL.createObjectURL(blob), filename);
        } catch (e) {
            console.error("Export failed:", e);
            if (e instanceof PrintExportValidationError) {
                setPrintValidation({
                    selection: printSelection,
                    pageCount: exportPages.length,
                    error: e.message,
                });
            } else {
                setExportError("Export failed. Please try again.");
            }
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

    const actions = (
        <>
            <Button
                aria-label="Edit"
                startIcon={<EditIcon />}
                onClick={() =>
                    mobile ? setDesktopEditingOpen(true) : setAppView("edit")
                }
                disabled={busy}
                sx={{
                    ...(mobile ? editorButtonSx : headerButtonSx),
                    color: toolbarColors.text,
                    bgcolor: toolbarColors.control,
                    "&:hover": { bgcolor: toolbarColors.hover },
                    "&:active": { bgcolor: toolbarColors.active },
                    "&.Mui-disabled": {
                        color: toolbarColors.disabled,
                        bgcolor: toolbarColors.control,
                        opacity: 1,
                    },
                }}
            >
                Edit
            </Button>
            {mobile && <ResetBookButton disabled={busy} />}
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
                            placeItems: "center",
                            width: 20,
                            height: 20,
                            flexShrink: 0,
                        }}
                    >
                        <DownloadIcon
                            sx={{
                                gridArea: "1 / 1",
                                fontSize: 20,
                                visibility: busy ? "hidden" : "visible",
                            }}
                        />
                        <CircularProgress
                            disableShrink
                            size={mobile ? 16 : 20}
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
                    ...(mobile ? editorButtonSx : headerButtonSx),
                    ...(mobile && { ml: "auto", gap: busy ? 0.5 : 0 }),
                    ...(busy && { "&.Mui-disabled": { opacity: 1 } }),
                }}
            >
                <Box
                    component="span"
                    sx={{ display: mobile && busy ? "none" : "inline" }}
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
        </>
    );

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
            {mobile ? (
                <Box
                    component="header"
                    sx={{
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "space-between",
                        minHeight: EDITOR_HEADER_HEIGHT,
                        px: 1,
                        gap: 1,
                        flexShrink: 0,
                    }}
                >
                    <BookTitleInput disabled={busy} />
                    <BookBindingSelect disabled={busy} />
                </Box>
            ) : (
                <BookHeader
                    showBindingSelect
                    titleDisabled={busy}
                    sidebarOpen={sidebarOpen}
                    onToggleSidebar={onToggleSidebar}
                >
                    {actions}
                </BookHeader>
            )}

            <Box
                sx={{
                    display: "flex",
                    flex: 1,
                    minHeight: 0,
                    gap: EDITOR_PANEL_INSET,
                    mb: mobile ? 0 : EDITOR_PANEL_BOTTOM_INSET,
                }}
            >
                {!mobile && sidebarOpen && (
                    <BookSidebar
                        readOnly
                        onSpreadClick={(index) =>
                            viewerRef.current?.goToSpread(index)
                        }
                    />
                )}
                <Box
                    component="main"
                    aria-label={`Photobook preview: ${pageLabel}`}
                    sx={{
                        ...EDITOR_PANEL_SX,
                        ...(mobile && { bgcolor: "transparent" }),
                        flex: 1,
                        minWidth: 0,
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
            </Box>

            {mobile && (
                <Box
                    component="footer"
                    aria-label="Photobook actions"
                    sx={{
                        display: "flex",
                        alignItems: "center",
                        gap: 0.5,
                        px: 1,
                        pt: 1,
                        pb: "max(16px, env(safe-area-inset-bottom))",
                        flexShrink: 0,
                    }}
                >
                    {actions}
                </Box>
            )}

            <DesktopEditingDialog
                open={mobile && desktopEditingOpen}
                onClose={() => setDesktopEditingOpen(false)}
            />

            {printValidation && (
                <PrintValidationDialog
                    validation={printValidation}
                    onClose={() => setPrintValidation(null)}
                />
            )}

            <Dialog
                open={waitingForOriginals}
                slotProps={{
                    backdrop: { sx: { bgcolor: "rgba(0,0,0,0.25)" } },
                    paper: {
                        sx: {
                            borderRadius: 3,
                            bgcolor: uiColors.surface,
                            minWidth: 360,
                            "@media (max-width: 959px)": {
                                minWidth: 0,
                                width: 360,
                                maxWidth: "calc(100% - 32px)",
                            },
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

export default memo(ResultsPage);
