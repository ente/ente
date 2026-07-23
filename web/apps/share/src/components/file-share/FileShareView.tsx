import { Box, Button, CircularProgress, Typography } from "@mui/material";
import { Notification } from "ente-base/components/Notification";
import Head from "next/head";
import React from "react";
import { useFileShare } from "../../hooks/useFileShare";
import { formatFileSize } from "../../services/file-share";
import { getLockerFileIcon } from "../../utils/file-type";
import { LockerTypeDisplay } from "./LockerTypeDisplay";

export const FileShareView: React.FC = () => {
    const {
        loading,
        downloading,
        error,
        fileInfo,
        notificationAttributes,
        handleDownload,
        handleCopyContent,
        setNotificationAttributes,
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
                    minHeight: "100dvh",
                    width: "100%",
                    maxWidth: "100%",
                    bgcolor: "accent.main",
                    display: "flex",
                    flexDirection: "column",
                    alignItems: "center",
                    p: { xs: 1.25, md: 2 },
                    boxSizing: "border-box",
                    overflowX: "hidden",
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
                        overflow: "hidden",
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
                    {/* Ente Locker Logo */}
                    <Box
                        sx={{
                            width: "100%",
                            display: "flex",
                            alignItems: "center",
                            justifyContent: { xs: "center", md: "flex-end" },
                            minHeight: { xs: 88, md: 104 },
                            px: { xs: 3, md: 4.5 },
                            mb: fileInfo?.lockerType ? { xs: 16, md: 0 } : 0,
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

                    {/* Main Container */}
                    <Box
                        sx={{
                            display: "flex",
                            flexDirection: "column",
                            alignItems: "center",
                            justifyContent: fileInfo?.lockerType
                                ? "flex-start"
                                : "center",
                            width: "100%",
                            maxWidth: 400,
                            flex: 1,
                            px: 3,
                            pb: 8,
                            mt: fileInfo?.lockerType
                                ? { xs: 0, md: "20dvh" }
                                : 0,
                        }}
                    >
                        {/* Loading State */}
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

                        {/* Error State */}
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

                        {/* File Info Display */}
                        {fileInfo && iconInfo && !loading && (
                            <>
                                {/* File Info - Centered */}
                                <Box
                                    sx={{
                                        display: "flex",
                                        flexDirection: "column",
                                        alignItems: "center",
                                        justifyContent: "center",
                                        gap: 3,
                                        width: "100%",
                                        marginBottom: 4,
                                    }}
                                >
                                    {/* Large File Icon */}
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

                                    {/* File Name */}
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

                                    {/* File Size - only show if no locker type */}
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

                                    {/* Locker Type Display */}
                                    {fileInfo.lockerType &&
                                        fileInfo.lockerInfoData && (
                                            <LockerTypeDisplay
                                                type={fileInfo.lockerType}
                                                data={fileInfo.lockerInfoData}
                                                onCopy={handleCopyContent}
                                            />
                                        )}
                                </Box>

                                {/* Download Button - Only show if not a LockerInfoType */}
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

                    <Notification
                        open={!!notificationAttributes}
                        onClose={() => setNotificationAttributes(undefined)}
                        attributes={notificationAttributes}
                    />
                </Box>
            </Box>
        </>
    );
};
