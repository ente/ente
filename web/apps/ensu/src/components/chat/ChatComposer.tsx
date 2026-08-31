import type { ChatMessage } from "@/services/chat/store";
import type { DownloadProgress } from "@/services/llm/types";
import {
    Attachment01Icon,
    Cancel01Icon,
    Edit01Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Box,
    Button,
    CircularProgress,
    IconButton,
    LinearProgress,
    Menu,
    MenuItem,
    Stack,
    Typography,
} from "@mui/material";
import type { SxProps, Theme } from "@mui/material/styles";
import React, { forwardRef, memo, useImperativeHandle, useRef } from "react";
import { ChatInput, type ChatInputHandle } from "./ChatInput";

interface IconProps {
    size: number;
    strokeWidth: number;
}

interface DocumentAttachment {
    id: string;
    name: string;
    size: number;
    text: string;
}

interface ImageAttachment {
    id: string;
    name: string;
    size: number;
    file: File;
}

type SuggestedModelStatus =
    | "checking"
    | "missing"
    | "preloading"
    | "downloading"
    | "ready"
    | "error";

export type ChatComposerHandle = ChatInputHandle;

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
    isAttachingImages: boolean;
    pendingImagePreviews: Record<string, string>;
    removePendingDocument: (id: string) => void;
    removePendingImage: (id: string) => void;
    formatBytes: (size: number) => string;
    isGenerating: boolean;
    handleSend: (input: string) => void | Promise<void>;
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
    forwardRef<ChatInputHandle, ChatComposerProps>(function ChatComposer(
        {
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
            isAttachingImages,
            pendingImagePreviews,
            removePendingDocument,
            removePendingImage,
            formatBytes,
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
        },
        ref,
    ) {
        const inputRef = useRef<ChatInputHandle>(null);
        const draftRef = useRef("");

        useImperativeHandle(
            ref,
            () => ({
                focus: () => inputRef.current?.focus(),
                setText: (text) => {
                    draftRef.current = text;
                    inputRef.current?.setText(text);
                },
            }),
            [],
        );

        const isModelPreparationActive =
            modelGateStatus === "checking" ||
            modelGateStatus === "preloading" ||
            modelGateStatus === "downloading";
        const disableAttachmentButton =
            isGenerating ||
            isAttachingImages ||
            isModelPreparationActive ||
            isDownloading ||
            (showImageAttachment && isImageAttachmentLimitReached);

        const pendingImagePreviewRow =
            pendingImages.length > 0 || isAttachingImages ? (
                <Box
                    sx={{
                        display: "flex",
                        flexWrap: "wrap",
                        alignItems: "center",
                        gap: 1,
                        pb: 1,
                    }}
                >
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
                    {isAttachingImages && (
                        <Stack
                            direction="row"
                            spacing={1}
                            sx={{ alignItems: "center", color: "text.muted" }}
                            role="status"
                        >
                            <CircularProgress size={16} color="inherit" />
                            <Typography variant="small">
                                Attaching images...
                            </Typography>
                        </Stack>
                    )}
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
                                                modelGateStatus !== "missing" &&
                                                modelGateStatus !== "error"
                                            }
                                            onClick={() =>
                                                void handleDownloadModel()
                                            }
                                        >
                                            {modelGateStatus === "checking"
                                                ? "Checking..."
                                                : modelGateStatus ===
                                                        "preloading" ||
                                                    modelGateStatus ===
                                                        "downloading"
                                                  ? "Loading..."
                                                  : modelGateStatus === "error"
                                                    ? "Retry"
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

                                    <ChatInput
                                        ref={inputRef}
                                        actionIconProps={actionIconProps}
                                        disableAttachmentButton={
                                            disableAttachmentButton
                                        }
                                        drawerIconButtonSx={drawerIconButtonSx}
                                        handleSend={handleSend}
                                        handleStopGeneration={
                                            handleStopGeneration
                                        }
                                        hasPendingAttachments={
                                            pendingDocuments.length > 0 ||
                                            pendingImages.length > 0
                                        }
                                        isDownloading={isDownloading}
                                        isAttachingImages={isAttachingImages}
                                        isGenerating={isGenerating}
                                        isModelPreparationActive={
                                            isModelPreparationActive
                                        }
                                        initialText={draftRef.current}
                                        onTextChange={(text) => {
                                            draftRef.current = text;
                                        }}
                                        openAttachmentMenu={openAttachmentMenu}
                                        showAttachmentPicker={
                                            showAttachmentPicker
                                        }
                                        stopButtonColor={stopButtonColor}
                                    />
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
    }),
);
