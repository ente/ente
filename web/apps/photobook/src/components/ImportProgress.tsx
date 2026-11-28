import { usePhotoImport } from "@/hooks/usePhotoImport";
import { accentGreen, accentGreenHover } from "@/theme/buttons";
import { uiColors } from "@/theme/colors";
import { Box, LinearProgress, Typography } from "@mui/material";
import { useEffect, useState } from "react";
import BookHeader from "./BookHeader";
import PhotoChoiceDialog from "./PhotoChoiceDialog";
import { EDITOR_PANEL_INSET } from "./editorLayout";

export default function ImportProgress() {
    const {
        importing,
        processingProgress,
        enteError,
        importError,
        enteStage,
        retryImport,
        dismissImport,
        chooseAnotherAlbum,
    } = usePhotoImport();
    const canRetry = enteError?.canRetry ?? true;
    const retryAt = enteError?.retryAt ?? 0;
    const [now, setNow] = useState(Date.now);
    useEffect(() => {
        if (!retryAt) return;
        const timeout = window.setTimeout(
            () => setNow(Date.now()),
            Math.max(0, retryAt - Date.now()),
        );
        return () => window.clearTimeout(timeout);
    }, [retryAt]);

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
                                sx={{
                                    fontFamily:
                                        "var(--font-outfit), sans-serif",
                                    fontSize: { xs: 22, sm: 28 },
                                    fontWeight: 500,
                                    letterSpacing: "-0.4px",
                                    mb: 3,
                                }}
                            >
                                Importing your photos...
                            </Typography>
                            <LinearProgress
                                variant="determinate"
                                value={processingProgress}
                                aria-label="Import progress"
                                sx={{
                                    height: { xs: 8, sm: 10 },
                                    borderRadius: "999px",
                                    bgcolor: "#2B2B2B",
                                    "& .MuiLinearProgress-bar": {
                                        borderRadius: "inherit",
                                        background: `linear-gradient(90deg, ${accentGreenHover}, ${accentGreen})`,
                                        transition: "transform 400ms ease-out",
                                    },
                                }}
                            />
                            <Typography
                                sx={{
                                    color: uiColors.muted,
                                    fontFamily:
                                        "var(--font-outfit), sans-serif",
                                    fontSize: 14,
                                    fontVariantNumeric: "tabular-nums",
                                    mt: 1.5,
                                }}
                            >
                                {processingProgress}%
                            </Typography>
                        </>
                    ) : (
                        <PhotoChoiceDialog
                            open={enteStage !== "url"}
                            icon="warning"
                            title="Couldn't import your photos"
                            description={
                                enteError?.message ||
                                importError ||
                                "Please try again."
                            }
                            primary={{
                                label: canRetry
                                    ? "Try again"
                                    : "Try a different album",
                                onClick: () => {
                                    if (canRetry) void retryImport();
                                    else chooseAnotherAlbum();
                                },
                                disabled: canRetry && now < retryAt,
                            }}
                            secondary={
                                canRetry
                                    ? {
                                          label: "Try a different album",
                                          onClick: chooseAnotherAlbum,
                                      }
                                    : undefined
                            }
                            onClose={dismissImport}
                        />
                    )}
                </Box>
            </Box>
        </Box>
    );
}
