import { useBook } from "@/context/book";
import { usePhotoImport } from "@/hooks/usePhotoImport";
import {
    Alert,
    Box,
    Button,
    InputAdornment,
    TextField,
    Typography,
} from "@mui/material";
import { useRouter } from "next/router";
import { useEffect } from "react";
import { AddPhotosIcon } from "./icons";

export default function StartPage() {
    const router = useRouter();
    const { loading } = useBook();
    useEffect(() => {
        void router.prefetch("/app");
    }, [router]);
    const {
        fileInputRef,
        dragOver,
        enteUrl,
        setEnteUrl,
        enteError,
        importError,
        importing,
        handleImportEnte,
        handleFiles,
        handleDrop,
        handleDragOver,
        handleDragLeave,
    } = usePhotoImport();
    const busy = loading || importing;

    return (
        <Box
            sx={{
                minHeight: "100svh",
                bgcolor: "#fff",
                color: "#003D12",
                display: "flex",
                flexDirection: "column",
                p: { xs: 1, sm: 1.5 },
            }}
        >
            <Box
                component="main"
                className="green-bg"
                onDrop={busy ? undefined : handleDrop}
                onDragOver={busy ? undefined : handleDragOver}
                onDragLeave={handleDragLeave}
                sx={{
                    flex: 1,
                    display: "flex",
                    flexDirection: "column",
                    alignItems: "center",
                    justifyContent: "center",
                    position: "relative",
                    overflow: "hidden",
                    borderRadius: { xs: "20px", sm: "28px" },
                    px: { xs: 2.5, sm: 4 },
                    pt: { xs: 3, sm: "clamp(24px, 4vh, 48px)" },
                    pb: {
                        xs: "max(20px, env(safe-area-inset-bottom))",
                        sm: "clamp(24px, 4vh, 48px)",
                    },
                }}
            >
                {dragOver && (
                    <Box
                        sx={{
                            position: "absolute",
                            inset: 0,
                            zIndex: 30,
                            bgcolor: "rgba(0,61,18,0.9)",
                            border: "3px dashed #FFF",
                            borderRadius: "inherit",
                            display: "grid",
                            placeItems: "center",
                            pointerEvents: "none",
                        }}
                    >
                        <Typography
                            sx={{
                                fontSize: "1.5rem",
                                fontWeight: 700,
                                color: "#FFF",
                            }}
                        >
                            Drop your photos here
                        </Typography>
                    </Box>
                )}
                <Box
                    sx={{
                        position: "relative",
                        zIndex: 10,
                        display: "flex",
                        flex: { xs: 1, sm: "initial" },
                        flexDirection: "column",
                        alignItems: "center",
                        textAlign: "center",
                        maxWidth: 660,
                        width: "100%",
                    }}
                >
                    <Box
                        sx={{
                            display: "flex",
                            flex: { xs: 1, sm: "initial" },
                            flexDirection: "column",
                            alignItems: "center",
                            justifyContent: "center",
                            width: "100%",
                            pb: { xs: 4, sm: 5 },
                            "@media (max-width: 599px) and (max-height: 640px)":
                                { pb: 3, "& > img": { width: 140, mb: 2 } },
                        }}
                    >
                        <Box
                            component="img"
                            src="/photobook-duck.png"
                            alt="A happy duck reading a photobook"
                            width={430}
                            height={468}
                            draggable={false}
                            sx={{
                                display: "block",
                                mb: { xs: 3, sm: 4 },
                                width: {
                                    xs: "clamp(160px, 28vh, 220px)",
                                    sm: "clamp(180px, 27vh, 300px)",
                                },
                                maxWidth: "100%",
                                height: "auto",
                                userSelect: "none",
                                pointerEvents: "none",
                            }}
                        />
                        <Typography
                            component="h1"
                            sx={{
                                fontFamily: "var(--font-outfit), sans-serif",
                                fontSize: {
                                    xs: "clamp(2rem, 10vw, 2.5rem)",
                                    sm: "clamp(2.5rem, 6vh, 3.5rem)",
                                },
                                fontWeight: 800,
                                letterSpacing: "-0.02em",
                                mb: { xs: 1.5, sm: 2 },
                                lineHeight: 1.1,
                                color: "#FFF",
                            }}
                        >
                            Your memories{" "}
                            <Box
                                component="span"
                                sx={{
                                    display: "block",
                                    fontFamily: '"Gochi Hand", cursive',
                                    fontSize: "1.15em",
                                    fontWeight: 400,
                                    letterSpacing: "-0.025em",
                                }}
                            >
                                deserve a book
                            </Box>
                        </Typography>
                        <Typography
                            sx={{
                                fontFamily: "var(--font-outfit), sans-serif",
                                fontSize: { xs: "0.95rem", sm: "1.125rem" },
                                fontWeight: 500,
                                color: "rgba(0,61,18,0.65)",
                                maxWidth: { xs: 560, md: 480 },
                                lineHeight: 1.5,
                            }}
                        >
                            Turn the photos you love into a beautifully arranged
                            photobook, ready to print and keep for years to
                            come.
                        </Typography>
                    </Box>
                    <Box
                        sx={{
                            display: "grid",
                            gridTemplateColumns: "minmax(0, 1fr)",
                            alignItems: "start",
                            gap: 2,
                            width: "100%",
                            maxWidth: { xs: "100%", sm: 370 },
                            mt: { xs: "auto", sm: 0 },
                        }}
                    >
                        <Box
                            component="form"
                            onSubmit={(event) => {
                                event.preventDefault();
                                if (!busy && enteUrl.trim())
                                    void handleImportEnte();
                            }}
                            sx={{ minWidth: 0 }}
                        >
                            <TextField
                                id="landing-album-url"
                                variant="outlined"
                                margin="none"
                                fullWidth
                                placeholder="Paste an Ente album link"
                                value={enteUrl}
                                onChange={(event) =>
                                    setEnteUrl(event.target.value)
                                }
                                error={Boolean(enteError)}
                                autoComplete="off"
                                disabled={busy}
                                slotProps={{
                                    input: {
                                        endAdornment: (
                                            <InputAdornment position="end">
                                                <Button
                                                    type="submit"
                                                    disabled={
                                                        busy || !enteUrl.trim()
                                                    }
                                                    sx={{
                                                        minWidth: 84,
                                                        height: 42,
                                                        px: 2,
                                                        borderRadius: "999px",
                                                        color: "#08652D",
                                                        bgcolor: "#FFF",
                                                        fontFamily:
                                                            "var(--font-outfit), sans-serif",
                                                        fontSize: 14,
                                                        fontWeight: 600,
                                                        "&:hover": {
                                                            bgcolor: "#ECF8EF",
                                                        },
                                                        "&.Mui-disabled": {
                                                            color: "#497755",
                                                            bgcolor: "#DAEEDF",
                                                            opacity: 1,
                                                        },
                                                        "&.Mui-focusVisible": {
                                                            outline:
                                                                "2px solid #FFF",
                                                            outlineOffset: 2,
                                                        },
                                                    }}
                                                >
                                                    Import
                                                </Button>
                                            </InputAdornment>
                                        ),
                                    },
                                    htmlInput: {
                                        "aria-label": "Ente album link",
                                        inputMode: "url",
                                        spellCheck: false,
                                        "aria-describedby": enteError
                                            ? "landing-import-error"
                                            : undefined,
                                    },
                                }}
                                sx={{
                                    "& .MuiInputAdornment-root": { mr: 0 },
                                    "& .MuiOutlinedInput-root": {
                                        height: 56,
                                        pl: 1,
                                        pr: "7px",
                                        borderRadius: "999px",
                                        color: "#FFF",
                                        bgcolor: "rgba(0,80,20,0.38)",
                                        transition:
                                            "background-color 150ms ease",
                                        fontFamily:
                                            "var(--font-outfit), sans-serif",
                                        fontSize: 16,
                                        "& fieldset": {
                                            borderColor: "transparent",
                                        },
                                        "&:hover": {
                                            bgcolor: "rgba(0,80,20,0.46)",
                                        },
                                        "&:hover fieldset": {
                                            borderColor: "transparent",
                                        },
                                        "&.Mui-focused": {
                                            bgcolor: "rgba(0,80,20,0.52)",
                                        },
                                        "&.Mui-focused fieldset": {
                                            borderColor: "transparent",
                                        },
                                        "& input::placeholder": {
                                            color: "#D7E8DB",
                                            opacity: 1,
                                        },
                                    },
                                }}
                            />
                            {enteError && (
                                <Alert
                                    id="landing-import-error"
                                    severity="error"
                                    sx={{
                                        mt: 2,
                                        borderRadius: 2,
                                        textAlign: "left",
                                    }}
                                >
                                    {enteError}
                                </Alert>
                            )}
                        </Box>
                        <Button
                            variant="outlined"
                            size="large"
                            disabled={busy}
                            onClick={() => fileInputRef.current?.click()}
                            startIcon={
                                <AddPhotosIcon sx={{ width: 20, height: 20 }} />
                            }
                            sx={{
                                height: 53,
                                color: "#FFF2CD",
                                borderColor: "rgba(255,242,205,0.3)",
                                fontFamily: "var(--font-outfit), sans-serif",
                                fontSize: 14,
                                fontWeight: 500,
                                whiteSpace: "nowrap",
                                px: 3,
                                py: 0,
                                borderRadius: "999px",
                                "&:hover": {
                                    bgcolor: "rgba(255,242,205,0.12)",
                                    borderColor: "rgba(255,242,205,0.55)",
                                },
                                "&.Mui-disabled": {
                                    color: "rgba(255,242,205,0.45)",
                                    borderColor: "rgba(255,242,205,0.2)",
                                },
                                "&.Mui-focusVisible": {
                                    outline: "3px solid #FFF2CD",
                                    outlineOffset: 3,
                                },
                            }}
                        >
                            Add photos instead
                        </Button>
                        {importError && (
                            <Alert
                                severity="error"
                                sx={{ gridColumn: "1 / -1", textAlign: "left" }}
                            >
                                {importError}
                            </Alert>
                        )}
                    </Box>
                </Box>
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
