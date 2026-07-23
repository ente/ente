import type { ChatMessage } from "@/services/chat/store";
import type { DownloadProgress } from "@/services/llm/types";
import {
    Attachment01Icon,
    Cancel01Icon,
    Edit01Icon,
    Navigation06Icon,
    Upload01Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Box,
    Button,
    IconButton,
    InputBase,
    LinearProgress,
    Menu,
    MenuItem,
    Stack,
    Typography,
} from "@mui/material";
import type { SxProps, Theme } from "@mui/material/styles";
import React, { memo } from "react";

type IconProps = { size: number; strokeWidth: number };

type DocumentAttachment = {
    id: string;
    name: string;
    size: number;
    text: string;
};

type ImageAttachment = { id: string; name: string; size: number; file: File };

type SuggestedModelStatus =
    | "checking"
    | "missing"
    | "preloading"
    | "downloading"
    | "ready"
    | "error";

export interface ChatComposerProps {
    showModelGate: boolean;
    showDownloadProgress: boolean;
    downloadStatus: DownloadProgress | null;
    downloadStatusLabel: string | null;
    downloadSizeLabel: string;
    modelGateStatus: SuggestedModelStatus;
    modelGateError: string | null;
    isDownloading: boolean;
    handleDownloadModel: () => void | Promise<void>;
    editingMessage: ChatMessage | null;
    handleCancelEdit: () => void;
    pendingDocuments: DocumentAttachment[];
    pendingImages: ImageAttachment[];
    pendingImagePreviews: Record<string, string>;
    removePendingDocument: (id: string) => void;
    removePendingImage: (id: string) => void;
    formatBytes: (size: number) => string;
    input: string;
    onInputChange: React.Dispatch<React.SetStateAction<string>>;
    inputRef: React.RefObject<HTMLTextAreaElement | null>;
    isGenerating: boolean;
    handleSend: () => void | Promise<void>;
    handleStopGeneration: () => void;
    showAttachmentPicker: boolean;
    openAttachmentMenu: (event: React.MouseEvent<HTMLElement>) => void;
    attachmentAnchor: HTMLElement | null;
    closeAttachmentMenu: () => void;
    handleAttachmentChoice: (choice: "image" | "document") => void;
    showImageAttachment: boolean;
    isImageAttachmentLimitReached: boolean;
    getDocumentInputProps: () => React.InputHTMLAttributes<HTMLInputElement>;
    getImageInputProps: () => React.InputHTMLAttributes<HTMLInputElement>;
    actionButtonSx: SxProps<Theme>;
    drawerIconButtonSx: SxProps<Theme>;
    smallIconProps: IconProps;
    compactIconProps: IconProps;
    actionIconProps: IconProps;
    stopButtonColor: string;
}

export const ChatComposer = memo(
    ({
        showModelGate,
        showDownloadProgress,
        downloadStatus,
        downloadStatusLabel,
        downloadSizeLabel,
        modelGateStatus,
        modelGateError,
        isDownloading,
        handleDownloadModel,
        editingMessage,
        handleCancelEdit,
        pendingDocuments,
        pendingImages,
        pendingImagePreviews,
        removePendingDocument,
        removePendingImage,
        formatBytes,
        input,
        onInputChange,
        inputRef,
        isGenerating,
        handleSend,
        handleStopGeneration,
        showAttachmentPicker,
        openAttachmentMenu,
        attachmentAnchor,
        closeAttachmentMenu,
        handleAttachmentChoice,
        showImageAttachment,
        isImageAttachmentLimitReached,
        getDocumentInputProps,
        getImageInputProps,
        actionButtonSx,
        drawerIconButtonSx,
        smallIconProps,
        compactIconProps,
        actionIconProps,
        stopButtonColor,
    }: ChatComposerProps) => {
        const disableSend =
            isDownloading ||
            (!isGenerating &&
                !input.trim() &&
                pendingDocuments.length === 0 &&
                pendingImages.length === 0);
        const disableAttachmentButton =
            isGenerating ||
            isDownloading ||
            (showImageAttachment && isImageAttachmentLimitReached);

        const pendingImagePreviewRow =
            pendingImages.length > 0 ? (
                <Box sx={{ display: "flex", flexWrap: "wrap", gap: 1, pb: 1 }}>
                    {pendingImages.map((img) => {
                        const preview = pendingImagePreviews[img.id];
                        return (
                            <Box
                                key={img.id}
                                sx={{
                                    position: "relative",
                                    width: 76,
                                    height: 76,
                                    borderRadius: 2,
                                    bgcolor: "fill.faint",
                                    overflow: "hidden",
                                    display: "flex",
                                    alignItems: "center",
                                    justifyContent: "center",
                                    color: "text.muted",
                                    border: "1px solid",
                                    borderColor: "divider",
                                    boxShadow: "0 8px 24px rgba(0, 0, 0, 0.12)",
                                }}
                            >
                                {preview ? (
                                    <Box
                                        component="img"
                                        src={preview}
                                        alt={img.name}
                                        sx={{
                                            width: "100%",
                                            height: "100%",
                                            objectFit: "cover",
                                            display: "block",
                                        }}
                                    />
                                ) : (
                                    <HugeiconsIcon
                                        icon={Attachment01Icon}
                                        size={22}
                                        strokeWidth={1.7}
                                    />
                                )}
                                <IconButton
                                    aria-label="Remove image"
                                    sx={{
                                        position: "absolute",
                                        top: 4,
                                        right: 4,
                                        width: 20,
                                        height: 20,
                                        p: 0,
                                        borderRadius: "999px",
                                        bgcolor: "rgba(0, 0, 0, 0.45)",
                                        color: "#fff",
                                        backdropFilter: "blur(8px)",
                                        "&:hover": {
                                            bgcolor: "rgba(0, 0, 0, 0.6)",
                                        },
                                    }}
                                    onClick={() => removePendingImage(img.id)}
                                >
                                    <HugeiconsIcon
                                        icon={Cancel01Icon}
                                        size={11}
                                        strokeWidth={smallIconProps.strokeWidth}
                                    />
                                </IconButton>
                            </Box>
                        );
                    })}
                </Box>
            ) : null;

        return (
            <>
                <Box
                    sx={{
                        px: { xs: 2, md: 4 },
                        position: "absolute",
                        left: 0,
                        right: 0,
                        bottom: 16,
                        zIndex: 5,
                        pointerEvents: "none",
                        width: "100%",
                        boxSizing: "border-box",
                    }}
                >
                    <Box
                        sx={{
                            maxWidth: 900,
                            width: "100%",
                            mx: "auto",
                            pointerEvents: "auto",
                            boxSizing: "border-box",
                        }}
                    >
                        {showModelGate ? (
                            <>
                                {showDownloadProgress &&
                                    downloadStatus?.totalBytes && (
                                        <Box
                                            sx={{
                                                display: "flex",
                                                justifyContent: "flex-end",
                                                mb: 1,
                                                px: 1,
                                            }}
                                        >
                                            <Typography
                                                variant="mini"
                                                sx={{
                                                    color: "text.muted",
                                                    fontVariantNumeric:
                                                        "tabular-nums",
                                                }}
                                            >
                                                {formatBytes(
                                                    downloadStatus.bytesDownloaded ??
                                                        0,
                                                )}{" "}
                                                /{" "}
                                                {formatBytes(
                                                    downloadStatus.totalBytes,
                                                )}
                                            </Typography>
                                        </Box>
                                    )}
                                <Stack
                                    sx={{
                                        px: 0,
                                        py: 0,
                                        gap: 0.5,
                                        borderRadius: 2,
                                        bgcolor: "background.paper",
                                        border: "1px solid",
                                        borderColor: "divider",
                                        boxShadow:
                                            "0px 12px 32px rgba(0, 0, 0, 0.12)",
                                        position: "relative",
                                        overflow: "hidden",
                                    }}
                                >
                                    {showDownloadProgress && (
                                        <LinearProgress
                                            variant={
                                                downloadStatus?.totalBytes
                                                    ? "determinate"
                                                    : "indeterminate"
                                            }
                                            value={
                                                downloadStatus?.totalBytes
                                                    ? downloadStatus.percent
                                                    : undefined
                                            }
                                            sx={{
                                                position: "absolute",
                                                top: 0,
                                                left: 0,
                                                right: 0,
                                                height: 3,
                                                borderRadius: "8px 8px 0 0",
                                                pointerEvents: "none",
                                            }}
                                        />
                                    )}
                                    <Stack sx={{ px: 2, py: 2, gap: 1.5 }}>
                                        <Typography variant="h3">
                                            Download to begin using the Chat
                                        </Typography>
                                        <Typography
                                            variant="small"
                                            sx={{ color: "text.muted" }}
                                        >
                                            {downloadStatusLabel ??
                                                (modelGateStatus === "error"
                                                    ? "We couldn't load the model. Try downloading again."
                                                    : downloadSizeLabel)}
                                        </Typography>
                                        {modelGateError && (
                                            <Typography
                                                variant="mini"
                                                sx={{ color: "critical.main" }}
                                            >
                                                {modelGateError}
                                            </Typography>
                                        )}
                                        <Button
                                            variant="contained"
                                            color="accent"
                                            disabled={
                                                modelGateStatus ===
                                                    "downloading" ||
                                                isDownloading
                                            }
                                            onClick={() =>
                                                void handleDownloadModel()
                                            }
                                        >
                                            {modelGateStatus ===
                                                "downloading" || isDownloading
                                                ? "Downloading..."
                                                : "Download"}
                                        </Button>
                                    </Stack>
                                </Stack>
                            </>
                        ) : (
                            <>
                                {pendingImagePreviewRow}
                                <Stack
                                    sx={{
                                        px: 0,
                                        py: 0,
                                        gap: 0.5,
                                        borderRadius: 2,
                                        bgcolor: "background.paper",
                                        border: "1px solid",
                                        borderColor: "divider",
                                        boxShadow:
                                            "0px 12px 32px rgba(0, 0, 0, 0.12)",
                                        position: "relative",
                                        overflow: "hidden",
                                    }}
                                >
                                    {showDownloadProgress && (
                                        <LinearProgress
                                            variant={
                                                downloadStatus?.totalBytes
                                                    ? "determinate"
                                                    : "indeterminate"
                                            }
                                            value={
                                                downloadStatus?.totalBytes
                                                    ? downloadStatus.percent
                                                    : undefined
                                            }
                                            sx={{
                                                position: "absolute",
                                                top: 0,
                                                left: 0,
                                                right: 0,
                                                height: 3,
                                                borderRadius: "8px 8px 0 0",
                                                pointerEvents: "none",
                                            }}
                                        />
                                    )}
                                    {editingMessage && (
                                        <Box
                                            sx={{
                                                display: "flex",
                                                alignItems: "center",
                                                gap: 1,
                                                px: 1.5,
                                                py: 0.5,
                                                borderRadius: 2,
                                                bgcolor: "fill.faint",
                                                borderLeft: "3px solid",
                                                borderLeftColor: "accent.main",
                                            }}
                                        >
                                            <HugeiconsIcon
                                                icon={Edit01Icon}
                                                {...compactIconProps}
                                            />
                                            <Typography
                                                variant="mini"
                                                sx={{ color: "text.muted" }}
                                            >
                                                Editing:
                                            </Typography>
                                            <Typography
                                                variant="mini"
                                                sx={{
                                                    color: "text.base",
                                                    flex: 1,
                                                    overflow: "hidden",
                                                    textOverflow: "ellipsis",
                                                    whiteSpace: "nowrap",
                                                }}
                                            >
                                                {editingMessage.text}
                                            </Typography>
                                            <IconButton
                                                aria-label="Cancel edit"
                                                sx={actionButtonSx}
                                                onClick={handleCancelEdit}
                                            >
                                                <HugeiconsIcon
                                                    icon={Cancel01Icon}
                                                    {...smallIconProps}
                                                />
                                            </IconButton>
                                        </Box>
                                    )}

                                    {pendingDocuments.length > 0 && (
                                        <Box
                                            sx={{
                                                display: "grid",
                                                gridTemplateColumns:
                                                    "repeat(2, minmax(0, 1fr))",
                                                gap: 0.5,
                                            }}
                                        >
                                            {pendingDocuments.map((doc) => (
                                                <Box
                                                    key={doc.id}
                                                    sx={{
                                                        display: "flex",
                                                        alignItems: "center",
                                                        gap: 1,
                                                        px: 1.5,
                                                        py: 0.75,
                                                        borderRadius: 1.5,
                                                        bgcolor: "fill.faint",
                                                        minWidth: 0,
                                                    }}
                                                >
                                                    <Typography
                                                        variant="mini"
                                                        sx={{
                                                            flex: 1,
                                                            color: "text.base",
                                                            overflow: "hidden",
                                                            textOverflow:
                                                                "ellipsis",
                                                            whiteSpace:
                                                                "nowrap",
                                                        }}
                                                    >
                                                        {doc.name}
                                                    </Typography>
                                                    <Typography
                                                        variant="mini"
                                                        sx={{
                                                            color: "text.muted",
                                                        }}
                                                    >
                                                        {formatBytes(doc.size)}
                                                    </Typography>
                                                    <IconButton
                                                        aria-label="Remove document"
                                                        sx={actionButtonSx}
                                                        onClick={() =>
                                                            removePendingDocument(
                                                                doc.id,
                                                            )
                                                        }
                                                    >
                                                        <HugeiconsIcon
                                                            icon={Cancel01Icon}
                                                            {...smallIconProps}
                                                        />
                                                    </IconButton>
                                                </Box>
                                            ))}
                                        </Box>
                                    )}

                                    <Box
                                        sx={{
                                            display: "flex",
                                            alignItems: "center",
                                            gap: 1,
                                            px: 1,
                                            py: 0.75,
                                            borderRadius: 2,
                                            bgcolor:
                                                "color-mix(in srgb, var(--mui-palette-background-default) 45%, var(--mui-palette-background-paper) 55%)",
                                        }}
                                    >
                                        <InputBase
                                            multiline
                                            maxRows={5}
                                            inputRef={inputRef}
                                            placeholder={
                                                isDownloading
                                                    ? "Downloading model..."
                                                    : "Write a message..."
                                            }
                                            value={input}
                                            onChange={(event) =>
                                                onInputChange(
                                                    event.target.value,
                                                )
                                            }
                                            onKeyDown={(event) => {
                                                if (
                                                    event.key === "Enter" &&
                                                    !event.shiftKey
                                                ) {
                                                    event.preventDefault();
                                                    void handleSend();
                                                }
                                            }}
                                            sx={{
                                                flex: 1,
                                                bgcolor: "transparent",
                                                borderRadius: 2,
                                                px: 1.5,
                                                py: 1.5,
                                                minHeight: 48,
                                                display: "flex",
                                                alignItems: "center",
                                                fontFamily: "inherit",
                                                fontSize: "15px",
                                                lineHeight: 1.7,
                                                color: "text.base",
                                                "& textarea": {
                                                    padding: 0,
                                                    margin: 0,
                                                },
                                                "& code": {
                                                    fontFamily:
                                                        'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace',
                                                },
                                            }}
                                        />
                                        {showAttachmentPicker && (
                                            <IconButton
                                                aria-label="Add attachment"
                                                sx={drawerIconButtonSx}
                                                disabled={
                                                    disableAttachmentButton
                                                }
                                                onClick={openAttachmentMenu}
                                            >
                                                <HugeiconsIcon
                                                    icon={Upload01Icon}
                                                    {...actionIconProps}
                                                />
                                            </IconButton>
                                        )}
                                        <IconButton
                                            aria-label={
                                                isGenerating
                                                    ? "Stop"
                                                    : "Send message"
                                            }
                                            onClick={
                                                isGenerating
                                                    ? handleStopGeneration
                                                    : () => void handleSend()
                                            }
                                            disabled={disableSend}
                                            sx={{
                                                width: 44,
                                                height: 44,
                                                borderRadius: 2,
                                                bgcolor: "transparent",
                                                color: isGenerating
                                                    ? "critical.main"
                                                    : "text.muted",
                                                "&:hover": {
                                                    bgcolor: "fill.faint",
                                                },
                                                "&.Mui-disabled": {
                                                    color: "text.faint",
                                                },
                                            }}
                                        >
                                            {isGenerating ? (
                                                <Box
                                                    sx={{
                                                        width: 22,
                                                        height: 22,
                                                        minWidth: 22,
                                                        minHeight: 22,
                                                        borderRadius: "999px",
                                                        bgcolor: "#ffffff",
                                                        display: "inline-flex",
                                                        alignItems: "center",
                                                        justifyContent:
                                                            "center",
                                                    }}
                                                >
                                                    <Box
                                                        component="svg"
                                                        viewBox="0 0 24 24"
                                                        sx={{
                                                            width: 12,
                                                            height: 12,
                                                            display: "block",
                                                        }}
                                                    >
                                                        <path
                                                            d="M4 12C4 8.72077 4 7.08116 4.81382 5.91891C5.1149 5.48891 5.48891 5.1149 5.91891 4.81382C7.08116 4 8.72077 4 12 4C15.2792 4 16.9188 4 18.0811 4.81382C18.5111 5.1149 18.8851 5.48891 19.1862 5.91891C20 7.08116 20 8.72077 20 12C20 15.2792 20 16.9188 19.1862 18.0811C18.8851 18.5111 18.5111 18.8851 18.0811 19.1862C16.9188 20 15.2792 20 12 20C8.72077 20 7.08116 20 5.91891 19.1862C5.48891 18.8851 5.1149 18.5111 4.81382 18.0811C4 16.9188 4 15.2792 4 12Z"
                                                            fill={
                                                                stopButtonColor
                                                            }
                                                        />
                                                    </Box>
                                                </Box>
                                            ) : (
                                                <Box
                                                    sx={{
                                                        transform:
                                                            "rotate(90deg)",
                                                        display: "flex",
                                                    }}
                                                >
                                                    <HugeiconsIcon
                                                        icon={Navigation06Icon}
                                                        {...actionIconProps}
                                                    />
                                                </Box>
                                            )}
                                        </IconButton>
                                    </Box>
                                </Stack>
                            </>
                        )}
                    </Box>
                </Box>

                {showAttachmentPicker && (
                    <>
                        <input {...getDocumentInputProps()} />
                        <input {...getImageInputProps()} />
                        <Menu
                            anchorEl={attachmentAnchor}
                            open={Boolean(attachmentAnchor)}
                            onClose={closeAttachmentMenu}
                            anchorOrigin={{
                                vertical: "top",
                                horizontal: "right",
                            }}
                            transformOrigin={{
                                vertical: "bottom",
                                horizontal: "right",
                            }}
                        >
                            {showImageAttachment && (
                                <MenuItem
                                    disabled={isImageAttachmentLimitReached}
                                    onClick={() =>
                                        handleAttachmentChoice("image")
                                    }
                                >
                                    Image
                                </MenuItem>
                            )}
                        </Menu>
                    </>
                )}
            </>
        );
    },
);
