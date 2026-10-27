import { Box, Button, CircularProgress, Typography } from "@mui/material";
import { Notification } from "ente-base/components/Notification";
import Head from "next/head";
import React from "react";
import { useFileShare } from "../../hooks/use-file-share";
import { formatFileSize } from "../../services/file-share";
import { getLockerFileIcon } from "../../utils/file-type";
import { LockerTypeDisplay } from "./LockerTypeDisplay";

export const FileShareView: React.FC = () => {
    const {
        loading,
        downloading,
        error,
        fileInfo,
        notificationProps,
        handleDownload,
        handleCopyContent,
    } = useFileShare();
    const iconInfo = fileInfo
        ? getLockerFileIcon(fileInfo.fileName, {
              lockerType: fileInfo.lockerType,
          })
        : null;

    return (
        <>
            <Head>
                <meta name="robots" content="noindex, nofollow" />
            </Head>
            <Box
                sx={{
                    height: "100dvh",
                    width: "100%",
                    maxWidth: "100%",
                    bgcolor: "accent.main",
                    display: "flex",
                    flexDirection: "column",
                    alignItems: "center",
                    p: { xs: 1.25, md: 2 },
                    boxSizing: "border-box",
                    overflow: "hidden",
                }}
            >
                <Box
                    sx={{
                        width: "100%",
                        height: {
                            xs: "calc(100dvh - 20px)",
                            md: "calc(100dvh - 32px)",
                        },
                        bgcolor: "background.default",
                        borderRadius: { xs: "24px", md: "34px" },
                        display: "flex",
                        flexDirection: "column",
                        alignItems: "center",
                        overflowX: "hidden",
                        overflowY: "auto",
                        "& > *": { flexShrink: 0 },
                        scrollbarWidth: "thin",
                        scrollbarColor: "rgba(128, 128, 128, 0.35) transparent",
                        "&::-webkit-scrollbar": { width: 6 },
                        "&::-webkit-scrollbar-track": {
                            background: "transparent",
                            marginBlock: "34px",
                        },
                        "&::-webkit-scrollbar-thumb": {
                            backgroundColor: "rgba(128, 128, 128, 0.35)",
                            borderRadius: "999px",
                            "&:hover": {
                                backgroundColor: "rgba(128, 128, 128, 0.55)",
                            },
                        },
                        "& ::selection": {
                            backgroundColor: "accent.main",
                            color: "fixed.white",
                        },
                        "& ::-moz-selection": {
                            backgroundColor: "accent.main",
                            color: "fixed.white",
                        },
                    }}
                >
                    <Box
                        sx={{
                            position: "sticky",
                            top: { xs: 16, md: 24 },
                            zIndex: 1,
                            alignSelf: "flex-end",
                            height: 0,
                            display: "flex",
                            alignItems: "flex-start",
                            justifyContent: "flex-end",
                            px: { xs: 3, md: 4.5 },
                        }}
                    >
                        <a
                            href="https://ente.com/locker"
                            target="_blank"
                            rel="noopener noreferrer"
                            style={{ display: "block", lineHeight: 0 }}
                        >
                            <picture>
                                <source
                                    srcSet="/images/ente-locker-white.svg"
                                    media="(prefers-color-scheme: dark)"
                                />
                                <Box
                                    component="img"
                                    src="/images/ente-locker.svg"
                                    alt="Ente Locker"
                                    sx={{ height: "56px", cursor: "pointer" }}
                                />
                            </picture>
                        </a>
                    </Box>

                    <Box
                        sx={{
                            display: "flex",
                            flexDirection: "column",
                            alignItems: "center",
                            justifyContent: "center",
                            width: "100%",
                            maxWidth: fileInfo?.lockerType
                                ? { xs: 400, md: 640, lg: 720 }
                                : 400,
                            flex: 1,
                            px: 3,
                            py: { xs: "88px", md: 3 },
                        }}
                    >
                        {loading && (
                            <Box
                                sx={{
                                    flex: 1,
                                    display: "flex",
                                    alignItems: "center",
                                    justifyContent: "center",
                                }}
                            >
                                <CircularProgress
                                    sx={{ color: "accent.main" }}
                                    size={32}
                                />
                            </Box>
                        )}

                        {error && !loading && (
                            <Box
                                sx={{
                                    flex: 1,
                                    display: "flex",
                                    alignItems: "center",
                                    justifyContent: "center",
                                    textAlign: "center",
                                    p: 3,
                                }}
                            >
                                <Typography
                                    variant="body"
                                    sx={{ color: "error.main" }}
                                >
                                    {error}
                                </Typography>
                            </Box>
                        )}

                        {fileInfo && iconInfo && !loading && (
                            <>
                                <Box
                                    sx={{
                                        display: "flex",
                                        flexDirection: "column",
                                        alignItems: "center",
                                        justifyContent: "center",
                                        gap: 3,
                                        width: "100%",
                                        marginBottom: fileInfo.lockerType
                                            ? 0
                                            : 4,
                                    }}
                                >
                                    <Box
                                        sx={{
                                            backgroundColor:
                                                iconInfo.backgroundColor,
                                            borderRadius: "20px",
                                            padding: 1.8,
                                            display: "flex",
                                            alignItems: "center",
                                            justifyContent: "center",
                                        }}
                                    >
                                        {iconInfo.icon}
                                    </Box>

                                    <Typography
                                        variant="h5"
                                        sx={{
                                            fontWeight: 600,
                                            fontSize: fileInfo.lockerType
                                                ? "24px"
                                                : "22px",
                                            textAlign: "center",
                                            wordBreak: "break-word",
                                            color: "text.base",
                                        }}
                                    >
                                        {fileInfo.fileName}
                                    </Typography>

                                    {!fileInfo.lockerType && (
                                        <Typography
                                            variant="body"
                                            sx={{
                                                color: "text.muted",
                                                mt: -2,
                                                fontSize: "1rem",
                                            }}
                                        >
                                            {fileInfo.fileSize > 0
                                                ? formatFileSize(
                                                      fileInfo.fileSize,
                                                  )
                                                : "Unknown size"}
                                        </Typography>
                                    )}

                                    {fileInfo.lockerType &&
                                        fileInfo.lockerInfoData && (
                                            <LockerTypeDisplay
                                                type={fileInfo.lockerType}
                                                data={fileInfo.lockerInfoData}
                                                onCopy={handleCopyContent}
                                            />
                                        )}
                                </Box>

                                {!fileInfo.lockerType && (
                                    <Box sx={{ width: "100%", mt: 4 }}>
                                        <Button
                                            variant="contained"
                                            size="large"
                                            fullWidth
                                            onClick={handleDownload}
                                            disabled={downloading}
                                            sx={{
                                                py: 2.5,
                                                fontSize: "1rem",
                                                fontWeight: 600,
                                                bgcolor: "accent.main",
                                                color: "accent.contrastText",
                                                "&:hover": {
                                                    bgcolor: "accent.dark",
                                                },
                                                "&:disabled": {
                                                    bgcolor: "accent.main",
                                                    color: "accent.contrastText",
                                                    opacity: 0.7,
                                                },
                                                borderRadius: "22px",
                                                textTransform: "none",
                                            }}
                                        >
                                            {downloading ? (
                                                <>
                                                    <CircularProgress
                                                        size={20}
                                                        sx={{
                                                            mr: 1,
                                                            color: "accent.contrastText",
                                                        }}
                                                    />
                                                    Downloading...
                                                </>
                                            ) : (
                                                "Download"
                                            )}
                                        </Button>
                                    </Box>
                                )}
                            </>
                        )}
                    </Box>

                    <Notification {...notificationProps} />
                </Box>
            </Box>
        </>
    );
};
