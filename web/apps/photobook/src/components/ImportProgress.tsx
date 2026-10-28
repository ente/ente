"use client";

import { usePhotoImport } from "@/hooks/usePhotoImport";
import { editorButtonSx, secondaryButtonSx } from "@/theme/buttons";
import { uiColors } from "@/theme/colors";
import {
    Alert,
    Box,
    Button,
    LinearProgress,
    TextField,
    Typography,
} from "@mui/material";
import BookHeader from "./BookHeader";
import { EDITOR_PANEL_INSET } from "./editorLayout";

export default function ImportProgress() {
    const {
        importing,
        processingProgress,
        processingMessage,
        enteUrl,
        setEnteUrl,
        enteError,
        importError,
        retryImport,
        dismissImport,
    } = usePhotoImport();

    return (
        <Box
            sx={{
                minHeight: "100dvh",
                display: "flex",
                flexDirection: "column",
                px: EDITOR_PANEL_INSET,
                pb: EDITOR_PANEL_INSET,
                bgcolor: uiColors.background,
            }}
        >
            <BookHeader showBookControls={false}>{null}</BookHeader>
            <Box
                sx={{
                    flex: 1,
                    display: "grid",
                    placeItems: "center",
                    px: 2,
                    py: 5,
                }}
            >
                <Box sx={{ width: "100%", maxWidth: 400, textAlign: "center" }}>
                    {importing ? (
                        <>
                            <Typography
                                component="h1"
                                sx={{ fontSize: 22, fontWeight: 600, mb: 3 }}
                            >
                                {processingMessage}
                            </Typography>
                            <LinearProgress
                                variant="determinate"
                                value={processingProgress}
                                aria-label="Import progress"
                                sx={{
                                    height: 6,
                                    borderRadius: 3,
                                    bgcolor: "#303030",
                                    "& .MuiLinearProgress-bar": {
                                        borderRadius: 3,
                                    },
                                }}
                            />
                            <Typography
                                sx={{
                                    color: uiColors.muted,
                                    fontSize: 14,
                                    fontVariantNumeric: "tabular-nums",
                                    mt: 1.5,
                                }}
                            >
                                {processingProgress}%
                            </Typography>
                        </>
                    ) : (
                        <>
                            <Typography
                                component="h1"
                                sx={{ fontSize: 24, fontWeight: 600, mb: 2 }}
                            >
                                Couldn’t import your photos
                            </Typography>
                            <Alert
                                severity="error"
                                sx={{
                                    textAlign: "left",
                                    borderRadius: "14px",
                                    mb: 2,
                                }}
                            >
                                {enteError || importError}
                            </Alert>
                            {enteError && (
                                <TextField
                                    fullWidth
                                    label="Ente album link"
                                    value={enteUrl}
                                    onChange={(event) =>
                                        setEnteUrl(event.target.value)
                                    }
                                    sx={{ mb: 2 }}
                                />
                            )}
                            <Box sx={{ display: "flex", gap: 1 }}>
                                <Button
                                    fullWidth
                                    onClick={dismissImport}
                                    sx={secondaryButtonSx}
                                >
                                    Back
                                </Button>
                                <Button
                                    fullWidth
                                    variant="contained"
                                    onClick={() => {
                                        void retryImport();
                                    }}
                                    disabled={!!enteError && !enteUrl.trim()}
                                    sx={editorButtonSx}
                                >
                                    Try again
                                </Button>
                            </Box>
                        </>
                    )}
                </Box>
            </Box>
        </Box>
    );
}
