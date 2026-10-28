"use client";

import { usePhotoImport } from "@/hooks/usePhotoImport";
import {
    accentGreen,
    editorButtonSx,
    editorToolbarButtonSx,
} from "@/theme/buttons";
import { uiColors } from "@/theme/colors";
import {
    Alert,
    Box,
    Button,
    InputBase,
    LinearProgress,
    Typography,
} from "@mui/material";
import { AddPhotosIcon, LinkIcon } from "./icons";

export default function EmptyBookState() {
    const {
        fileInputRef,
        dragOver,
        enteUrl,
        setEnteUrl,
        enteError,
        importError,
        processingPhotos,
        processingProgress,
        processingMessage,
        handleImportEnte,
        handleFiles,
        handleDrop,
        handleDragOver,
        handleDragLeave,
    } = usePhotoImport();

    return (
        <Box
            onDrop={processingPhotos ? undefined : handleDrop}
            onDragOver={processingPhotos ? undefined : handleDragOver}
            onDragLeave={(event) => {
                if (
                    !event.currentTarget.contains(
                        event.relatedTarget as Node | null,
                    )
                )
                    handleDragLeave();
            }}
            sx={{
                flex: 1,
                minHeight: "min-content",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                px: 2,
                py: 5,
            }}
        >
            <Box sx={{ width: "100%", maxWidth: 480 }}>
                {processingPhotos ? (
                    <Box
                        role="status"
                        aria-live="polite"
                        sx={{ py: 5, textAlign: "center" }}
                    >
                        <Typography
                            sx={{ fontSize: 18, fontWeight: 600, mb: 3 }}
                        >
                            {processingMessage}
                        </Typography>
                        <LinearProgress
                            variant="determinate"
                            value={processingProgress}
                            aria-label="Import progress"
                            sx={{
                                height: 5,
                                borderRadius: 3,
                                bgcolor: uiColors.control,
                                "& .MuiLinearProgress-bar": { borderRadius: 3 },
                            }}
                        />
                        <Typography
                            sx={{ fontSize: 13, color: uiColors.muted, mt: 2 }}
                        >
                            {processingProgress}%
                        </Typography>
                    </Box>
                ) : (
                    <>
                        <Typography
                            component="h1"
                            sx={{
                                fontSize: { xs: 28, sm: 32 },
                                lineHeight: 1.25,
                                fontWeight: 600,
                                letterSpacing: "-0.8px",
                                mb: 4,
                                textAlign: "center",
                            }}
                        >
                            Create your photobook
                        </Typography>
                        <Box
                            component="form"
                            onSubmit={(event) => {
                                event.preventDefault();
                                if (enteUrl.trim()) void handleImportEnte();
                            }}
                        >
                            <Box
                                sx={{
                                    display: "flex",
                                    alignItems: "center",
                                    gap: { xs: 1, sm: 1.5 },
                                    p: "6px",
                                    pl: { xs: "12px", sm: "18px" },
                                    borderRadius: "20px",
                                    border: `1px solid ${enteError ? uiColors.danger : "#414141"}`,
                                    bgcolor: "#242424",
                                    transition:
                                        "border-color 120ms ease, background-color 120ms ease",
                                    "&:hover": { borderColor: "#626262" },
                                    "&:focus-within": {
                                        borderColor: accentGreen,
                                    },
                                }}
                            >
                                <LinkIcon
                                    aria-hidden="true"
                                    sx={{
                                        fontSize: 22,
                                        color: uiColors.muted,
                                        flexShrink: 0,
                                    }}
                                />
                                <InputBase
                                    id="empty-book-album-url"
                                    placeholder="Paste an Ente Photos album link"
                                    value={enteUrl}
                                    onChange={(event) =>
                                        setEnteUrl(event.target.value)
                                    }
                                    error={Boolean(enteError)}
                                    autoComplete="off"
                                    inputProps={{
                                        "aria-label": "Ente Photos album link",
                                        inputMode: "url",
                                        spellCheck: false,
                                        "aria-describedby": enteError
                                            ? "empty-book-import-error"
                                            : undefined,
                                    }}
                                    sx={{
                                        flex: 1,
                                        minWidth: 0,
                                        fontSize: { xs: 14, sm: 15 },
                                        "& input": { py: 1.5 },
                                        "& input::placeholder": {
                                            color: uiColors.muted,
                                            opacity: 1,
                                        },
                                    }}
                                />
                                <Button
                                    type="submit"
                                    variant="contained"
                                    disabled={!enteUrl.trim()}
                                    sx={{
                                        ...editorButtonSx,
                                        height: 46,
                                        px: { xs: 2, sm: 3 },
                                        fontWeight: 700,
                                        flexShrink: 0,
                                        borderRadius: "13px",
                                    }}
                                >
                                    Import
                                </Button>
                            </Box>
                            {enteError && (
                                <Alert
                                    id="empty-book-import-error"
                                    severity="error"
                                    sx={{ mt: 2, borderRadius: "14px" }}
                                >
                                    {enteError}
                                </Alert>
                            )}
                        </Box>
                        <Typography
                            sx={{
                                my: 2.5,
                                fontSize: 12,
                                lineHeight: "18px",
                                color: "#808080",
                                textAlign: "center",
                            }}
                        >
                            or
                        </Typography>
                        <Box
                            role="group"
                            aria-label="Add or drop photos"
                            sx={{
                                textAlign: "center",
                                p: 3,
                                borderRadius: "20px",
                                minHeight: 300,
                                display: "flex",
                                flexDirection: "column",
                                alignItems: "center",
                                justifyContent: "center",
                                border: `1px dashed ${dragOver ? accentGreen : "#484848"}`,
                                bgcolor: dragOver ? "#1B2A1D" : "transparent",
                                transition:
                                    "border-color 120ms ease, background-color 120ms ease",
                            }}
                        >
                            <Button
                                startIcon={
                                    <AddPhotosIcon sx={{ fontSize: 20 }} />
                                }
                                onClick={() => fileInputRef.current?.click()}
                                sx={{
                                    ...editorToolbarButtonSx,
                                    borderRadius: "14px",
                                    px: 2,
                                }}
                            >
                                Add photos
                            </Button>
                            <Typography
                                sx={{
                                    mt: 1.5,
                                    fontSize: 12,
                                    lineHeight: "18px",
                                    color: dragOver ? uiColors.text : "#898989",
                                }}
                            >
                                {dragOver
                                    ? "Drop photos here"
                                    : "or drop photos here"}
                            </Typography>
                        </Box>
                        {importError && (
                            <Alert
                                severity="error"
                                sx={{ mt: 2, borderRadius: "14px" }}
                            >
                                {importError}
                            </Alert>
                        )}
                    </>
                )}
            </Box>
            <input
                ref={fileInputRef}
                type="file"
                accept="image/jpeg,image/png,image/webp,image/heic,image/heif,.heic,.heif"
                multiple
                style={{ display: "none" }}
                onChange={(event) => {
                    if (event.currentTarget.files)
                        void handleFiles(event.currentTarget.files);
                    event.currentTarget.value = "";
                }}
            />
        </Box>
    );
}
