import EditPage from "@/components/EditPage";
import ResultsPage from "@/components/ResultsPage";
import { useBook, useBookSelector } from "@/context/book";
import { usePhotoImport } from "@/hooks/usePhotoImport";
import { popupShadow, uiColors } from "@/theme/colors";
import {
    Alert,
    Backdrop,
    Box,
    CircularProgress,
    Snackbar,
    Typography,
    useMediaQuery,
} from "@mui/material";
import { useCallback, useEffect, useRef, useState } from "react";
import type { SidebarTab } from "./BookSidebar";
import { MOBILE_QUERY } from "./editorLayout";
import EntePasswordDialog from "./EntePasswordDialog";
import ImportProgress from "./ImportProgress";

export default function AppShell() {
    const mobile = useMediaQuery(MOBILE_QUERY, { noSsr: true });
    const hasPlacedPhotos = useBookSelector((state) =>
        state.book.pages.some((page) =>
            page.slots.some((slot) => slot.photoId),
        ),
    );
    const [sidebarOpen, setSidebarOpen] = useState(!mobile);
    const [sidebarTab, setSidebarTab] = useState<SidebarTab>(
        hasPlacedPhotos ? "pages" : "photos",
    );
    const sidebarScrollPositions = useRef({ pages: 0, photos: 0 });
    const toggleSidebar = useCallback(
        () => setSidebarOpen((open) => !open),
        [],
    );
    const openSidebar = useCallback(() => setSidebarOpen(true), []);
    const {
        appView,
        loading,
        importNotice,
        clearImportNotice,
        book,
        addPhotos,
        processingPhotos,
        processingProgress,
    } = useBook(
        "appView",
        "loading",
        "importNotice",
        "clearImportNotice",
        "book",
        "addPhotos",
        "processingPhotos",
        "processingProgress",
    );
    const showPreview = mobile || appView === "results";
    const {
        importActive,
        enteStage,
        entePassword,
        setEntePassword,
        handleSubmitPassword,
        handleCancelPassword,
    } = usePhotoImport();
    const wasImporting = useRef(false);
    useEffect(() => {
        if (importActive) {
            sidebarScrollPositions.current = { pages: 0, photos: 0 };
            setSidebarOpen(true);
        } else if (wasImporting.current) {
            setSidebarTab(hasPlacedPhotos ? "pages" : "photos");
        }
        wasImporting.current = importActive;
    }, [importActive, hasPlacedPhotos]);
    const [photoImportError, setPhotoImportError] = useState<string | null>(
        null,
    );
    const [showPhotoImportProgress, setShowPhotoImportProgress] =
        useState(false);
    const pagePhotoImportBusy =
        !importActive && processingPhotos && book.pages.length > 0;

    useEffect(() => {
        if (!pagePhotoImportBusy) {
            setShowPhotoImportProgress(false);
            return;
        }
        const timeout = window.setTimeout(
            () => setShowPhotoImportProgress(true),
            300,
        );
        return () => window.clearTimeout(timeout);
    }, [pagePhotoImportBusy]);

    const photoInputRef = useRef<HTMLInputElement>(null);

    const handleAddPhotos = useCallback(() => {
        if (processingPhotos) return;
        setPhotoImportError(null);
        photoInputRef.current?.click();
    }, [processingPhotos]);

    if (loading) {
        return (
            <Box
                sx={{
                    minHeight: "100vh",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                }}
            >
                <CircularProgress sx={{ color: "#08C225" }} />
            </Box>
        );
    }

    return (
        <>
            {importActive ? (
                <ImportProgress />
            ) : (
                <Box data-workspace-view={showPreview ? "results" : "edit"}>
                    {showPreview ? (
                        <ResultsPage
                            sidebarOpen={sidebarOpen}
                            sidebarTab={sidebarTab}
                            sidebarScrollPositions={sidebarScrollPositions}
                            onSidebarTabChange={setSidebarTab}
                            onToggleSidebar={toggleSidebar}
                            onAddPhotos={handleAddPhotos}
                        />
                    ) : (
                        <EditPage
                            sidebarOpen={sidebarOpen}
                            sidebarTab={sidebarTab}
                            sidebarScrollPositions={sidebarScrollPositions}
                            onSidebarTabChange={setSidebarTab}
                            onToggleSidebar={toggleSidebar}
                            onAddPhotos={handleAddPhotos}
                        />
                    )}
                </Box>
            )}
            <input
                ref={photoInputRef}
                type="file"
                accept="image/jpeg,image/png,image/webp,image/heic,image/heif,.heic,.heif"
                multiple
                style={{ display: "none" }}
                onChange={async (event) => {
                    const files = Array.from(event.currentTarget.files ?? []);
                    event.currentTarget.value = "";
                    if (files.length === 0) return;
                    setSidebarTab("photos");
                    openSidebar();
                    try {
                        await addPhotos(files, {
                            replace: book.pages.length === 0,
                            destination: { kind: "gallery" },
                        });
                    } catch (error) {
                        setPhotoImportError(
                            error instanceof Error
                                ? error.message
                                : "Couldn't add these photos. Please try again.",
                        );
                    }
                }}
            />
            <Backdrop
                open={pagePhotoImportBusy}
                invisible={!showPhotoImportProgress}
                transitionDuration={0}
                sx={{ zIndex: (theme) => theme.zIndex.modal + 1 }}
            >
                {pagePhotoImportBusy && showPhotoImportProgress && (
                    <Box
                        role="status"
                        aria-live="polite"
                        sx={{
                            display: "flex",
                            alignItems: "center",
                            gap: 2,
                            bgcolor: uiColors.surface,
                            color: uiColors.text,
                            p: 3,
                            borderRadius: 3,
                        }}
                    >
                        <CircularProgress size={24} sx={{ color: "#08C225" }} />
                        <Typography>
                            {"Adding photos… "}
                            {processingProgress}%
                        </Typography>
                    </Box>
                )}
            </Backdrop>
            <Snackbar
                open={!!photoImportError}
                onClose={() => setPhotoImportError(null)}
                anchorOrigin={{ vertical: "top", horizontal: "center" }}
            >
                <Alert
                    severity="error"
                    onClose={() => setPhotoImportError(null)}
                >
                    {photoImportError}
                </Alert>
            </Snackbar>

            <EntePasswordDialog
                open={enteStage === "password"}
                password={entePassword}
                onPasswordChange={setEntePassword}
                onSubmit={handleSubmitPassword}
                onCancel={handleCancelPassword}
            />

            <Snackbar
                open={Boolean(importNotice)}
                autoHideDuration={10000}
                onClose={clearImportNotice}
                anchorOrigin={{ vertical: "bottom", horizontal: "center" }}
            >
                <Alert
                    severity="info"
                    onClose={clearImportNotice}
                    sx={{
                        bgcolor: uiColors.surface,
                        color: uiColors.text,
                        boxShadow: popupShadow,
                        "& .MuiAlert-icon": { color: "#08C225" },
                    }}
                >
                    {importNotice}
                </Alert>
            </Snackbar>
        </>
    );
}
