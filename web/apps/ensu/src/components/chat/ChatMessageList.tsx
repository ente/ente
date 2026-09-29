import { MarkdownRenderer } from "@/components/MarkdownRenderer";
import GeneratingRiveIndicator from "@/components/chat/GeneratingRiveIndicator";
import {
    STREAMING_SELECTION_KEY,
    type BranchSwitcher,
} from "@/services/chat/branching";
import type { ChatAttachment, ChatMessage } from "@/services/chat/store";
import {
    handleExternalLinkClick,
    safeExternalUrl,
} from "@/services/external-links";
import { noteSourceErrorMessage, openNoteDocument } from "@/services/notes";
import {
    ArrowLeft01Icon,
    ArrowRight01Icon,
    Attachment01Icon,
    Cancel01Icon,
    Copy01Icon,
    Edit01Icon,
    RepeatIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Box,
    Chip,
    Dialog,
    DialogContent,
    DialogTitle,
    Divider,
    IconButton,
    Link,
    Stack,
    Typography,
} from "@mui/material";
import type { SxProps, Theme } from "@mui/material/styles";
import type { SystemStyleObject } from "@mui/system";
import { useBaseContext } from "ente-base/context";
import React, { memo, useCallback, useEffect, useMemo, useState } from "react";

interface DocumentAttachment {
    id: string;
    name: string;
    text: string;
    size: number;
}

interface IconProps {
    size: number;
    strokeWidth: number;
}

const sourceLinkSx = {
    border: 0,
    p: 0,
    bgcolor: "transparent",
    fontFamily: "inherit",
    fontSize: "12px",
    lineHeight: "15px",
    fontWeight: 500,
    color: "accent.main",
    cursor: "pointer",
} as const;

const sourceChipSx = {
    height: 25,
    borderRadius: 1,
    bgcolor: "fill.faintHover",
    color: "text.base",
    fontSize: "12px",
    lineHeight: "15px",
    fontWeight: 500,
    cursor: "pointer",
    "& .MuiChip-label": { px: 1.25 },
    "&:hover": { bgcolor: "fill.muted" },
} as const;

const sourceChipLabel = (label: string, sourceCount: number) =>
    sourceCount > 1 ? `${label} +${sourceCount - 1}` : label;

interface ParsedDocuments {
    text: string;
    documents: DocumentAttachment[];
}

export interface ChatMessageListProps {
    messages: ChatMessage[];
    attachmentPreviews: Record<string, string>;
    branchSwitchers: Record<string, BranchSwitcher>;
    loadingPhrase: string | null;
    preparationStatus: string | null;
    loadingDots: number;
    isGenerating: boolean;
    isStreamingOutro: boolean;
    stickToBottom: boolean;
    onStickToBottomChange: (value: boolean) => void;
    scrollContainerRef: React.RefObject<HTMLDivElement | null>;
    onScroll: () => void;
    onUserScrollIntent: () => void;
    onOpenAttachment: (
        message: ChatMessage,
        attachment: ChatAttachment,
    ) => void;
    onEditMessage: (message: ChatMessage) => void;
    onCopyMessage: (text: string) => void;
    onRetryMessage: (message: ChatMessage) => void;
    onPrevBranch: (switcher: BranchSwitcher) => void;
    onNextBranch: (switcher: BranchSwitcher) => void;
    onRequestPreview: (attachment: ChatAttachment, sessionUuid: string) => void;
    parseDocumentBlocks: (text: string) => ParsedDocuments;
    stripHiddenParts: (text: string) => string;
    formatTime: (timestamp: number) => string;
    isDesktopOverlay: boolean;
    userBubbleBackground: string;
    userMessageTextSx: SxProps<Theme>;
    assistantTextSx: SxProps<Theme>;
    assistantMarkdownSx: SxProps<Theme>;
    streamingMessageSx: SystemStyleObject<Theme>;
    actionButtonSx: SxProps<Theme>;
    dialogTitleSx: SystemStyleObject<Theme>;
    dialogCloseButtonSx: SystemStyleObject<Theme>;
    dialogCloseIconProps: IconProps;
    smallIconProps: IconProps;
    actionIconProps: IconProps;
}

interface ImageAttachmentThumbnailProps {
    attachment: ChatAttachment;
    previewUrl?: string;
    onClick: () => void;
}

const ImageAttachmentThumbnail = memo(
    ({ attachment, previewUrl, onClick }: ImageAttachmentThumbnailProps) => {
        const [orientation, setOrientation] = useState<
            "landscape" | "portrait" | "square"
        >("landscape");
        const size =
            orientation === "portrait"
                ? { width: { xs: 112, sm: 124 }, height: { xs: 148, sm: 164 } }
                : orientation === "square"
                  ? {
                        width: { xs: 132, sm: 140 },
                        height: { xs: 132, sm: 140 },
                    }
                  : {
                        width: { xs: 148, sm: 164 },
                        height: { xs: 112, sm: 124 },
                    };

        return (
            <Box
                component="button"
                type="button"
                aria-label={attachment.name || "Open image attachment"}
                onClick={onClick}
                sx={{
                    width: size.width,
                    height: size.height,
                    p: 0,
                    border: 0,
                    borderRadius: 2,
                    bgcolor: "fill.faint",
                    cursor: "pointer",
                    overflow: "hidden",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    color: "text.muted",
                    lineHeight: 0,
                    boxShadow: "0 1px 2px rgba(0, 0, 0, 0.08)",
                }}
            >
                {previewUrl ? (
                    <Box
                        component="img"
                        src={previewUrl}
                        alt={attachment.name || "Image attachment"}
                        onLoad={(event) => {
                            const img = event.currentTarget;
                            if (img.naturalHeight > img.naturalWidth) {
                                setOrientation("portrait");
                            } else if (img.naturalHeight === img.naturalWidth) {
                                setOrientation("square");
                            } else {
                                setOrientation("landscape");
                            }
                        }}
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
                        size={24}
                        strokeWidth={1.7}
                    />
                )}
            </Box>
        );
    },
);

const AiSafetyFooter = memo(() => {
    return (
        <Typography
            variant="small"
            sx={{
                color: "text.muted",
                textAlign: "center",
                width: "100%",
                fontSize: "12px",
                lineHeight: "16px",
            }}
        >
            Ensu can make mistakes. Please double-check key details.
        </Typography>
    );
});

type MessageSource = NonNullable<ChatMessage["sources"]>[number];
type PackSource = Extract<MessageSource, { type: "ensuPack" }>;
type LocalNoteSource = Extract<MessageSource, { type: "localNote" }>;

const PackSourceCard = memo(
    ({ source, number }: { source: PackSource; number: number }) => {
        const { showMiniDialog } = useBaseContext();
        const { citation } = source;
        return (
            <Stack
                sx={{
                    gap: 1.25,
                    p: 2,
                    borderRadius: 1.5,
                    bgcolor: "fill.faint",
                }}
            >
                <Typography variant="mini" sx={{ color: "text.muted" }}>
                    SOURCE {number} · ENSU PACK ·{" "}
                    {citation.datasetLabel.toUpperCase()}
                </Typography>
                <Typography variant="h6">{citation.title}</Typography>
                <Divider sx={{ my: 0.25 }} />
                <Typography variant="small" sx={{ color: "text.muted" }}>
                    {citation.credit}
                </Typography>
                <Stack direction="row" sx={{ gap: 2, flexWrap: "wrap" }}>
                    <Link
                        href={safeExternalUrl(citation.sourceUrl)}
                        target="_blank"
                        rel="noopener noreferrer"
                        underline="hover"
                        onClick={(event) =>
                            handleExternalLinkClick(event, showMiniDialog)
                        }
                        sx={sourceLinkSx}
                    >
                        Open source ↗
                    </Link>
                    <Link
                        href={safeExternalUrl(citation.licenseUrl)}
                        target="_blank"
                        rel="noopener noreferrer"
                        underline="hover"
                        onClick={(event) =>
                            handleExternalLinkClick(event, showMiniDialog)
                        }
                        sx={sourceLinkSx}
                    >
                        {citation.licenseLabel} ↗
                    </Link>
                </Stack>
            </Stack>
        );
    },
);

const LocalNoteSourceCard = memo(
    ({ source, number }: { source: LocalNoteSource; number: number }) => {
        const [openError, setOpenError] = useState<string | null>(null);
        const { reference } = source;
        return (
            <Stack
                sx={{
                    gap: 1.25,
                    p: 2,
                    borderRadius: 1.5,
                    bgcolor: "fill.faint",
                }}
            >
                <Typography variant="mini" sx={{ color: "text.muted" }}>
                    SOURCE {number} · YOUR NOTES
                    {reference.collectionLabel && (
                        <> · {reference.collectionLabel.toUpperCase()}</>
                    )}
                </Typography>
                <Typography variant="h6">{reference.title}</Typography>
                {reference.section && (
                    <Typography variant="small" sx={{ color: "text.muted" }}>
                        {reference.section}
                    </Typography>
                )}
                <Divider sx={{ my: 0.25 }} />
                <Typography variant="small" sx={{ color: "text.muted" }}>
                    {reference.documentId}
                </Typography>
                <Link
                    component="button"
                    type="button"
                    underline="hover"
                    onClick={() => {
                        setOpenError(null);
                        void openNoteDocument(
                            reference.collectionId,
                            reference.documentId,
                            reference.indexedRevision,
                        ).catch((error: unknown) =>
                            setOpenError(noteSourceErrorMessage(error)),
                        );
                    }}
                    sx={{ ...sourceLinkSx, alignSelf: "flex-start" }}
                >
                    Open note ↗
                </Link>
                {openError && (
                    <Typography variant="small" sx={{ color: "critical.main" }}>
                        {openError}
                    </Typography>
                )}
            </Stack>
        );
    },
);

const KnowledgeSourcesDialog = memo(
    ({
        sources,
        onClose,
        dialogTitleSx,
        closeButtonSx,
        closeIconProps,
    }: {
        sources: MessageSource[];
        onClose: () => void;
        dialogTitleSx: SystemStyleObject<Theme>;
        closeButtonSx: SystemStyleObject<Theme>;
        closeIconProps: IconProps;
    }) => (
        <Dialog
            open
            onClose={onClose}
            fullWidth
            maxWidth="sm"
            slotProps={{ paper: { sx: { borderRadius: 3 } } }}
        >
            <DialogTitle
                sx={[
                    dialogTitleSx,
                    {
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "space-between",
                        gap: 1,
                        px: 3,
                        py: 1.5,
                        pr: 1.5,
                    },
                ]}
            >
                <Box component="span">Sources</Box>
                <IconButton
                    aria-label="Close sources"
                    onClick={onClose}
                    sx={closeButtonSx}
                >
                    <HugeiconsIcon icon={Cancel01Icon} {...closeIconProps} />
                </IconButton>
            </DialogTitle>
            <DialogContent sx={{ px: 3, pt: 1, pb: 3 }}>
                <Stack sx={{ gap: 1.5 }}>
                    {sources.map((source, index) =>
                        source.type === "ensuPack" ? (
                            <PackSourceCard
                                key={`${source.type}:${source.citation.datasetId}:${source.citation.sourceUrl}:${index}`}
                                source={source}
                                number={index + 1}
                            />
                        ) : (
                            <LocalNoteSourceCard
                                key={`${source.type}:${source.reference.collectionId}:${source.reference.documentId}:${index}`}
                                source={source}
                                number={index + 1}
                            />
                        ),
                    )}
                </Stack>
            </DialogContent>
        </Dialog>
    ),
);

interface MessageRowProps {
    message: ChatMessage;
    isLastMessage: boolean;
    branchSwitchers: Record<string, BranchSwitcher>;
    loadingPhrase: string | null;
    preparationStatus: string | null;
    loadingDots: number;
    isGenerating: boolean;
    isStreamingOutro: boolean;
    onOpenAttachment: (
        message: ChatMessage,
        attachment: ChatAttachment,
    ) => void;
    onEditMessage: (message: ChatMessage) => void;
    onCopyMessage: (text: string) => void;
    onRetryMessage: (message: ChatMessage) => void;
    onPrevBranch: (switcher: BranchSwitcher) => void;
    onNextBranch: (switcher: BranchSwitcher) => void;
    attachmentPreviews: Record<string, string>;
    onRequestPreview: (attachment: ChatAttachment, sessionUuid: string) => void;
    parseDocumentBlocks: (text: string) => ParsedDocuments;
    stripHiddenParts: (text: string) => string;
    formatTime: (timestamp: number) => string;
    userBubbleBackground: string;
    userMessageTextSx: SxProps<Theme>;
    assistantMarkdownSx: SxProps<Theme>;
    streamingMessageSx: SystemStyleObject<Theme>;
    actionButtonSx: SxProps<Theme>;
    dialogTitleSx: SystemStyleObject<Theme>;
    dialogCloseButtonSx: SystemStyleObject<Theme>;
    dialogCloseIconProps: IconProps;
    smallIconProps: IconProps;
    actionIconProps: IconProps;
}

const MessageRow = memo(
    ({
        message,
        isLastMessage,
        branchSwitchers,
        loadingPhrase,
        preparationStatus,
        loadingDots,
        isGenerating,
        isStreamingOutro,
        onOpenAttachment,
        onEditMessage,
        onCopyMessage,
        onRetryMessage,
        onPrevBranch,
        onNextBranch,
        attachmentPreviews,
        onRequestPreview,
        parseDocumentBlocks,
        stripHiddenParts,
        formatTime,
        userBubbleBackground,
        userMessageTextSx,
        assistantMarkdownSx,
        streamingMessageSx,
        actionButtonSx,
        dialogTitleSx,
        dialogCloseButtonSx,
        dialogCloseIconProps,
        smallIconProps,
        actionIconProps,
    }: MessageRowProps) => {
        const isSelf = message.sender === "self";
        const isStreaming = message.messageUuid === STREAMING_SELECTION_KEY;
        const isSynthetic = !!message.isSynthetic;
        const sources = message.sources ?? [];
        const citations = sources
            .filter(
                (source): source is PackSource => source.type === "ensuPack",
            )
            .map(({ citation }) => citation);
        const localNotes = sources.filter(
            (source): source is LocalNoteSource => source.type === "localNote",
        );
        const packCount = new Set(citations.map(({ datasetId }) => datasetId))
            .size;
        const noteCount = new Set(
            localNotes.map(({ reference }) => reference.collectionId),
        ).size;
        const packSourceLabel = citations.length
            ? sourceChipLabel(citations[0]!.datasetLabel, packCount)
            : undefined;
        const noteSourceLabel = localNotes.length
            ? sourceChipLabel(
                  localNotes[0]!.reference.collectionLabel ?? "Your Notes",
                  noteCount,
              )
            : undefined;
        const [showSources, setShowSources] = useState(false);
        const switcher = branchSwitchers[message.messageUuid];
        const showSwitcher = !isSynthetic && !!switcher && switcher.total > 1;
        const timestamp = formatTime(message.createdAt);
        const assistantMessagePaddingX = "8px";

        const { displayText, copyText, imageAttachments } = useMemo(() => {
            const attachments = message.attachments ?? [];
            const imageAttachments = attachments.filter(
                (attachment) => attachment.kind === "image",
            );
            const parsedDocuments = isSelf
                ? parseDocumentBlocks(message.text)
                : { text: message.text, documents: [] };
            const imageCount = imageAttachments.length;
            const fallbackText = imageCount ? "Attached images" : "";
            const displayText = isSelf
                ? parsedDocuments.text || fallbackText
                : stripHiddenParts(message.text) || fallbackText;
            const copyText = isSelf
                ? displayText
                : stripHiddenParts(message.text);

            return { displayText, copyText, imageAttachments };
        }, [
            isSelf,
            message.attachments,
            message.text,
            parseDocumentBlocks,
            stripHiddenParts,
        ]);
        const showLoadingPlaceholder =
            !isSelf && isStreaming && !displayText.trim();
        const dots = ".".repeat(loadingDots);

        useEffect(() => {
            if (imageAttachments.length === 0) {
                return;
            }

            for (const attachment of imageAttachments) {
                if (!attachmentPreviews[attachment.id]) {
                    onRequestPreview(attachment, message.sessionUuid);
                }
            }
        }, [
            attachmentPreviews,
            imageAttachments,
            message.sessionUuid,
            onRequestPreview,
        ]);

        return (
            <Box
                sx={{
                    display: "flex",
                    justifyContent: isSelf ? "flex-end" : "flex-start",
                    pl: isSelf ? { xs: 0, lg: 10 } : 0,
                    pr: isSelf ? 0 : { xs: 0, lg: 10 },
                    minWidth: 0,
                    maxWidth: "100%",
                }}
            >
                <Stack
                    sx={{
                        width: { xs: "100%", lg: "85%" },
                        maxWidth: { xs: "100%", lg: 720 },
                        alignItems: isSelf ? "flex-end" : "flex-start",
                        minWidth: 0,
                    }}
                >
                    {imageAttachments.length > 0 && (
                        <Stack
                            sx={{
                                gap: 1,
                                mb: 1,
                                width: "fit-content",
                                maxWidth: "100%",
                                alignItems: isSelf ? "flex-end" : "flex-start",
                            }}
                        >
                            {imageAttachments.map((attachment) => (
                                <ImageAttachmentThumbnail
                                    key={attachment.id}
                                    attachment={attachment}
                                    previewUrl={
                                        attachmentPreviews[attachment.id]
                                    }
                                    onClick={() =>
                                        onOpenAttachment(message, attachment)
                                    }
                                />
                            ))}
                        </Stack>
                    )}
                    {isSelf ? (
                        <Box
                            sx={{
                                bgcolor: userBubbleBackground,
                                borderRadius: "18px",
                                px: "12px",
                                py: "12px",
                                alignSelf: "flex-end",
                                maxWidth: "100%",
                                minWidth: 0,
                                overflowWrap: "break-word",
                                wordBreak: "break-word",
                            }}
                        >
                            <Typography
                                variant="message"
                                sx={userMessageTextSx}
                            >
                                {displayText}
                            </Typography>
                        </Box>
                    ) : (
                        <Box
                            sx={{
                                px: assistantMessagePaddingX,
                                py: "12px",
                                alignSelf: "flex-start",
                                width: "fit-content",
                                maxWidth: "100%",
                                minWidth: 0,
                                overflowWrap: "break-word",
                                wordBreak: "break-word",
                                ...(isStreaming ? streamingMessageSx : {}),
                            }}
                        >
                            {isStreaming ? (
                                <Stack
                                    sx={{
                                        gap: showLoadingPlaceholder ? 0 : 0.75,
                                        alignItems: "flex-start",
                                        width: "100%",
                                    }}
                                >
                                    {showLoadingPlaceholder ? null : (
                                        <Box
                                            sx={assistantMarkdownSx}
                                            className="ensu-markdown-streaming"
                                        >
                                            <MarkdownRenderer
                                                content={displayText}
                                                className="markdown-content"
                                            />
                                        </Box>
                                    )}
                                    <GeneratingRiveIndicator
                                        isGenerating={
                                            isGenerating && isStreaming
                                        }
                                        isOutroPhase={isStreamingOutro}
                                        fallbackText={`${loadingPhrase ?? "Generating your reply"}${dots}`}
                                        status={preparationStatus}
                                    />
                                </Stack>
                            ) : (
                                <Stack
                                    sx={{ gap: 1, alignItems: "flex-start" }}
                                >
                                    <Box sx={assistantMarkdownSx}>
                                        <MarkdownRenderer
                                            content={displayText}
                                            className="markdown-content"
                                        />
                                    </Box>
                                    {(packSourceLabel || noteSourceLabel) && (
                                        <Stack
                                            direction="row"
                                            sx={{ gap: 0.75, flexWrap: "wrap" }}
                                        >
                                            {packSourceLabel && (
                                                <Chip
                                                    size="small"
                                                    label={packSourceLabel}
                                                    onClick={() =>
                                                        setShowSources(true)
                                                    }
                                                    sx={sourceChipSx}
                                                />
                                            )}
                                            {noteSourceLabel && (
                                                <Chip
                                                    size="small"
                                                    label={noteSourceLabel}
                                                    onClick={() =>
                                                        setShowSources(true)
                                                    }
                                                    sx={sourceChipSx}
                                                />
                                            )}
                                        </Stack>
                                    )}
                                    {showSources && (
                                        <KnowledgeSourcesDialog
                                            sources={sources}
                                            onClose={() =>
                                                setShowSources(false)
                                            }
                                            dialogTitleSx={dialogTitleSx}
                                            closeButtonSx={dialogCloseButtonSx}
                                            closeIconProps={
                                                dialogCloseIconProps
                                            }
                                        />
                                    )}
                                </Stack>
                            )}
                        </Box>
                    )}

                    <Stack
                        direction="row"
                        sx={{
                            mt: 0.25,
                            gap: 0.5,
                            alignSelf: isSelf ? "flex-end" : "flex-start",
                        }}
                    >
                        {isStreaming ? null : isSynthetic ? (
                            isLastMessage ? (
                                <IconButton
                                    aria-label="Retry"
                                    sx={actionButtonSx}
                                    onClick={() => onRetryMessage(message)}
                                >
                                    <HugeiconsIcon
                                        icon={RepeatIcon}
                                        {...actionIconProps}
                                    />
                                </IconButton>
                            ) : null
                        ) : isSelf ? (
                            <>
                                <IconButton
                                    aria-label="Edit"
                                    sx={actionButtonSx}
                                    onClick={() => onEditMessage(message)}
                                >
                                    <HugeiconsIcon
                                        icon={Edit01Icon}
                                        {...actionIconProps}
                                    />
                                </IconButton>
                                <IconButton
                                    aria-label="Copy"
                                    sx={actionButtonSx}
                                    onClick={() => onCopyMessage(copyText)}
                                >
                                    <HugeiconsIcon
                                        icon={Copy01Icon}
                                        {...actionIconProps}
                                    />
                                </IconButton>
                            </>
                        ) : (
                            <>
                                <IconButton
                                    aria-label="Copy"
                                    sx={actionButtonSx}
                                    onClick={() => onCopyMessage(copyText)}
                                >
                                    <HugeiconsIcon
                                        icon={Copy01Icon}
                                        {...actionIconProps}
                                    />
                                </IconButton>
                                <IconButton
                                    aria-label="Retry"
                                    sx={actionButtonSx}
                                    onClick={() => onRetryMessage(message)}
                                >
                                    <HugeiconsIcon
                                        icon={RepeatIcon}
                                        {...actionIconProps}
                                    />
                                </IconButton>
                            </>
                        )}
                    </Stack>

                    {isStreaming || isSynthetic ? null : (
                        <Stack
                            direction="row"
                            sx={{
                                mt: 0.5,
                                width: "100%",
                                alignItems: "center",
                                gap: 0.75,
                                pl: isSelf ? 0 : assistantMessagePaddingX,
                            }}
                        >
                            {isSelf ? (
                                <>
                                    <Box sx={{ flex: 1 }} />
                                    {showSwitcher && (
                                        <Stack
                                            direction="row"
                                            sx={{
                                                alignItems: "center",
                                                gap: 0.25,
                                            }}
                                        >
                                            <IconButton
                                                aria-label="Previous branch"
                                                sx={actionButtonSx}
                                                onClick={() =>
                                                    onPrevBranch(switcher)
                                                }
                                            >
                                                <HugeiconsIcon
                                                    icon={ArrowLeft01Icon}
                                                    {...smallIconProps}
                                                />
                                            </IconButton>
                                            <Typography
                                                variant="small"
                                                sx={{
                                                    color: "text.muted",
                                                    fontVariantNumeric:
                                                        "tabular-nums",
                                                    minWidth: 40,
                                                    textAlign: "center",
                                                }}
                                            >
                                                {switcher.currentIndex + 1}/
                                                {switcher.total}
                                            </Typography>
                                            <IconButton
                                                aria-label="Next branch"
                                                sx={actionButtonSx}
                                                onClick={() =>
                                                    onNextBranch(switcher)
                                                }
                                            >
                                                <HugeiconsIcon
                                                    icon={ArrowRight01Icon}
                                                    {...smallIconProps}
                                                />
                                            </IconButton>
                                        </Stack>
                                    )}
                                    <Typography
                                        variant="mini"
                                        sx={{
                                            color: "text.muted",
                                            fontVariantNumeric: "tabular-nums",
                                        }}
                                    >
                                        {timestamp}
                                    </Typography>
                                </>
                            ) : (
                                <>
                                    <Typography
                                        variant="mini"
                                        sx={{
                                            color: "text.muted",
                                            fontVariantNumeric: "tabular-nums",
                                        }}
                                    >
                                        {timestamp}
                                    </Typography>
                                    {showSwitcher && (
                                        <Stack
                                            direction="row"
                                            sx={{
                                                alignItems: "center",
                                                gap: 0.25,
                                                ml: 0.75,
                                            }}
                                        >
                                            <IconButton
                                                aria-label="Previous branch"
                                                sx={actionButtonSx}
                                                onClick={() =>
                                                    onPrevBranch(switcher)
                                                }
                                            >
                                                <HugeiconsIcon
                                                    icon={ArrowLeft01Icon}
                                                    {...smallIconProps}
                                                />
                                            </IconButton>
                                            <Typography
                                                variant="small"
                                                sx={{
                                                    color: "text.muted",
                                                    fontVariantNumeric:
                                                        "tabular-nums",
                                                    minWidth: 40,
                                                    textAlign: "center",
                                                }}
                                            >
                                                {switcher.currentIndex + 1}/
                                                {switcher.total}
                                            </Typography>
                                            <IconButton
                                                aria-label="Next branch"
                                                sx={actionButtonSx}
                                                onClick={() =>
                                                    onNextBranch(switcher)
                                                }
                                            >
                                                <HugeiconsIcon
                                                    icon={ArrowRight01Icon}
                                                    {...smallIconProps}
                                                />
                                            </IconButton>
                                        </Stack>
                                    )}
                                    <Box sx={{ flex: 1 }} />
                                </>
                            )}
                        </Stack>
                    )}
                </Stack>
            </Box>
        );
    },
);

export const ChatMessageList = memo(
    ({
        messages,
        attachmentPreviews,
        branchSwitchers,
        loadingPhrase,
        preparationStatus,
        loadingDots,
        isGenerating,
        isStreamingOutro,
        onStickToBottomChange,
        scrollContainerRef,
        onScroll,
        onUserScrollIntent,
        onOpenAttachment,
        onEditMessage,
        onCopyMessage,
        onRetryMessage,
        onPrevBranch,
        onNextBranch,
        onRequestPreview,
        parseDocumentBlocks,
        stripHiddenParts,
        formatTime,
        isDesktopOverlay,
        userBubbleBackground,
        userMessageTextSx,
        assistantMarkdownSx,
        streamingMessageSx,
        actionButtonSx,
        dialogTitleSx,
        dialogCloseButtonSx,
        dialogCloseIconProps,
        smallIconProps,
        actionIconProps,
    }: ChatMessageListProps) => {
        const paddingTop = isDesktopOverlay ? 10 : 2;
        const paddingBottom = 16;

        const EmptyPlaceholder = useCallback(() => {
            return (
                <Stack
                    sx={{
                        gap: 1,
                        height: "100%",
                        alignItems: "center",
                        justifyContent: "flex-start",
                        textAlign: "center",
                        width: "100%",
                        maxWidth: { xs: "100%", lg: 900 },
                        mx: { xs: 0, lg: "auto" },
                        pt: "150px",
                    }}
                >
                    <Typography variant="h2">Welcome</Typography>
                    <Typography variant="small" sx={{ color: "text.muted" }}>
                        Type a message to start chatting
                    </Typography>
                </Stack>
            );
        }, []);

        const lastMessageUuid = messages[messages.length - 1]?.messageUuid;

        const renderMessage = useCallback(
            (_index: number, message: ChatMessage) => {
                const isStreaming =
                    message.messageUuid === STREAMING_SELECTION_KEY;
                return (
                    <MessageRow
                        message={message}
                        isLastMessage={message.messageUuid === lastMessageUuid}
                        branchSwitchers={branchSwitchers}
                        loadingPhrase={isStreaming ? loadingPhrase : null}
                        preparationStatus={
                            isStreaming ? preparationStatus : null
                        }
                        loadingDots={isStreaming ? loadingDots : 0}
                        isGenerating={isGenerating}
                        isStreamingOutro={isStreamingOutro}
                        onOpenAttachment={onOpenAttachment}
                        onEditMessage={onEditMessage}
                        onCopyMessage={onCopyMessage}
                        onRetryMessage={onRetryMessage}
                        onPrevBranch={onPrevBranch}
                        onNextBranch={onNextBranch}
                        attachmentPreviews={attachmentPreviews}
                        onRequestPreview={onRequestPreview}
                        parseDocumentBlocks={parseDocumentBlocks}
                        stripHiddenParts={stripHiddenParts}
                        formatTime={formatTime}
                        userBubbleBackground={userBubbleBackground}
                        userMessageTextSx={userMessageTextSx}
                        assistantMarkdownSx={assistantMarkdownSx}
                        streamingMessageSx={streamingMessageSx}
                        actionButtonSx={actionButtonSx}
                        dialogTitleSx={dialogTitleSx}
                        dialogCloseButtonSx={dialogCloseButtonSx}
                        dialogCloseIconProps={dialogCloseIconProps}
                        smallIconProps={smallIconProps}
                        actionIconProps={actionIconProps}
                    />
                );
            },
            [
                actionButtonSx,
                actionIconProps,
                assistantMarkdownSx,
                attachmentPreviews,
                branchSwitchers,
                dialogCloseButtonSx,
                dialogCloseIconProps,
                dialogTitleSx,
                formatTime,
                isGenerating,
                isStreamingOutro,
                loadingDots,
                loadingPhrase,
                preparationStatus,
                onCopyMessage,
                onEditMessage,
                onNextBranch,
                onOpenAttachment,
                onPrevBranch,
                onRequestPreview,
                onRetryMessage,
                parseDocumentBlocks,
                smallIconProps,
                streamingMessageSx,
                stripHiddenParts,
                userBubbleBackground,
                userMessageTextSx,
                lastMessageUuid,
            ],
        );

        return (
            <Box
                ref={(ref) => {
                    scrollContainerRef.current =
                        (ref as HTMLDivElement | null) ?? null;
                }}
                onScroll={() => {
                    onScroll();
                    const container = scrollContainerRef.current;
                    if (!container) return;
                    const distance =
                        container.scrollHeight -
                        container.scrollTop -
                        container.clientHeight;
                    onStickToBottomChange(distance <= 120);
                }}
                onWheel={() => {
                    onUserScrollIntent();
                }}
                onTouchMove={() => {
                    onUserScrollIntent();
                }}
                sx={{
                    flex: 1,
                    overflowY: "auto",
                    overflowX: "hidden",
                    bgcolor: "background.paper",
                    overscrollBehaviorY: "contain",
                    scrollbarWidth: "thin",
                    "&::-webkit-scrollbar": { width: "8px" },
                    "&::-webkit-scrollbar-thumb": {
                        backgroundColor: "divider",
                        borderRadius: "999px",
                    },
                    "&::-webkit-scrollbar-track": {
                        backgroundColor: "transparent",
                    },
                    minWidth: 0,
                    width: "100%",
                    maxWidth: "100vw",
                    boxSizing: "border-box",
                    px: { xs: 2, sm: 2, md: 3, lg: 4 },
                    pt: paddingTop,
                    pb: paddingBottom,
                    scrollPaddingTop: (theme) => theme.spacing(paddingTop),
                    scrollPaddingBottom: (theme) =>
                        theme.spacing(paddingBottom),
                }}
            >
                {messages.length === 0 ? (
                    <EmptyPlaceholder />
                ) : (
                    <Stack
                        sx={{
                            gap: 3,
                            width: "100%",
                            maxWidth: 900,
                            mx: "auto",
                            minWidth: 0,
                            boxSizing: "border-box",
                        }}
                    >
                        {messages.map((message, index) => (
                            <React.Fragment key={message.messageUuid}>
                                {renderMessage(index, message)}
                            </React.Fragment>
                        ))}
                        <AiSafetyFooter />
                    </Stack>
                )}
            </Box>
        );
    },
);
