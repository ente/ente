"use client";

import { useBook } from "@/context/book";
import { usePhotoImport } from "@/hooks/usePhotoImport";
import { Alert, Box, Button, TextField, Typography } from "@mui/material";
import { useRouter } from "next/navigation";
import { useEffect } from "react";
import NavBar from "./NavBar";

export default function StartPage() {
    const router = useRouter();
    const { loading } = useBook();
    useEffect(() => {
        router.prefetch("/app");
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
                minHeight: "100vh",
                bgcolor: "#fff",
                color: "#1A1C1D",
                display: "flex",
                flexDirection: "column",
                position: "relative",
                overflow: "hidden",
            }}
        >
            <NavBar />
            <Box
                component="main"
                onDrop={busy ? undefined : handleDrop}
                onDragOver={busy ? undefined : handleDragOver}
                onDragLeave={handleDragLeave}
                sx={{
                    flex: 1,
                    display: "flex",
                    flexDirection: "column",
                    alignItems: "center",
                    position: "relative",
                    px: 3,
                    pt: { xs: "128px", sm: "170px" },
                    pb: 8,
                }}
            >
                {dragOver && (
                    <Box
                        sx={{
                            position: "absolute",
                            inset: 0,
                            zIndex: 30,
                            bgcolor: "rgba(8,194,37,0.08)",
                            border: "3px dashed #08C225",
                            borderRadius: 2,
                            display: "grid",
                            placeItems: "center",
                            pointerEvents: "none",
                        }}
                    >
                        <Typography
                            sx={{
                                fontSize: "1.5rem",
                                fontWeight: 700,
                                color: "#08C225",
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
                        flexDirection: "column",
                        alignItems: "center",
                        textAlign: "center",
                        maxWidth: 1100,
                        width: "100%",
                    }}
                >
                    <Typography
                        component="h1"
                        sx={{
                            fontFamily: "var(--font-inter), sans-serif",
                            fontSize: { xs: "2.5rem", md: "4rem" },
                            fontWeight: 800,
                            letterSpacing: "-0.02em",
                            mb: 2,
                            lineHeight: 1.1,
                            color: "#1A1C1D",
                        }}
                    >
                        Your memories deserve a book
                    </Typography>
                    <Typography
                        sx={{
                            fontFamily: "var(--font-inter), sans-serif",
                            fontSize: "1.15rem",
                            color: "#666",
                            maxWidth: 560,
                            lineHeight: 1.7,
                            mb: 6,
                        }}
                    >
                        Drop in your photos and get a print-ready photobook.
                        <br />
                        Beautifully arranged, completely private, and free.
                    </Typography>
                    <Box
                        sx={{
                            mb: 8,
                            position: "relative",
                            "& .card": { transition: "transform 0.5s ease" },
                            "&:hover .card": {
                                transform: "rotate(0deg) !important",
                            },
                        }}
                    >
                        <Box
                            className="card"
                            component="img"
                            src="/hero-photo.jpg"
                            alt="A photobook page with photos from Delhi"
                            draggable={false}
                            sx={{
                                width: { xs: 260, md: 380 },
                                maxWidth: "100%",
                                height: "auto",
                                borderRadius: 2,
                                boxShadow:
                                    "0px 16px 40px rgba(0,0,0,0.15), 0px 4px 12px rgba(0,0,0,0.08)",
                                transform: "rotate(-3deg)",
                                position: "relative",
                                zIndex: 20,
                                userSelect: "none",
                                pointerEvents: "none",
                            }}
                        />
                    </Box>
                    <Button
                        variant="contained"
                        size="large"
                        disabled={busy}
                        onClick={() => fileInputRef.current?.click()}
                        sx={{
                            bgcolor: "#08C225",
                            fontFamily: "var(--font-inter), sans-serif",
                            fontSize: "1.15rem",
                            fontWeight: 700,
                            px: 6,
                            py: 2,
                            boxShadow: "none",
                            "&:hover": {
                                transform: "scale(1.02)",
                                bgcolor: "#07AE22",
                            },
                            "&:active": { transform: "scale(0.95)" },
                            transition:
                                "transform 0.3s ease, background-color 0.3s ease",
                        }}
                    >
                        Add photos
                    </Button>
                    {importError && (
                        <Alert severity="error" sx={{ mt: 2, maxWidth: 480 }}>
                            {importError}
                        </Alert>
                    )}
                    <Box
                        component="form"
                        onSubmit={(event) => {
                            event.preventDefault();
                            if (!busy && enteUrl.trim())
                                void handleImportEnte();
                        }}
                        sx={{ mt: 3, mb: 3, width: "100%", maxWidth: 480 }}
                    >
                        <Typography
                            component="label"
                            htmlFor="landing-album-url"
                            sx={{
                                display: "block",
                                mb: 1.5,
                                color: "#777",
                                fontSize: 14,
                            }}
                        >
                            or import an Ente album
                        </Typography>
                        <Box sx={{ display: "flex", gap: 1 }}>
                            <TextField
                                id="landing-album-url"
                                fullWidth
                                placeholder="Paste an album link"
                                value={enteUrl}
                                onChange={(event) =>
                                    setEnteUrl(event.target.value)
                                }
                                error={Boolean(enteError)}
                                autoComplete="off"
                                disabled={busy}
                                slotProps={{
                                    htmlInput: {
                                        inputMode: "url",
                                        spellCheck: false,
                                        "aria-describedby": enteError
                                            ? "landing-import-error"
                                            : undefined,
                                    },
                                }}
                                sx={{
                                    "& .MuiOutlinedInput-root": {
                                        height: 48,
                                        borderRadius: "14px",
                                        color: "#333",
                                        bgcolor: "#FFF",
                                        fontSize: 14,
                                        "& fieldset": { borderColor: "#DDD" },
                                        "&:hover fieldset": {
                                            borderColor: "#BBB",
                                        },
                                        "&.Mui-focused fieldset": {
                                            borderColor: "#08C225",
                                        },
                                    },
                                }}
                            />
                            <Button
                                type="submit"
                                disabled={busy || !enteUrl.trim()}
                                sx={{
                                    height: 48,
                                    px: 2.5,
                                    borderRadius: "14px",
                                    color: "#006E0F",
                                    bgcolor: "#EEF8EF",
                                    "&:hover": { bgcolor: "#E1F2E3" },
                                    "&.Mui-disabled": {
                                        color: "#999",
                                        bgcolor: "#F2F2F2",
                                    },
                                }}
                            >
                                Import
                            </Button>
                        </Box>
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
                    <Typography
                        sx={{
                            fontFamily: "var(--font-inter), sans-serif",
                            fontSize: "0.85rem",
                            color: "#999",
                            letterSpacing: "0.04em",
                        }}
                    >
                        Print-ready. Auto-arranged. 100% in your browser.
                    </Typography>
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
