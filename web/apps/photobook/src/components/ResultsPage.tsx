import { useBook } from "@/context/book";
import { useSpineTitlePrompt } from "@/hooks/useSpineTitlePrompt";
import { useSpreads } from "@/hooks/useSpreads";
import { normalizeBookPages } from "@/lib/bookPages";
import {
    createCheckout,
    uploadBook,
    UploadSessionExpiredError,
    type DeliveryDestination,
    type UploadedBook,
} from "@/lib/checkout";
import { exportPdfX4Pages } from "@/lib/export";
import {
    getBindingPrintSelection,
    getPrintBinding,
    getPrintExportError,
    PrintExportValidationError,
    type PrintBinding,
    type PrintSelection,
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
    Link,
    Snackbar,
    Typography,
    useMediaQuery,
} from "@mui/material";
import { isDevBuild } from "ente-base/env";
import { saveAsFileAndRevokeObjectURL } from "ente-base/utils/web";
import { memo, useCallback, useEffect, useMemo, useRef, useState } from "react";
import BookBindingSelect from "./BookBindingSelect";
import BookHeader from "./BookHeader";
import BookSidebar from "./BookSidebar";
import BookTitleInput from "./BookTitleInput";
import BookViewer, { type BookViewerHandle } from "./BookViewer";
import CheckoutDialog from "./CheckoutDialog";
import type { CheckoutProgress } from "./CheckoutProgressContent";
import CoverTypeDialog from "./CoverTypeDialog";
import DesktopEditingDialog from "./DesktopEditingDialog";
import {
    EDITOR_HEADER_HEIGHT,
    EDITOR_PANEL_BOTTOM_INSET,
    EDITOR_PANEL_INSET,
    EDITOR_PANEL_SX,
    MOBILE_QUERY,
} from "./editorLayout";
import { ArrowRightIcon, DownloadIcon, EditIcon } from "./icons";
import PrintValidationDialog, {
    type PrintValidation,
} from "./PrintValidationDialog";
import ResetBookButton from "./ResetBookButton";

type BookAction = "download" | "checkout";

function ResultsPage({
    sidebarOpen,
    onToggleSidebar,
}: {
    sidebarOpen: boolean;
    onToggleSidebar: () => void;
}) {
    const mobile = useMediaQuery(MOBILE_QUERY, { noSsr: true });
    const { book, photos, setBook, setAppView, waitForEnteOriginals } = useBook(
        "book",
        "photos",
        "setBook",
        "setAppView",
        "waitForEnteOriginals",
    );
    const viewerRef = useRef<BookViewerHandle>(null);
    const [spreadIndex, setSpreadIndex] = useState(0);
    const [desktopEditingOpen, setDesktopEditingOpen] = useState(false);
    const [checkoutProgress, setCheckoutProgress] =
        useState<CheckoutProgress>();
    const checkoutAttempt = useRef<{
        pages: typeof book.pages;
        cover: PrintBinding;
        title: string;
        pdf?: Blob;
        uploaded?: UploadedBook;
    } | null>(null);
    const [pendingCoverAction, setPendingCoverAction] = useState<BookAction>();
    const [deliveryBook, setDeliveryBook] = useState<{
        cover: PrintBinding;
        title: string;
    }>();
    const actionInProgress = useRef(false);
    const [exportProgress, setExportProgress] = useState<number | null>(null);
    const [exportError, setExportError] = useState<string | null>(null);
    const [originalsProgress, setOriginalsProgress] = useState({
        done: 0,
        total: 0,
    });
    const busy = exportProgress !== null || !!checkoutProgress;
    const waitingForOriginals = originalsProgress.total > 0;
    const { withSpineTitle, spineTitleDialog } = useSpineTitlePrompt();
    const [printValidation, setPrintValidation] =
        useState<PrintValidation | null>(null);
    const pages = book.pages;
    const binding = getPrintBinding(book.printSelection);
    const exportPages = useMemo(() => normalizeBookPages(pages), [pages]);
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

    useEffect(() => {
        const onPageShow = (event: PageTransitionEvent) => {
            if (event.persisted && checkoutProgress?.stage === "opening") {
                setDeliveryBook(undefined);
                setCheckoutProgress(undefined);
            }
        };
        window.addEventListener("pageshow", onPageShow);
        return () => window.removeEventListener("pageshow", onPageShow);
    }, [checkoutProgress?.stage]);

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

    const continueWithCover = (
        action: BookAction,
        cover: PrintBinding,
        title: string,
    ) => {
        const printSelection = getBindingPrintSelection(cover);
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
        if (action === "checkout") setDeliveryBook({ cover, title });
        else void downloadPdf(printSelection);
    };

    const requestBook = (action: BookAction) => {
        if (binding)
            withSpineTitle((title) =>
                continueWithCover(action, binding, title),
            );
        else setPendingCoverAction(action);
    };

    const preparePdf = async (
        printSelection: PrintSelection,
        onProgress: (progress: number) => void,
        onOriginalsProgress?: (progress: {
            done: number;
            total: number;
        }) => void,
    ) => {
        const pendingIds = getBlockedEntePhotos().map((photo) => photo.id);

        const downloadShare = Math.min(
            75,
            Math.round(
                (100 * pendingIds.length) /
                    (pendingIds.length + exportPages.length),
            ),
        );

        if (pendingIds.length > 0) {
            onOriginalsProgress?.({ done: 0, total: pendingIds.length });
            const ready = await waitForEnteOriginals(
                pendingIds,
                (done, total) => {
                    onOriginalsProgress?.({ done, total });
                    onProgress(
                        total ? Math.round((done / total) * downloadShare) : 0,
                    );
                },
            );
            onOriginalsProgress?.({ done: 0, total: 0 });
            if (!ready) return null;
        }

        await new Promise<void>((resolve) =>
            requestAnimationFrame(() => setTimeout(resolve, 0)),
        );
        return exportPdfX4Pages(exportPages, printSelection, (progress) => {
            onProgress(
                downloadShare +
                    Math.round((progress * (100 - downloadShare)) / 100),
            );
        });
    };

    const startCheckout = async (
        cover: PrintBinding,
        title: string,
        destination: DeliveryDestination,
    ) => {
        if (actionInProgress.current) return;
        actionInProgress.current = true;
        setExportError(null);
        let attempt = checkoutAttempt.current;
        if (
            attempt?.pages !== pages ||
            attempt.cover !== cover ||
            attempt.title !== title
        ) {
            attempt = { pages, cover, title };
            checkoutAttempt.current = attempt;
        }
        try {
            if (!attempt.uploaded) {
                if (!attempt.pdf) {
                    setCheckoutProgress({ stage: "preparing", percent: 0 });
                    const pdf = await preparePdf(
                        getBindingPrintSelection(cover),
                        (percent) =>
                            setCheckoutProgress({
                                stage: "preparing",
                                percent,
                            }),
                    );
                    if (!pdf)
                        throw new Error(
                            "Some photos couldn’t download. Please try again.",
                        );
                    attempt.pdf = pdf;
                }
                setCheckoutProgress({ stage: "uploading", percent: 0 });
                attempt.uploaded = await uploadBook(
                    attempt.pdf,
                    { binding: cover, pages: exportPages.length, title },
                    (percent) =>
                        setCheckoutProgress({ stage: "uploading", percent }),
                );
                delete attempt.pdf;
            }
            setCheckoutProgress({ stage: "opening" });
            window.location.assign(
                await createCheckout(attempt.uploaded, destination),
            );
        } catch (error) {
            if (error instanceof UploadSessionExpiredError)
                delete attempt.uploaded;
            setCheckoutProgress(undefined);
            setDeliveryBook(undefined);
            setExportError(
                error instanceof Error
                    ? error.message
                    : "Checkout failed. Please try again.",
            );
        } finally {
            actionInProgress.current = false;
        }
    };

    const downloadPdf = async (selection: PrintSelection) => {
        if (actionInProgress.current) return;
        actionInProgress.current = true;
        setExportProgress(0);
        setExportError(null);
        try {
            const pdf = await preparePdf(
                selection,
                setExportProgress,
                setOriginalsProgress,
            );
            if (!pdf) {
                setExportError(
                    "Some photos couldn't download. Click Download to try again. Your edits are unchanged.",
                );
                return;
            }
            saveAsFileAndRevokeObjectURL(
                URL.createObjectURL(pdf),
                `photobook-${selection.sizeMm}mm.pdf`,
            );
        } catch (error) {
            if (error instanceof PrintExportValidationError) {
                setPrintValidation({
                    selection,
                    pageCount: exportPages.length,
                    error: error.message,
                });
            } else {
                console.error("Export failed:", error);
                setExportError("Export failed. Please try again.");
            }
        } finally {
            actionInProgress.current = false;
            setExportProgress(null);
            setOriginalsProgress({ done: 0, total: 0 });
        }
    };

    const coverControls = (
        <Box
            sx={{
                display: "flex",
                alignItems: "center",
                gap: { xs: "16px", md: "24px" },
            }}
        >
            <Button
                variant="text"
                disableRipple
                startIcon={<EditIcon />}
                disabled={busy}
                onClick={() =>
                    mobile ? setDesktopEditingOpen(true) : setAppView("edit")
                }
                sx={{
                    ...editorButtonSx,
                    px: 1,
                    color: toolbarColors.text,
                    "&, &:hover": { bgcolor: "transparent" },
                    "& .MuiButton-startIcon": { ml: 0, mr: "8px" },
                }}
            >
                Edit
            </Button>
            <BookBindingSelect disabled={busy} />
        </Box>
    );

    const primaryAction = isDevBuild ? (
        <Button
            variant="contained"
            endIcon={checkoutProgress ? undefined : <ArrowRightIcon />}
            aria-busy={!!checkoutProgress}
            disabled={busy || pages.length === 0}
            sx={{
                ...(mobile ? editorButtonSx : headerButtonSx),
                "& .MuiButton-endIcon": { ml: mobile ? "6px" : 0, mr: 0 },
                ...(busy && { "&.Mui-disabled": { opacity: 1 } }),
            }}
            onClick={() => requestBook("checkout")}
        >
            Continue
        </Button>
    ) : (
        <Button
            id="download-button"
            variant="contained"
            aria-label={busy ? `Downloading, ${exportProgress}%` : "Download"}
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
            onClick={() => requestBook("download")}
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
                    {coverControls}
                </Box>
            ) : (
                <BookHeader
                    titleDisabled={busy}
                    sidebarOpen={sidebarOpen}
                    onToggleSidebar={onToggleSidebar}
                    center={
                        <Typography
                            component="div"
                            sx={{
                                color: toolbarColors.muted,
                                fontSize: 13,
                                lineHeight: "20px",
                                textAlign: "center",
                                maxWidth: { xs: 210, lg: 400, xl: 720 },
                            }}
                        >
                            Photos look blurry? This is a lower-resolution
                            preview.{" "}
                            <Link
                                component="button"
                                type="button"
                                variant="inherit"
                                underline="always"
                                disabled={busy || pages.length === 0}
                                onClick={() => requestBook("download")}
                                sx={{
                                    color: toolbarColors.text,
                                    verticalAlign: "baseline",
                                    textUnderlineOffset: "3px",
                                    "&:focus-visible": {
                                        outline: "2px solid currentColor",
                                        outlineOffset: 2,
                                    },
                                }}
                            >
                                {exportProgress === null
                                    ? "Download the PDF to see the print quality."
                                    : `Preparing PDF… ${exportProgress}%`}
                            </Link>
                        </Typography>
                    }
                >
                    {coverControls}
                    {isDevBuild && primaryAction}
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
                        justifyContent: "space-between",
                        alignItems: "center",
                        gap: 0.5,
                        px: 1,
                        pt: 1,
                        pb: "max(16px, env(safe-area-inset-bottom))",
                        flexShrink: 0,
                    }}
                >
                    <ResetBookButton disabled={busy} />
                    {primaryAction}
                </Box>
            )}

            <DesktopEditingDialog
                open={mobile && desktopEditingOpen}
                onClose={() => setDesktopEditingOpen(false)}
            />

            {spineTitleDialog}
            {deliveryBook && (
                <CheckoutDialog
                    cover={deliveryBook.cover}
                    pages={exportPages.length}
                    progress={checkoutProgress}
                    onClose={() => setDeliveryBook(undefined)}
                    onContinue={(destination) => {
                        void startCheckout(
                            deliveryBook.cover,
                            deliveryBook.title,
                            destination,
                        );
                    }}
                />
            )}
            {pendingCoverAction && (
                <CoverTypeDialog
                    onClose={() => setPendingCoverAction(undefined)}
                    onContinue={(cover) => {
                        setBook((previous) => ({
                            ...previous,
                            printSelection: getBindingPrintSelection(cover),
                        }));
                        setPendingCoverAction(undefined);
                        withSpineTitle((title) =>
                            continueWithCover(pendingCoverAction, cover, title),
                        );
                    }}
                />
            )}

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
