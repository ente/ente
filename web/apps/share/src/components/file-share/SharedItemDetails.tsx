import ArrowBackIcon from "@mui/icons-material/ArrowBack";
import {
    Box,
    Button,
    CircularProgress,
    IconButton,
    Typography,
} from "@mui/material";
import React from "react";
import { formatFileSize } from "../../services/file-share";
import type { DecryptedFileInfo } from "../../types/file-share";
import { getLockerFileIcon } from "../../utils/file-type";
import { LockerTypeDisplay } from "./LockerTypeDisplay";

interface SharedItemDetailsProps {
    itemInfo: DecryptedFileInfo;
    downloading?: boolean;
    onDownload?: () => Promise<void> | void;
    onCopyContent: (content: string) => void;
    onBack?: () => void;
}

export const SharedItemDetails: React.FC<SharedItemDetailsProps> = ({
    itemInfo,
    downloading = false,
    onDownload,
    onCopyContent,
    onBack,
}) => {
    const iconInfo = getLockerFileIcon(itemInfo.fileName, {
        lockerType: itemInfo.lockerType,
    });

    const topMargin = onBack
        ? { xs: 3, md: 5 }
        : itemInfo.lockerType
          ? { xs: 16, md: "20dvh" }
          : 0;

    return (
        <Box
            sx={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                justifyContent:
                    itemInfo.lockerType || onBack ? "flex-start" : "center",
                width: "100%",
                maxWidth: 400,
                mx: "auto",
                flex: 1,
                px: 3,
                pb: 8,
                mt: topMargin,
            }}
        >
            {onBack && (
                <Box sx={{ width: "100%", mb: 4 }}>
                    <IconButton
                        onClick={onBack}
                        aria-label="Back"
                        sx={{
                            color: "text.base",
                            ml: -1,
                            "&:hover": { bgcolor: "fill.faintHover" },
                        }}
                    >
                        <ArrowBackIcon />
                    </IconButton>
                </Box>
            )}

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
                <Box
                    sx={{
                        backgroundColor: iconInfo.backgroundColor,
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
                        fontSize: itemInfo.lockerType ? "24px" : "22px",
                        textAlign: "center",
                        wordBreak: "break-word",
                        color: "text.base",
                    }}
                >
                    {itemInfo.fileName}
                </Typography>

                {!itemInfo.lockerType && (
                    <Typography
                        variant="body"
                        sx={{ color: "text.muted", mt: -2, fontSize: "1rem" }}
                    >
                        {itemInfo.fileSize > 0
                            ? formatFileSize(itemInfo.fileSize)
                            : "Unknown size"}
                    </Typography>
                )}

                {itemInfo.lockerType && itemInfo.lockerInfoData && (
                    <LockerTypeDisplay
                        type={itemInfo.lockerType}
                        data={itemInfo.lockerInfoData}
                        onCopy={onCopyContent}
                    />
                )}
            </Box>

            {!itemInfo.lockerType && onDownload && (
                <Box sx={{ width: "100%", mt: 4 }}>
                    <Button
                        variant="contained"
                        size="large"
                        fullWidth
                        onClick={onDownload}
                        disabled={downloading}
                        sx={{
                            py: 2.5,
                            fontSize: "1rem",
                            fontWeight: 600,
                            bgcolor: "accent.main",
                            color: "accent.contrastText",
                            "&:hover": { bgcolor: "accent.dark" },
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
                                    sx={{ mr: 1, color: "accent.contrastText" }}
                                />
                                Downloading...
                            </>
                        ) : (
                            "Download"
                        )}
                    </Button>
                </Box>
            )}
        </Box>
    );
};
