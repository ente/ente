"use client";

import EditPage from "@/components/EditPage";
import ResultsPage from "@/components/ResultsPage";
import { useBook } from "@/context/book";
import { usePhotoImport } from "@/hooks/usePhotoImport";
import type { AppView } from "@/lib/types";
import { popupShadow, uiColors } from "@/theme/colors";
import {
    Alert,
    Box,
    CircularProgress,
    Dialog,
    DialogContent,
    Fade,
    IconButton,
    Snackbar,
    Typography,
    useMediaQuery,
} from "@mui/material";
import { useEffect, useState } from "react";
import EntePasswordDialog from "./EntePasswordDialog";
import { CloseIcon } from "./icons";
import ImportProgress from "./ImportProgress";

function BookWorkspace({ view }: { view: AppView }) {
    const [displayedView, setDisplayedView] = useState(view);
    const reduceMotion = useMediaQuery("(prefers-reduced-motion: reduce)");
    const visible = displayedView === view;

    return (
        <Fade
            in={visible}
            appear={false}
            timeout={reduceMotion ? 0 : { exit: 120, enter: 220 }}
            easing={{ exit: "ease-in", enter: "ease-out" }}
            onExited={() => setDisplayedView(view)}
        >
            {/* Keep the outgoing screen intact until it fades out. Only one workspace
          is mounted, so canvases and keyboard handlers never overlap. */}
            <Box inert={!visible} data-workspace-view={displayedView}>
                {displayedView === "results" ? <ResultsPage /> : <EditPage />}
            </Box>
        </Fade>
    );
}

export default function AppShell() {
    const { appView, loading, book, importNotice, clearImportNotice } =
        useBook();
    const {
        importActive,
        enteStage,
        entePassword,
        setEntePassword,
        handleSubmitPassword,
        handleCancelPassword,
    } = usePhotoImport();
    const [showMobileHint, setShowMobileHint] = useState(false);

    useEffect(() => {
        if (
            !importActive &&
            book.pages.length > 0 &&
            appView === "edit" &&
            typeof window !== "undefined" &&
            window.matchMedia("(max-width: 640px)").matches
        ) {
            const dismissed = sessionStorage.getItem("mobile-hint-dismissed");
            if (!dismissed) setShowMobileHint(true);
        }
    }, [appView, importActive, book.pages.length]);

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
                <BookWorkspace view={appView} />
            )}
            <EntePasswordDialog
                open={enteStage === "password"}
                password={entePassword}
                onPasswordChange={setEntePassword}
                onSubmit={handleSubmitPassword}
                onCancel={handleCancelPassword}
            />

            {/* Import truncation notice */}
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

            {/* Mobile hint dialog */}
            <Dialog
                open={showMobileHint}
                onClose={() => {
                    setShowMobileHint(false);
                    sessionStorage.setItem("mobile-hint-dismissed", "1");
                }}
                slotProps={{
                    paper: {
                        sx: {
                            borderRadius: 4,
                            maxWidth: 300,
                            mx: 2,
                            p: 0,
                            bgcolor: uiColors.surface,
                            boxShadow: popupShadow,
                        },
                    },
                }}
            >
                <DialogContent
                    sx={{
                        textAlign: "center",
                        py: 3.5,
                        px: 3,
                        position: "relative",
                    }}
                >
                    <IconButton
                        onClick={() => {
                            setShowMobileHint(false);
                            sessionStorage.setItem(
                                "mobile-hint-dismissed",
                                "1",
                            );
                        }}
                        size="small"
                        sx={{
                            position: "absolute",
                            top: 6,
                            right: 6,
                            color: uiColors.muted,
                            "&:hover": { color: uiColors.text },
                        }}
                    >
                        <CloseIcon sx={{ fontSize: 18 }} />
                    </IconButton>
                    <Typography
                        variant="subtitle1"
                        sx={{
                            fontFamily: "var(--font-inter)",
                            fontWeight: 700,
                            mb: 0.5,
                            color: uiColors.text,
                            fontSize: "1rem",
                        }}
                    >
                        Best on desktop
                    </Typography>
                    <Typography
                        variant="body2"
                        sx={{
                            fontFamily: "var(--font-inter)",
                            color: uiColors.muted,
                            lineHeight: 1.55,
                            fontSize: "0.835rem",
                        }}
                    >
                        The photobook editor works best on a larger screen. For
                        the full experience, try it on a desktop or laptop.
                    </Typography>
                </DialogContent>
            </Dialog>
        </>
    );
}
