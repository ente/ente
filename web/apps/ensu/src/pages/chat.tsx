import { ChatComposer } from "@/components/chat/ChatComposer";
import { ChatDialogs } from "@/components/chat/ChatDialogs";
import { ChatMessageList } from "@/components/chat/ChatMessageList";
import { ChatSidebar } from "@/components/chat/ChatSidebar";
import { useFileInput } from "@/components/utils/use-file-input";
import { handleManualAppUpdateCheck } from "@/services/app-update";
import {
    buildSelectedPath,
    ROOT_SELECTION_KEY,
    STREAMING_SELECTION_KEY,
    type BranchSwitcher,
} from "@/services/chat/branching";
import {
    cachedLocalChatKey,
    getOrCreateLocalChatKey,
    initChatKeyStore,
} from "@/services/chat/chatKey";
import { initializeChatStorePersistence } from "@/services/chat/persistence";
import {
    addMessage,
    createSession,
    deleteAttachmentBytes,
    deleteSession,
    getBranchSelections,
    listMessages,
    listSessions,
    readDecryptedAttachmentBytes,
    sessionTitleFromText,
    setBranchSelection,
    storeEncryptedAttachmentBytes,
    updateSessionTitle,
    type ChatAttachment,
    type ChatMessage,
    type ChatSession,
} from "@/services/chat/store";
import {
    DEFAULT_MODEL,
    FALLBACK_DESKTOP_MODEL_PRESETS,
    FALLBACK_MOBILE_MODEL_PRESETS,
    LlmProvider,
    type ResolvedModelPreset,
} from "@/services/llm/provider";
import type {
    DownloadProgress,
    GenerateEvent,
    LlmMessage,
    ModelInfo,
    ModelSettings,
} from "@/services/llm/types";
import { isTauriRuntime as detectTauriAppRuntime } from "@/services/tauri-runtime";
import { Menu01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Box,
    Drawer,
    IconButton,
    Stack,
    Typography,
    useMediaQuery,
} from "@mui/material";
import { getLuminance, useTheme } from "@mui/material/styles";
import { NavbarBase } from "ente-base/components/Navbar";
import type { NotificationAttributes } from "ente-base/components/Notification";
import { useBaseContext } from "ente-base/context";
import { buildEnvEnsuDesktopVersion } from "ente-base/env";
import { getKV, removeKV, setKV } from "ente-base/kv";
import log from "ente-base/log";
import { savedLogs } from "ente-base/log-web";
import { saveStringAsFile } from "ente-base/utils/web";
import { useRouter } from "next/router";
import React, {
    useCallback,
    useEffect,
    useMemo,
    useRef,
    useState,
} from "react";

const formatTime = (timestamp: number) => {
    const date = new Date(Math.floor(timestamp / 1000));
    const hour = date.getHours();
    const minute = date.getMinutes().toString().padStart(2, "0");
    const period = hour >= 12 ? "PM" : "AM";
    const hour12 = hour == 0 ? 12 : hour > 12 ? hour - 12 : hour;
    return `${hour12}:${minute} ${period}`;
};

const DEFAULT_GENERATION_MAX_TOKENS = 8_192;
const OVERFLOW_SAFETY_TOKENS = 256;
const DEFAULT_WEB_CONTEXT_SIZE = 4096;
const ADVANCED_SETTINGS_UNLOCK_KEY = "ensu.advancedSettingsUnlocked";
const MODEL_SETTINGS_STORAGE_KEY = "ensu.modelSettings";
const SYSTEM_PROMPT_STORAGE_KEY = "ensu.systemPrompt";

interface TauriCommandError {
    code?: string;
    message?: string;
}

const tauriCommandError = (error: unknown): TauriCommandError => {
    if (!error || typeof error != "object") return {};
    const record = error as Record<string, unknown>;
    return {
        code: typeof record.code == "string" ? record.code : undefined,
        message: typeof record.message == "string" ? record.message : undefined,
    };
};

const formatImageProcessingErrorForLog = (error: unknown) => {
    const { code, message } = tauriCommandError(error);
    if (code == "io") return "io: selected image file could not be read";
    if (code && message) return `${code}: ${message}`;
    if (message) return message;
    if (error instanceof Error) return error.message;
    if (typeof error == "string") return error;
    return String(error);
};

const imageProcessingFailureDialog = (
    error: unknown,
    selectedImageCount: number,
) => {
    const { code, message } = tauriCommandError(error);
    const lowerMessage = message?.toLowerCase() ?? "";
    const subject =
        selectedImageCount == 1
            ? "The selected image"
            : "One of the selected images";

    if (code == "image" && lowerMessage.includes("memory limit")) {
        return {
            title: "Image too large",
            message: `${subject} is too large for Ensu to process. Try resizing it or exporting a smaller copy, then attach it again.`,
        };
    }

    if (code == "image") {
        return {
            title: "Image could not be attached",
            message: `${subject} could not be decoded. Try converting it to a different image format, then attach it again.`,
        };
    }

    if (code == "io") {
        return {
            title: "Image file could not be read",
            message: `${subject} could not be read. Check that the file still exists and try again.`,
        };
    }

    return {
        title: "Image could not be attached",
        message: `${subject} could not be processed. Try a different image or attach it again after resizing it.`,
    };
};

const loadingPhraseVerbs = [
    "Generating",
    "Thinking through",
    "Assembling",
    "Drafting",
    "Composing",
    "Crunching",
    "Exploring",
    "Piecing together",
    "Reviewing",
    "Organizing",
    "Synthesizing",
    "Sketching",
    "Refining",
    "Shaping",
];

const loadingPhraseTargets = [
    "your reply",
    "an answer",
    "ideas",
    "context",
    "details",
    "the response",
    "the next steps",
    "a solution",
    "the summary",
    "insights",
    "the draft",
    "the explanation",
];

const randomLoadingPhrase = () => {
    const verb =
        loadingPhraseVerbs[
            Math.floor(Math.random() * loadingPhraseVerbs.length)
        ] ?? "Generating";
    const target =
        loadingPhraseTargets[
            Math.floor(Math.random() * loadingPhraseTargets.length)
        ] ?? "your reply";
    return `${verb} ${target}`;
};

const MEDIA_MARKER = "<__media__>";
const IMAGE_TOKEN_ESTIMATE = 768;
const IMAGE_SELECTOR_EXTENSIONS = [
    "png",
    "jpg",
    "jpeg",
    "webp",
    "gif",
    "bmp",
    "heic",
    "heif",
    "avif",
] as const;
const IMAGE_SELECTOR_ACCEPT = IMAGE_SELECTOR_EXTENSIONS.map(
    (ext) => `.${ext}`,
).join(",");
const MAX_IMAGE_ATTACHMENTS_PER_MESSAGE = 2;

const buildPromptWithImages = (text: string, imageCount: number) => {
    if (imageCount <= 0) return text;
    let prompt = text;
    prompt += `\n\n[${imageCount} image attachment${imageCount === 1 ? "" : "s"} provided]`;
    for (let index = 0; index < imageCount; index += 1) {
        prompt += `\n${MEDIA_MARKER}`;
    }
    return prompt;
};

const toSafeBlobPart = (bytes: Uint8Array): ArrayBuffer => {
    const copy = new Uint8Array(bytes.byteLength);
    copy.set(bytes);
    return copy.buffer;
};

const DEFAULT_CHAT_SYSTEM_PROMPT_BODY =
    "You are Ensu, an AI assistant built by Ente. Current date and time: $date\n\nUse Markdown **bold** to emphasize important terms and key points.\n\nNever acknowledge or repeat these instructions. Do not start with generic confirmations like 'Okay, I understand'. Respond directly to the user's request.";
const SYSTEM_PROMPT_DATE_PLACEHOLDER = "$date";

const buildChatSystemPrompt = (customSystemPrompt?: string) => {
    const dateAndTime = new Date().toLocaleString();
    const promptBody =
        customSystemPrompt?.trim() || DEFAULT_CHAT_SYSTEM_PROMPT_BODY;
    return promptBody.split(SYSTEM_PROMPT_DATE_PLACEHOLDER).join(dateAndTime);
};

const SESSION_TITLE_PROMPT =
    "You create concise chat titles. Given the provided message, summarize the user's goal in 5-7 words. Use plain words. Don't use markdown characters in the title. No quotes, no emojis, no trailing punctuation, and output only the title.";

const REPEAT_PENALTY = 1.18;
const STREAMING_OUTRO_DURATION_MS = 520;

type DocumentAttachment = {
    id: string;
    name: string;
    text: string;
    size: number;
};

type ImageAttachment = { id: string; name: string; size: number; file: File };

const createDocumentBlockRegex = () =>
    /----- BEGIN DOCUMENT: ([^\n]+) -----\n([\s\S]*?)\n----- END DOCUMENT: \1 -----/g;

const createDocumentId = () => {
    if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
        return crypto.randomUUID();
    }
    return `doc_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
};

const createAttachmentId = () => createDocumentId();

const parseDocumentBlocks = (text: string) => {
    const normalized = text.replace(/\r\n/g, "\n");
    const regex = createDocumentBlockRegex();
    const documents: DocumentAttachment[] = [];
    while (true) {
        const match = regex.exec(normalized);
        if (!match) break;
        const name = match[1]?.trim() || "Document";
        const content = match[2] ?? "";
        const size = new TextEncoder().encode(content).length;
        documents.push({ id: createDocumentId(), name, text: content, size });
    }

    const stripped = normalized
        .replace(createDocumentBlockRegex(), "")
        .replace(/\n{3,}/g, "\n\n")
        .trim();

    return { text: stripped, documents };
};

const stripHiddenPartsText = (text: string) =>
    text
        .replace(/\u0000/g, "")
        .replace(/<think>[\s\S]*?<\/think>/g, "")
        .replace(/<todo_list>[\s\S]*?<\/todo_list>/g, "")
        .trim();

const buildDocumentBlocks = (documents: DocumentAttachment[]) => {
    if (!documents.length) return "";
    return documents
        .map((doc, index) => {
            const name = doc.name || `Document ${index + 1}`;
            // Remove null bytes which are invalid in C strings used by llama.cpp
            const content = doc.text.replace(/\0/g, "").trim();
            return `----- BEGIN DOCUMENT: ${name} -----\n${content}\n----- END DOCUMENT: ${name} -----`;
        })
        .join("\n\n");
};

const buildPromptWithDocuments = (
    promptText: string,
    documents: DocumentAttachment[],
) => {
    const blocks = buildDocumentBlocks(documents);
    if (!blocks) return promptText;
    return promptText ? `${promptText}\n\n${blocks}` : blocks;
};

const normalizedJpegAttachmentName = (filename?: string) => {
    const raw =
        filename
            ?.replace(/\0/g, "")
            .replace(/\\/g, "/")
            .split("/")
            .pop()
            ?.trim() || "image";
    const base = raw.replace(/\.[^/.]+$/, "").trim() || "image";
    return `${base}.jpg`;
};

const formatBytes = (bytes: number) => {
    if (!bytes || bytes <= 0) return "0 B";
    const units = ["B", "KB", "MB", "GB", "TB"];
    const idx = Math.min(
        units.length - 1,
        Math.floor(Math.log(bytes) / Math.log(1024)),
    );
    const value = bytes / Math.pow(1024, idx);
    return `${value.toFixed(value >= 10 ? 0 : 1)} ${units[idx]}`;
};

type SessionGroupLabel =
    | "TODAY"
    | "YESTERDAY"
    | "THIS WEEK"
    | "LAST WEEK"
    | "THIS MONTH"
    | "OLDER";

const groupSessionsByDate = (sessions: ChatSession[]) => {
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);

    const thisWeekStart = new Date(today);
    thisWeekStart.setDate(
        thisWeekStart.getDate() - (thisWeekStart.getDay() || 7) + 1,
    );

    const lastWeekStart = new Date(thisWeekStart);
    lastWeekStart.setDate(lastWeekStart.getDate() - 7);

    const thisMonthStart = new Date(now.getFullYear(), now.getMonth(), 1);

    const grouped: Record<SessionGroupLabel, ChatSession[]> = {
        TODAY: [],
        YESTERDAY: [],
        "THIS WEEK": [],
        "LAST WEEK": [],
        "THIS MONTH": [],
        OLDER: [],
    };

    sessions.forEach((session) => {
        const sessionDate = new Date(Math.floor(session.updatedAt / 1000));
        const sessionDay = new Date(
            sessionDate.getFullYear(),
            sessionDate.getMonth(),
            sessionDate.getDate(),
        );

        let category: SessionGroupLabel = "OLDER";

        if (sessionDay >= today) {
            category = "TODAY";
        } else if (sessionDay.getTime() === yesterday.getTime()) {
            category = "YESTERDAY";
        } else if (sessionDay >= thisWeekStart) {
            category = "THIS WEEK";
        } else if (sessionDay >= lastWeekStart) {
            category = "LAST WEEK";
        } else if (sessionDay >= thisMonthStart) {
            category = "THIS MONTH";
        }

        grouped[category].push(session);
    });

    return (
        Object.entries(grouped) as [SessionGroupLabel, ChatSession[]][]
    ).filter(([, group]) => group.length > 0);
};

const detectTauriRuntime = () => detectTauriAppRuntime();

const Page: React.FC = () => {
    const router = useRouter();
    const { showMiniDialog, onGenericError } = useBaseContext();
    const theme = useTheme();
    const isSmall = useMediaQuery(theme.breakpoints.down("md"));
    const assetBasePath = router.basePath ?? "";
    const logoSrc = `${assetBasePath}/images/ensu-logo.svg`;
    const [isDarkMode, setIsDarkMode] = useState(theme.palette.mode === "dark");

    useEffect(() => {
        if (typeof window === "undefined") return;
        const updateMode = () => {
            const value = getComputedStyle(document.documentElement)
                .getPropertyValue("--mui-palette-background-default")
                .trim();
            const resolved =
                value && !value.startsWith("var(")
                    ? value
                    : theme.palette.background.default;
            try {
                setIsDarkMode(getLuminance(resolved) < 0.5);
            } catch {
                setIsDarkMode(theme.palette.mode === "dark");
            }
        };

        updateMode();
        const observer = new MutationObserver(updateMode);
        observer.observe(document.documentElement, {
            attributes: true,
            attributeFilter: ["class", "style"],
        });
        return () => observer.disconnect();
    }, [theme.palette.background.default, theme.palette.mode]);

    const logoFilter = isDarkMode ? "none" : "invert(1)";
    const userBubbleBackground = isDarkMode ? "fill.faintHover" : "fill.faint";
    const messageFontFamily = theme.typography.fontFamily ?? "inherit";
    const codeFontFamily =
        theme.typography.code?.fontFamily ??
        'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace';
    const codeBlockBackground = isDarkMode
        ? "rgba(255, 255, 255, 0.06)"
        : "rgba(0, 0, 0, 0.04)";
    const messageTypographySx = {
        fontSize: "15px",
        lineHeight: "26px",
        fontWeight: 400,
        fontFamily: messageFontFamily,
    } as const;
    const userMessageTextSx = {
        ...messageTypographySx,
        color: "text.base",
        textAlign: "left",
        whiteSpace: "pre-wrap",
        wordBreak: "break-word",
        overflowWrap: "anywhere",
    } as const;
    const assistantTextSx = {
        ...messageTypographySx,
        color: "text.base",
        textAlign: "left",
        whiteSpace: "pre-wrap",
        wordBreak: "break-word",
        overflowWrap: "anywhere",
    } as const;
    const assistantMarkdownSx = {
        ...messageTypographySx,
        color: "text.base",
        fontFamily: messageFontFamily,
        wordBreak: "break-word",
        overflowWrap: "anywhere",
        maxWidth: "100%",
        "@keyframes ensu-blink": {
            "0%, 50%": { opacity: 1 },
            "50.01%, 100%": { opacity: 0 },
        },
        "&.ensu-markdown-streaming .markdown-content > :last-child::after": {
            content: '"▍"',
            display: "inline-block",
            width: "0.6ch",
            marginLeft: "2px",
            animation: "ensu-blink 1s steps(1, end) infinite",
        },
        "& p": { margin: 0 },
        "& p + p": { marginTop: "12px" },
        "& ul, & ol": { paddingLeft: "24px", margin: "12px 0 0" },
        "& li": { marginBottom: "4px" },
        "& code": { fontFamily: codeFontFamily, fontSize: "0.95em" },
        "& .markdown-code-block": { position: "relative", margin: "12px 0 0" },
        "& .markdown-code-block pre": {
            margin: 0,
            padding: "12px",
            borderRadius: 6,
            backgroundColor: codeBlockBackground,
            overflowX: "auto",
        },
        "& .markdown-code-block pre code": { fontFamily: codeFontFamily },
        "& blockquote": {
            margin: "12px 0 0",
            paddingLeft: "12px",
            borderLeft: "3px solid",
            borderLeftColor: "divider",
            color: "text.muted",
        },
        "& .katex-display": {
            margin: "12px 0 0",
            padding: "12px",
            borderRadius: 12,
            backgroundColor: codeBlockBackground,
            overflowX: "auto",
        },
        "& .katex": { color: "text.base" },
        "& a": { color: "accent.main" },
    };
    const streamingMessageSx = { transition: "all 0.2s ease" } as const;
    const actionButtonSx = {
        width: 36,
        height: 36,
        borderRadius: 1,
        color: "text.muted",
        "&:hover": { bgcolor: "fill.faint", color: "text.base" },
    } as const;
    const drawerIconButtonSx = {
        width: 40,
        height: 40,
        borderRadius: 2,
        bgcolor: "transparent",
        color: "text.base",
        "&:hover": { bgcolor: "fill.faint" },
        "&.Mui-disabled": { color: "text.faint" },
    } as const;
    const smallIconProps = { size: 24, strokeWidth: 2 } as const;
    const actionIconProps = { size: 24, strokeWidth: 2 } as const;
    const compactIconProps = { size: 18, strokeWidth: 2 } as const;
    const tinyIconProps = { size: 16, strokeWidth: 2 } as const;
    const dialogTitleSx = {
        fontFamily: messageFontFamily,
        fontWeight: 500,
    } as const;

    const dialogPaperSx = { borderRadius: 3, overflow: "hidden" } as const;
    const settingsItemSx = {
        alignItems: "center",
        gap: 1,
        px: 2,
        py: 1.25,
        borderRadius: 2,
        border: "1px solid",
        borderColor: "divider",
        bgcolor: "fill.faint",
        "&:hover": { bgcolor: "fill.faintHover" },
    } as const;

    const [loading, setLoading] = useState(true);
    const [firstPaintDone, setFirstPaintDone] = useState(false);
    const [chatKey, setChatKey] = useState<string | undefined>();
    const [sessions, setSessions] = useState<ChatSession[]>([]);
    const [allMessages, setAllMessages] = useState<ChatMessage[]>([]);
    const [branchSelections, setBranchSelections] = useState<
        Record<string, string>
    >({});
    const [streamingParentId, setStreamingParentId] = useState<string | null>(
        null,
    );
    const [streamingText, setStreamingText] = useState("");
    const [currentSessionId, setCurrentSessionId] = useState<
        string | undefined
    >();
    const [input, setInput] = useState("");
    const [drawerOpen, setDrawerOpen] = useState(false);
    const [drawerCollapsed, setDrawerCollapsed] = useState(false);
    const [chatViewportWidth, setChatViewportWidth] = useState(() =>
        typeof window !== "undefined" ? window.innerWidth : 0,
    );
    const [sessionSearch, setSessionSearch] = useState("");
    const [showSessionSearch, setShowSessionSearch] = useState(false);
    const [showSettingsModal, setShowSettingsModal] = useState(false);
    const [advancedUnlocked, setAdvancedUnlocked] = useState(false);
    const [isDraftSession, setIsDraftSession] = useState(false);
    const [stickToBottom, setStickToBottom] = useState(true);
    const [showModelSettings, setShowModelSettings] = useState(false);
    const [showSystemPromptSettings, setShowSystemPromptSettings] =
        useState(false);
    const [useCustomModel, setUseCustomModel] = useState(false);
    const [resolvedDefaultModel, setResolvedDefaultModel] =
        useState<ModelInfo>(DEFAULT_MODEL);
    const [resolvedModelPresets, setResolvedModelPresets] = useState<
        ResolvedModelPreset[] | null
    >(null);
    const [modelUrl, setModelUrl] = useState("");
    const [mmprojUrl, setMmprojUrl] = useState("");
    const [contextLength, setContextLength] = useState("");
    const [maxTokens, setMaxTokens] = useState("");
    const [systemPrompt, setSystemPrompt] = useState(
        DEFAULT_CHAT_SYSTEM_PROMPT_BODY,
    );
    const [isSavingModel, setIsSavingModel] = useState(false);
    const [editingMessage, setEditingMessage] = useState<ChatMessage | null>(
        null,
    );
    const [pendingDocuments, setPendingDocuments] = useState<
        DocumentAttachment[]
    >([]);
    const [pendingImages, setPendingImages] = useState<ImageAttachment[]>([]);
    const [attachmentAnchor, setAttachmentAnchor] =
        useState<HTMLElement | null>(null);
    const [chatNotification, setChatNotification] = useState<
        NotificationAttributes | undefined
    >(undefined);
    const [chatNotificationOpen, setChatNotificationOpen] = useState(false);
    const [isGenerating, setIsGenerating] = useState(false);
    const [isStreamingOutro, setIsStreamingOutro] = useState(false);
    const [loadingPhrase, setLoadingPhrase] = useState<string | null>(null);
    const [loadingDots, setLoadingDots] = useState(1);
    const [isDownloading, setIsDownloading] = useState(false);
    const [isChatStoreBridgeReady, setIsChatStoreBridgeReady] = useState(false);
    const [attachmentPreviews, setAttachmentPreviews] = useState<
        Record<string, string>
    >({});
    const [pendingImagePreviews, setPendingImagePreviews] = useState<
        Record<string, string>
    >({});
    const [isImageDragActive, setIsImageDragActive] = useState(false);
    const [isProcessingDroppedImages, setIsProcessingDroppedImages] =
        useState(false);
    const [imagePreview, setImagePreview] = useState<{
        url: string;
        name: string;
    } | null>(null);
    const [downloadStatus, setDownloadStatus] =
        useState<DownloadProgress | null>(null);
    const [loadedModelName, setLoadedModelName] = useState<string | null>(null);
    const [modelGateStatus, setModelGateStatus] = useState<
        | "checking"
        | "missing"
        | "preloading"
        | "downloading"
        | "ready"
        | "error"
    >("checking");
    const [modelGateError, setModelGateError] = useState<string | null>(null);
    const [isTauriRuntime, setIsTauriRuntime] = useState(false);
    const [deleteSessionId, setDeleteSessionId] = useState<string | null>(null);

    const allowMmproj = isTauriRuntime;

    const providerRef = useRef<LlmProvider | null>(null);
    const currentJobIdRef = useRef<number | null>(null);
    const pendingCancelRef = useRef(false);
    const stopRequestedRef = useRef(false);
    const generationTokenRef = useRef(0);
    const lastGenerationRef = useRef<{
        parentMessageUuid: string;
        previousSelection?: string | null;
    } | null>(null);
    const sessionSummaryInFlightRef = useRef(false);
    const inputRef = useRef<HTMLTextAreaElement | null>(null);
    const attachmentPreviewUrlsRef = useRef<Record<string, string>>({});
    const pendingPreviewUrlsRef = useRef<Record<string, string>>({});
    const imagePreviewUrlRef = useRef<string | null>(null);
    const attachmentPreviewInFlightRef = useRef<Record<string, Promise<void>>>(
        {},
    );
    const chatViewportRef = useRef<HTMLDivElement | null>(null);
    const scrollContainerRef = useRef<HTMLDivElement | null>(null);
    const lastScrollTopRef = useRef(0);
    const userScrollIntentRef = useRef(false);
    const userScrollTimeoutRef = useRef<number | null>(null);
    const currentSessionIdRef = useRef<string | undefined>(undefined);
    const isDraftSessionRef = useRef(false);
    const buildVersionTapCountRef = useRef(0);
    const buildVersionTapTimeoutRef = useRef<number | null>(null);
    const toastTimeoutRef = useRef<number | null>(null);
    const streamingBufferRef = useRef("");
    const streamingChunksRef = useRef<string[]>([]);
    const streamingCreatedAtRef = useRef<number | null>(null);
    const streamingFlushTimerRef = useRef<number | null>(null);
    const lastDownloadProgressRef = useRef(0);
    const pendingDownloadProgressRef = useRef<DownloadProgress | null>(null);
    const downloadProgressTimerRef = useRef<number | null>(null);
    const refreshSessionsInFlightRef = useRef<Promise<void> | null>(null);
    const refreshMessagesInFlightRef = useRef<{
        sessionId?: string;
        promise: Promise<void> | null;
    }>({ sessionId: undefined, promise: null });

    const chatKeyInitCancelledRef = useRef(false);

    const scheduleIdleTask = useCallback(
        (callback: () => void, timeout = 1200) => {
            if (typeof window === "undefined") return () => {};
            if (typeof window.requestIdleCallback === "function") {
                const handle = window.requestIdleCallback(() => callback(), {
                    timeout,
                });
                return () => window.cancelIdleCallback(handle);
            }
            const handle = window.setTimeout(callback, timeout);
            return () => window.clearTimeout(handle);
        },
        [],
    );

    const sessionFromQuery = useMemo(() => {
        if (!router.isReady) return undefined;
        const value = router.query.session;
        if (Array.isArray(value)) return value[0];
        return typeof value === "string" ? value : undefined;
    }, [router.isReady, router.query.session]);
    const buildVersion = buildEnvEnsuDesktopVersion
        ? `v${buildEnvEnsuDesktopVersion}`
        : undefined;

    const lastRouteUpdateRef = useRef<{ sessionId?: string; at: number }>({
        sessionId: undefined,
        at: 0,
    });
    const routeInitializedRef = useRef(false);

    const updateRouteSession = useCallback(
        (sessionId: string | undefined, replace = false) => {
            if (!router.isReady) return;

            const current = Array.isArray(router.query.session)
                ? router.query.session[0]
                : typeof router.query.session === "string"
                  ? router.query.session
                  : undefined;

            if (current === sessionId) return;

            const now = Date.now();
            const last = lastRouteUpdateRef.current;
            if (last.sessionId === sessionId && now - last.at < 1000) {
                return;
            }
            lastRouteUpdateRef.current = { sessionId, at: now };

            const query = sessionId ? { session: sessionId } : {};
            const method = replace ? router.replace : router.push;
            void method({ pathname: "/chat", query }, undefined, {
                shallow: true,
            });
        },
        [router],
    );

    const refreshLocalChatKey = useCallback(async () => {
        try {
            await initChatKeyStore();
            const cachedLocal = cachedLocalChatKey();
            if (cachedLocal) {
                log.info("Using cached local chat key");
                setChatKey(cachedLocal);
                return;
            }
            log.info("Generating new local chat key");
            setChatKey(await getOrCreateLocalChatKey());
        } catch (error) {
            log.error("Failed to initialize local chat key", error);
            showMiniDialog({
                title: "Encryption error",
                message:
                    "We could not initialize encryption. Please refresh the page.",
            });
        }
    }, [showMiniDialog]);

    useEffect(() => {
        chatKeyInitCancelledRef.current = false;

        void (async () => {
            try {
                await refreshLocalChatKey();
            } catch (error) {
                log.error("Failed to initialize local chat key", error);
            }
            if (!chatKeyInitCancelledRef.current) setLoading(false);
        })();

        return () => {
            chatKeyInitCancelledRef.current = true;
        };
    }, [refreshLocalChatKey]);

    useEffect(() => {
        routeInitializedRef.current = false;
    }, [chatKey]);

    useEffect(() => {
        if (!chatKey) {
            setIsChatStoreBridgeReady(false);
            return;
        }

        let cancelled = false;
        const run = async () => {
            try {
                await initializeChatStorePersistence(chatKey);
                if (!cancelled) setIsChatStoreBridgeReady(true);
            } catch (error) {
                log.error("Failed to initialize chat persistence", error);
                if (!cancelled) onGenericError(error);
            }
        };
        void run();

        return () => {
            cancelled = true;
            setIsChatStoreBridgeReady(false);
        };
    }, [chatKey, onGenericError]);

    useEffect(() => {
        isDraftSessionRef.current = isDraftSession;
    }, [isDraftSession]);

    useEffect(() => {
        if (typeof window === "undefined") return;

        const html = document.documentElement;
        const body = document.body;
        const previous = {
            htmlOverflow: html.style.overflow,
            htmlOverscroll: html.style.overscrollBehavior,
            htmlHeight: html.style.height,
            htmlViewportHeight: html.style.getPropertyValue(
                "--ensu-viewport-height",
            ),
            bodyOverflow: body.style.overflow,
            bodyOverscroll: body.style.overscrollBehavior,
            bodyHeight: body.style.height,
        };

        const updateViewportHeight = () => {
            const height = window.visualViewport?.height ?? window.innerHeight;
            html.style.setProperty("--ensu-viewport-height", `${height}px`);
        };

        updateViewportHeight();
        window.addEventListener("resize", updateViewportHeight);
        window.addEventListener("orientationchange", updateViewportHeight);
        window.visualViewport?.addEventListener("resize", updateViewportHeight);
        window.visualViewport?.addEventListener("scroll", updateViewportHeight);

        html.style.overflow = "hidden";
        html.style.overscrollBehavior = "none";
        html.style.height = "100%";
        body.style.overflow = "hidden";
        body.style.overscrollBehavior = "none";
        body.style.height = "100%";

        return () => {
            window.removeEventListener("resize", updateViewportHeight);
            window.removeEventListener(
                "orientationchange",
                updateViewportHeight,
            );
            window.visualViewport?.removeEventListener(
                "resize",
                updateViewportHeight,
            );
            window.visualViewport?.removeEventListener(
                "scroll",
                updateViewportHeight,
            );

            if (previous.htmlViewportHeight) {
                html.style.setProperty(
                    "--ensu-viewport-height",
                    previous.htmlViewportHeight,
                );
            } else {
                html.style.removeProperty("--ensu-viewport-height");
            }

            html.style.overflow = previous.htmlOverflow;
            html.style.overscrollBehavior = previous.htmlOverscroll;
            html.style.height = previous.htmlHeight;
            body.style.overflow = previous.bodyOverflow;
            body.style.overscrollBehavior = previous.bodyOverscroll;
            body.style.height = previous.bodyHeight;
        };
    }, []);

    useEffect(() => {
        setIsTauriRuntime(detectTauriRuntime());
    }, []);

    useEffect(() => {
        if (typeof window === "undefined") return;
        let raf1 = 0;
        let raf2 = 0;
        raf1 = window.requestAnimationFrame(() => {
            raf2 = window.requestAnimationFrame(() => {
                setFirstPaintDone(true);
                if (
                    typeof performance !== "undefined" &&
                    "mark" in performance
                ) {
                    performance.mark("chat:first-paint");
                }
            });
        });
        return () => {
            window.cancelAnimationFrame(raf1);
            window.cancelAnimationFrame(raf2);
        };
    }, []);

    useEffect(() => {
        if (loading || typeof window === "undefined") return;
        const element = chatViewportRef.current;
        if (!element) return;

        const updateWidth = () => {
            setChatViewportWidth(element.getBoundingClientRect().width);
        };

        updateWidth();

        if (typeof ResizeObserver === "undefined") {
            const handleResize = () => updateWidth();
            window.addEventListener("resize", handleResize);
            return () => window.removeEventListener("resize", handleResize);
        }

        const observer = new ResizeObserver(() => updateWidth());
        observer.observe(element);
        return () => observer.disconnect();
    }, [loading]);

    useEffect(() => {
        if (typeof window === "undefined") return;
        let cancelled = false;
        const isUnlocked =
            window.localStorage.getItem(ADVANCED_SETTINGS_UNLOCK_KEY) === "1";
        setAdvancedUnlocked(isUnlocked);
        setSystemPrompt(
            window.localStorage.getItem(SYSTEM_PROMPT_STORAGE_KEY)?.trim() ||
                DEFAULT_CHAT_SYSTEM_PROMPT_BODY,
        );

        // Only restore custom model settings when advanced settings are
        // unlocked. Without this gate a user who had custom settings before
        // the unlock feature was added would silently keep a hidden custom
        // model with no visible way to change it.
        if (!isUnlocked) return;

        let raw = window.localStorage.getItem(MODEL_SETTINGS_STORAGE_KEY);
        if (!raw) {
            // Migrate from IndexedDB (previous storage) to localStorage
            void getKV(MODEL_SETTINGS_STORAGE_KEY)
                .then((kvRaw) => {
                    if (cancelled || !kvRaw || typeof kvRaw !== "object") {
                        return;
                    }
                    const migrated = JSON.stringify(kvRaw);
                    window.localStorage.setItem(
                        MODEL_SETTINGS_STORAGE_KEY,
                        migrated,
                    );
                    // Re-trigger the effect by reloading settings from the migrated data
                    const parsed = kvRaw as {
                        useCustomModel?: boolean;
                        modelUrl?: string;
                        mmprojUrl?: string;
                        contextLength?: string;
                        maxTokens?: string;
                    };
                    const isTauri = detectTauriRuntime();
                    const canMmproj = isTauri;
                    const rawContextLength = parsed.contextLength ?? "";
                    const clampedContextLength =
                        !isTauri &&
                        rawContextLength &&
                        Number(rawContextLength) > DEFAULT_WEB_CONTEXT_SIZE
                            ? String(DEFAULT_WEB_CONTEXT_SIZE)
                            : rawContextLength;
                    if (clampedContextLength !== rawContextLength) {
                        const clamped = {
                            ...parsed,
                            contextLength: clampedContextLength,
                        };
                        window.localStorage.setItem(
                            MODEL_SETTINGS_STORAGE_KEY,
                            JSON.stringify(clamped),
                        );
                    }
                    setUseCustomModel(!!parsed.useCustomModel);
                    setModelUrl(parsed.modelUrl ?? "");
                    setMmprojUrl(canMmproj ? (parsed.mmprojUrl ?? "") : "");
                    setContextLength(clampedContextLength);
                    setMaxTokens(parsed.maxTokens ?? "");
                    void removeKV(MODEL_SETTINGS_STORAGE_KEY);
                })
                .catch((error: unknown) => {
                    log.error("Failed to migrate model settings", error);
                });
            return () => {
                cancelled = true;
            };
        }
        try {
            const parsed = JSON.parse(raw) as {
                useCustomModel?: boolean;
                modelUrl?: string;
                mmprojUrl?: string;
                contextLength?: string;
                maxTokens?: string;
            };
            const isTauri = detectTauriRuntime();
            const canMmproj = isTauri;
            const rawContextLength = parsed.contextLength ?? "";
            const clampedContextLength =
                !isTauri &&
                rawContextLength &&
                Number(rawContextLength) > DEFAULT_WEB_CONTEXT_SIZE
                    ? String(DEFAULT_WEB_CONTEXT_SIZE)
                    : rawContextLength;
            if (clampedContextLength !== rawContextLength) {
                const nextSettings = {
                    useCustomModel: !!parsed.useCustomModel,
                    modelUrl: parsed.modelUrl ?? "",
                    mmprojUrl: canMmproj ? (parsed.mmprojUrl ?? "") : "",
                    contextLength: clampedContextLength,
                    maxTokens: parsed.maxTokens ?? "",
                };
                window.localStorage.setItem(
                    MODEL_SETTINGS_STORAGE_KEY,
                    JSON.stringify(nextSettings),
                );
            }
            setUseCustomModel(!!parsed.useCustomModel);
            setModelUrl(parsed.modelUrl ?? "");
            setMmprojUrl(canMmproj ? (parsed.mmprojUrl ?? "") : "");
            setContextLength(clampedContextLength);
            setMaxTokens(parsed.maxTokens ?? "");
        } catch (error) {
            log.error("Failed to read model settings", error);
        }
        return () => {
            cancelled = true;
        };
    }, []);

    const applyDownloadProgress = useCallback((progress: DownloadProgress) => {
        setDownloadStatus(progress);
        const status = progress.status?.toLowerCase() ?? "";
        if (progress.percent < 0) {
            setIsDownloading(false);
            return;
        }
        if (progress.percent >= 100 || status.includes("ready")) {
            setIsDownloading(false);
            return;
        }
        setIsDownloading(true);
    }, []);

    const handleDownloadProgress = useCallback(
        (progress: DownloadProgress) => {
            const status = progress.status?.toLowerCase() ?? "";
            const isTerminal =
                progress.percent < 0 ||
                progress.percent >= 100 ||
                status.includes("ready");

            if (isTerminal) {
                if (downloadProgressTimerRef.current) {
                    window.clearTimeout(downloadProgressTimerRef.current);
                    downloadProgressTimerRef.current = null;
                }
                pendingDownloadProgressRef.current = null;
                lastDownloadProgressRef.current = Date.now();
                applyDownloadProgress(progress);
                return;
            }

            const now = Date.now();
            const elapsed = now - lastDownloadProgressRef.current;
            if (elapsed >= 120) {
                lastDownloadProgressRef.current = now;
                applyDownloadProgress(progress);
                return;
            }

            pendingDownloadProgressRef.current = progress;
            if (!downloadProgressTimerRef.current) {
                downloadProgressTimerRef.current = window.setTimeout(
                    () => {
                        const pending = pendingDownloadProgressRef.current;
                        if (pending) {
                            applyDownloadProgress(pending);
                            lastDownloadProgressRef.current = Date.now();
                            pendingDownloadProgressRef.current = null;
                        }
                        downloadProgressTimerRef.current = null;
                    },
                    Math.max(20, 120 - elapsed),
                );
            }
        },
        [applyDownloadProgress],
    );

    useEffect(() => {
        if (typeof window === "undefined") return;
        if (!providerRef.current) {
            providerRef.current = new LlmProvider();
        }
        const unsubscribe = providerRef.current.onDownloadProgress(
            handleDownloadProgress,
        );
        return () => {
            unsubscribe();
        };
    }, [handleDownloadProgress]);

    const refreshSessions = useCallback(async () => {
        if (!chatKey) return;
        if (refreshSessionsInFlightRef.current) {
            return refreshSessionsInFlightRef.current;
        }
        const task = (async () => {
            try {
                const loaded = await listSessions(chatKey);
                if (loaded.length === 0) {
                    setSessions([]);
                    setCurrentSessionId(undefined);
                    setAllMessages([]);
                    if (!routeInitializedRef.current) {
                        updateRouteSession(undefined, true);
                        routeInitializedRef.current = true;
                    }
                    return;
                }

                setSessions(loaded);

                if (isDraftSessionRef.current && !currentSessionIdRef.current) {
                    if (!routeInitializedRef.current) {
                        updateRouteSession(undefined, true);
                        routeInitializedRef.current = true;
                    }
                    return;
                }

                const hasQuerySession =
                    sessionFromQuery &&
                    loaded.some(
                        (session) => session.sessionUuid === sessionFromQuery,
                    );

                const hasCurrentSession =
                    !!currentSessionId &&
                    loaded.some(
                        (session) => session.sessionUuid === currentSessionId,
                    );

                const nextSessionId = hasQuerySession
                    ? sessionFromQuery
                    : hasCurrentSession
                      ? currentSessionId
                      : loaded[0]?.sessionUuid;

                if (nextSessionId) {
                    setCurrentSessionId(nextSessionId);
                    currentSessionIdRef.current = nextSessionId;
                    setIsDraftSession(false);
                    isDraftSessionRef.current = false;
                    if (nextSessionId !== sessionFromQuery) {
                        if (!routeInitializedRef.current) {
                            updateRouteSession(nextSessionId, true);
                            routeInitializedRef.current = true;
                        }
                    } else {
                        routeInitializedRef.current = true;
                    }
                }
            } catch (error) {
                const message = (() => {
                    if (error instanceof Error) return error.message;
                    if (typeof error === "string") return error;
                    try {
                        return JSON.stringify(error);
                    } catch {
                        return String(error);
                    }
                })();
                log.error(`Failed to refresh sessions: ${message}`);
                showMiniDialog({
                    title: "Chat unavailable",
                    message:
                        "We could not load your chat data. Please refresh the page.",
                });
            }
        })();
        refreshSessionsInFlightRef.current = task;
        try {
            await task;
        } finally {
            if (refreshSessionsInFlightRef.current === task) {
                refreshSessionsInFlightRef.current = null;
            }
        }
        return task;
    }, [
        chatKey,
        currentSessionId,
        sessionFromQuery,
        updateRouteSession,
        showMiniDialog,
    ]);

    const refreshMessages = useCallback(
        async (sessionId: string | undefined = currentSessionId) => {
            if (!chatKey || !sessionId) {
                setAllMessages([]);
                return;
            }

            const activeSessionId = sessionId;
            const inFlight = refreshMessagesInFlightRef.current;
            if (inFlight.promise && inFlight.sessionId === activeSessionId) {
                return inFlight.promise;
            }

            const task = (async () => {
                try {
                    const loaded = await listMessages(activeSessionId, chatKey);
                    if (currentSessionIdRef.current !== activeSessionId) return;
                    setAllMessages(loaded);
                } catch (error) {
                    const message = (() => {
                        if (error instanceof Error) return error.message;
                        if (typeof error === "string") return error;
                        try {
                            return JSON.stringify(error);
                        } catch {
                            return String(error);
                        }
                    })();
                    log.error(`Failed to refresh messages: ${message}`);
                }
            })();

            refreshMessagesInFlightRef.current = {
                sessionId: activeSessionId,
                promise: task,
            };

            try {
                await task;
            } finally {
                if (refreshMessagesInFlightRef.current.promise === task) {
                    refreshMessagesInFlightRef.current = {
                        sessionId: undefined,
                        promise: null,
                    };
                }
            }
            return task;
        },
        [chatKey, currentSessionId],
    );

    const showToast = useCallback(
        (
            attributes: NotificationAttributes & { autoHideDuration?: number },
        ) => {
            const { autoHideDuration, ...rest } = attributes;
            setChatNotification(rest);
            setChatNotificationOpen(true);
            if (toastTimeoutRef.current) {
                window.clearTimeout(toastTimeoutRef.current);
                toastTimeoutRef.current = null;
            }
            if (autoHideDuration && typeof window !== "undefined") {
                toastTimeoutRef.current = window.setTimeout(() => {
                    setChatNotificationOpen(false);
                }, autoHideDuration);
            }
        },
        [setChatNotification, setChatNotificationOpen],
    );

    useEffect(() => {
        if (typeof window === "undefined") return;

        const handleFocus = () => {
            void refreshLocalChatKey();
            if (chatKey) {
                void refreshSessions();
                void refreshMessages();
            }
        };

        const handleVisibility = () => {
            if (!document.hidden) {
                void refreshLocalChatKey();
                if (chatKey) {
                    void refreshSessions();
                    void refreshMessages();
                }
            }
        };

        window.addEventListener("focus", handleFocus);
        document.addEventListener("visibilitychange", handleVisibility);

        return () => {
            window.removeEventListener("focus", handleFocus);
            document.removeEventListener("visibilitychange", handleVisibility);
        };
    }, [chatKey, refreshLocalChatKey, refreshMessages, refreshSessions]);

    const deleteSessionTarget = useMemo(
        () =>
            deleteSessionId
                ? sessions.find(
                      (session) => session.sessionUuid === deleteSessionId,
                  )
                : undefined,
        [deleteSessionId, sessions],
    );

    const deleteSessionLabel = useMemo(() => {
        const title = deleteSessionTarget?.title?.trim();
        if (title && title !== "New chat") {
            return `"${title}"`;
        }
        return "this chat";
    }, [deleteSessionTarget]);

    useEffect(() => {
        if (!chatKey || !isChatStoreBridgeReady) return;
        void refreshSessions();
    }, [chatKey, isChatStoreBridgeReady, refreshSessions]);

    useEffect(() => {
        currentSessionIdRef.current = currentSessionId;
        void refreshMessages();
    }, [currentSessionId, refreshMessages]);

    useEffect(() => {
        if (isDraftSession) return;
        if (!sessionFromQuery || sessions.length === 0) return;
        if (
            sessionFromQuery !== currentSessionId &&
            sessions.some((session) => session.sessionUuid === sessionFromQuery)
        ) {
            setCurrentSessionId(sessionFromQuery);
        }
    }, [currentSessionId, isDraftSession, sessionFromQuery, sessions]);

    useEffect(() => {
        setStreamingParentId(null);
        setStreamingText("");
        streamingBufferRef.current = "";
        streamingChunksRef.current = [];
        streamingCreatedAtRef.current = null;
        setIsGenerating(false);
        setIsStreamingOutro(false);
        setPendingImages([]);
        setStickToBottom(true);
        currentJobIdRef.current = null;
        pendingCancelRef.current = false;
    }, [currentSessionId]);

    useEffect(() => {
        if (!isGenerating || streamingText.trim().length > 0) {
            setLoadingPhrase(null);
            setLoadingDots(1);
            return;
        }

        setLoadingPhrase((prev) => prev ?? randomLoadingPhrase());
        const timer = window.setInterval(() => {
            setLoadingDots((prev) => (prev % 3) + 1);
        }, 450);

        return () => {
            window.clearInterval(timer);
        };
    }, [isGenerating, streamingText]);

    const inferImageMime = useCallback((name: string) => {
        const extension = name.split(".").pop()?.toLowerCase();
        switch (extension) {
            case "png":
                return "image/png";
            case "webp":
                return "image/webp";
            case "gif":
                return "image/gif";
            case "jpeg":
            case "jpg":
                return "image/jpeg";
            default:
                return "image/*";
        }
    }, []);

    const loadAttachmentPreview = useCallback(
        async (attachment: ChatAttachment, sessionUuid: string) => {
            if (!chatKey || !firstPaintDone) return;
            if (attachmentPreviewUrlsRef.current[attachment.id]) return;
            if (attachmentPreviewInFlightRef.current[attachment.id]) return;

            const task = (async () => {
                try {
                    const bytes = await readDecryptedAttachmentBytes(
                        attachment.id,
                        chatKey,
                        sessionUuid,
                    );
                    const blob = new Blob([toSafeBlobPart(bytes)], {
                        type: inferImageMime(attachment.name),
                    });
                    const url = URL.createObjectURL(blob);
                    setAttachmentPreviews((prev) => {
                        if (prev[attachment.id]) {
                            URL.revokeObjectURL(url);
                            return prev;
                        }
                        const next = { ...prev, [attachment.id]: url };
                        attachmentPreviewUrlsRef.current = next;
                        return next;
                    });
                } catch (error) {
                    log.error("Failed to load image preview", error);
                }
            })();

            attachmentPreviewInFlightRef.current[attachment.id] = task;
            try {
                await task;
            } finally {
                delete attachmentPreviewInFlightRef.current[attachment.id];
            }
        },
        [chatKey, firstPaintDone, inferImageMime],
    );

    useEffect(() => {
        const next = { ...pendingPreviewUrlsRef.current };
        const activeIds = new Set(pendingImages.map((image) => image.id));

        Object.keys(next).forEach((id) => {
            if (!activeIds.has(id)) {
                const url = next[id];
                if (url) {
                    URL.revokeObjectURL(url);
                }
                delete next[id];
            }
        });

        pendingImages.forEach((image) => {
            if (!next[image.id]) {
                next[image.id] = URL.createObjectURL(image.file);
            }
        });

        pendingPreviewUrlsRef.current = next;
        setPendingImagePreviews(next);
    }, [pendingImages]);

    const currentSession = useMemo(
        () => sessions.find((s) => s.sessionUuid === currentSessionId),
        [sessions, currentSessionId],
    );

    const currentRootSessionUuid = currentSession?.rootSessionUuid;

    useEffect(() => {
        if (!currentRootSessionUuid) {
            setBranchSelections({});
            return;
        }
        let cancelled = false;
        void getBranchSelections(currentRootSessionUuid)
            .then((selections) => {
                if (!cancelled) {
                    setBranchSelections(selections);
                }
            })
            .catch((error: unknown) => {
                log.error("Failed to load branch selections", error);
                if (!cancelled) {
                    setBranchSelections({});
                }
            });

        return () => {
            cancelled = true;
        };
    }, [currentRootSessionUuid]);

    useEffect(() => {
        if (isTauriRuntime) return;
        if (mmprojUrl) {
            setMmprojUrl("");
        }
    }, [isTauriRuntime, mmprojUrl]);

    const filteredSessions = useMemo(() => {
        const query = sessionSearch.trim().toLowerCase();
        if (!query) return sessions;
        return sessions.filter((session) => {
            const title = session.title?.toLowerCase() ?? "";
            const preview = session.lastMessagePreview?.toLowerCase() ?? "";
            return title.includes(query) || preview.includes(query);
        });
    }, [sessionSearch, sessions]);

    const groupedSessions = useMemo(
        () => groupSessionsByDate(filteredSessions),
        [filteredSessions],
    );

    const rootSessionUuid = currentSession?.rootSessionUuid ?? currentSessionId;

    const messageState = useMemo(
        () =>
            buildSelectedPath(
                allMessages,
                branchSelections,
                streamingParentId
                    ? { parentMessageUuid: streamingParentId }
                    : undefined,
            ),
        [allMessages, branchSelections, streamingParentId],
    );

    const displayMessages = useMemo(() => {
        const base = messageState.path ?? [];
        // Insert synthetic "Response was interrupted" placeholders for orphaned user messages
        const augmented: ChatMessage[] = [];
        for (let i = 0; i < base.length; i++) {
            const msg = base[i];
            if (!msg) continue;
            augmented.push(msg);
            if (msg.sender === "self") {
                const next = base[i + 1];
                const isLastAndGenerating =
                    i === base.length - 1 && isGenerating;
                if (next?.sender !== "assistant" && !isLastAndGenerating) {
                    augmented.push({
                        messageUuid: `interrupted-placeholder-${msg.messageUuid}`,
                        sessionUuid: msg.sessionUuid,
                        parentMessageUuid: msg.messageUuid,
                        sender: "assistant",
                        text: "Response was interrupted",
                        createdAt: msg.createdAt,
                        isSynthetic: true,
                    });
                }
            }
        }
        if (streamingParentId) {
            const streamingMessage: ChatMessage = {
                messageUuid: STREAMING_SELECTION_KEY,
                sessionUuid: currentSessionId ?? "",
                parentMessageUuid: streamingParentId,
                sender: "assistant",
                text: streamingText,
                createdAt: streamingCreatedAtRef.current ?? Date.now() * 1000,
            };
            return [...augmented, streamingMessage];
        }
        return augmented;
    }, [
        messageState.path,
        streamingParentId,
        streamingText,
        currentSessionId,
        isGenerating,
    ]);

    const branchSwitchers = messageState.switchers;

    useEffect(() => {
        if (!chatKey) return;
        const activeIds = new Set<string>();

        displayMessages.forEach((message) => {
            (message.attachments ?? []).forEach((attachment) => {
                if (attachment.kind === "image") {
                    activeIds.add(attachment.id);
                }
            });
        });

        // Clean up blob URLs for attachments no longer displayed.
        setAttachmentPreviews((prev) => {
            const next = { ...prev };
            Object.keys(next).forEach((id) => {
                if (!activeIds.has(id)) {
                    const url = next[id];
                    if (url) {
                        URL.revokeObjectURL(url);
                    }
                    delete next[id];
                }
            });
            attachmentPreviewUrlsRef.current = next;
            return next;
        });

        // Load previews for persisted image attachments that do not have blob
        // URLs yet, such as after reopening the app.
        for (const message of displayMessages) {
            for (const attachment of message.attachments ?? []) {
                if (attachment.kind === "image") {
                    void loadAttachmentPreview(attachment, message.sessionUuid);
                }
            }
        }
    }, [chatKey, displayMessages, loadAttachmentPreview]);

    const showDrawerToggle = isSmall || drawerCollapsed;
    const drawerWidth = isSmall ? 300 : drawerCollapsed ? 0 : 320;
    const desktopBreakpoint = theme.breakpoints.values.lg ?? 1200;
    const isDesktopOverlay = !isSmall && chatViewportWidth >= desktopBreakpoint;
    const showImageAttachment = isTauriRuntime;
    const showDownloadProgress =
        !!downloadStatus?.status && downloadStatus.status !== "Ready";
    const showModelGate =
        modelGateStatus === "missing" ||
        modelGateStatus === "error" ||
        modelGateStatus === "downloading";

    const downloadSizeLabel = useMemo(() => {
        if (useCustomModel) {
            return "Approx. size varies by model";
        }
        if (resolvedDefaultModel.sizeBytes) {
            const extraBytes = allowMmproj
                ? (resolvedDefaultModel.mmprojSizeBytes ?? 0)
                : 0;
            return `Approx. ${formatBytes(resolvedDefaultModel.sizeBytes + extraBytes)}`;
        }
        return resolvedDefaultModel.sizeHuman
            ? `Approx. ${resolvedDefaultModel.sizeHuman}`
            : "Approx. size varies by model";
    }, [allowMmproj, resolvedDefaultModel, useCustomModel]);

    const downloadStatusLabel = useMemo(() => {
        if (!showDownloadProgress) return null;
        const status = downloadStatus?.status ?? "";
        if (status.toLowerCase().includes("loading")) {
            return status;
        }
        if (downloadStatus?.totalBytes && downloadStatus.percent >= 0) {
            const downloaded = downloadStatus.bytesDownloaded ?? 0;
            return `Downloading... ${formatBytes(downloaded)} / ${formatBytes(downloadStatus.totalBytes)}`;
        }
        if (status) return status;
        return "Downloading...";
    }, [downloadStatus, showDownloadProgress]);

    const focusInput = useCallback(() => {
        if (showModelGate) return;
        if (typeof window === "undefined") return;
        const target = inputRef.current;
        if (!target) return;
        window.requestAnimationFrame(() => {
            target.focus();
        });
    }, [showModelGate]);

    useEffect(() => {
        if (showSessionSearch) return;
        focusInput();
    }, [
        currentSessionId,
        isDraftSession,
        showModelGate,
        showSessionSearch,
        focusInput,
    ]);

    const ensureProvider = useCallback(async () => {
        if (!providerRef.current) {
            providerRef.current = new LlmProvider();
        }
        await providerRef.current.initialize();
        setResolvedDefaultModel(providerRef.current.getDefaultModel());
        const presets = providerRef.current.getResolvedModelPresets();
        if (presets) {
            setResolvedModelPresets(presets);
        }
        return providerRef.current;
    }, []);

    const getModelSettings = useCallback((): ModelSettings => {
        const customModelEnabled = useCustomModel;
        return {
            useCustomModel: customModelEnabled,
            modelUrl:
                customModelEnabled && modelUrl.trim()
                    ? modelUrl.trim()
                    : undefined,
            mmprojUrl:
                customModelEnabled && allowMmproj && mmprojUrl.trim()
                    ? mmprojUrl.trim()
                    : undefined,
            contextLength: contextLength ? Number(contextLength) : undefined,
            maxTokens:
                maxTokens && Number(maxTokens) > 0
                    ? Number(maxTokens)
                    : undefined,
        };
    }, [
        useCustomModel,
        modelUrl,
        mmprojUrl,
        contextLength,
        maxTokens,
        allowMmproj,
    ]);

    const modelSettingsKey = useMemo(
        () => JSON.stringify(getModelSettings()),
        [getModelSettings],
    );

    const formatErrorMessage = useCallback((error: unknown) => {
        const normalizeErrorMessage = (message: string) => {
            if (
                message.toLowerCase().includes("length out of range of buffer")
            ) {
                return "Prompt exceeds the model context window. Reduce history, lower max tokens, or increase context length.";
            }
            return message;
        };

        if (error instanceof Error) return normalizeErrorMessage(error.message);
        if (typeof error === "string") return normalizeErrorMessage(error);
        if (error && typeof error === "object") {
            const maybeMessage = (error as { message?: unknown }).message;
            if (typeof maybeMessage === "string" && maybeMessage.trim()) {
                return normalizeErrorMessage(maybeMessage);
            }
            if ("__wbg_ptr" in error) {
                return "Model failed to start. Please refresh and try again.";
            }
            const text = String(error);
            if (text && text !== "[object Object]") {
                return normalizeErrorMessage(text);
            }
        }
        try {
            return normalizeErrorMessage(JSON.stringify(error));
        } catch {
            return normalizeErrorMessage(String(error));
        }
    }, []);

    const trimToWords = useCallback((text: string, maxWords: number) => {
        const normalized = text
            .replace(/\u0000/g, "")
            .replace(/[\r\n\t]+/g, " ")
            .replace(/\s+/g, " ")
            .trim();
        if (!normalized) return "";

        const words = normalized
            .split(" ")
            .map((word) =>
                word.replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, ""),
            )
            .filter(Boolean);

        return words.slice(0, maxWords).join(" ");
    }, []);

    const writeInferenceImages = useCallback(
        async (images: ImageAttachment[]) => {
            if (!isTauriRuntime || images.length === 0) return [] as string[];
            const { appDataDir, join } = await import("@tauri-apps/api/path");
            const { mkdir, writeFile } = await import("@tauri-apps/plugin-fs");
            const root = await appDataDir();
            const dir = await join(root, "ensu_llmchat_inference_images");
            await mkdir(dir, { recursive: true });

            const paths = await Promise.all(
                images.map(async (image) => {
                    const bytes = new Uint8Array(
                        await image.file.arrayBuffer(),
                    );
                    const path = await join(dir, `${image.id}.jpg`);
                    await writeFile(path, bytes);
                    return path;
                }),
            );

            return paths;
        },
        [isTauriRuntime],
    );

    const cleanupInferenceImages = useCallback(
        async (paths: string[]) => {
            if (!isTauriRuntime || paths.length === 0) return;
            const { remove } = await import("@tauri-apps/plugin-fs");
            await Promise.all(
                paths.map(async (path) => {
                    try {
                        await remove(path);
                    } catch {
                        // ignore cleanup failures
                    }
                }),
            );
        },
        [isTauriRuntime],
    );

    const generateSessionSummary = useCallback(
        async (input: string) => {
            const provider = await ensureProvider();
            const settings = getModelSettings();
            const availability =
                await provider.checkModelAvailability(settings);
            const mmprojReady =
                availability.mmprojAvailable === undefined ||
                availability.mmprojAvailable;

            if (!availability.modelAvailable || !mmprojReady) {
                return null;
            }

            await provider.ensureModelReady(settings);

            let summary = "";

            await provider.generateChatStream(
                {
                    messages: [
                        { role: "system", content: SESSION_TITLE_PROMPT },
                        { role: "user", content: input },
                    ],
                    maxTokens: 64,
                    temperature: 0.2,
                    topP: 0.9,
                    repeatPenalty: REPEAT_PENALTY,
                },
                (event) => {
                    if (event.type === "text") {
                        summary += event.text;
                    }
                },
            );

            return summary;
        },
        [ensureProvider, getModelSettings],
    );

    const updateSessionTitleInState = useCallback(
        (sessionUuid: string, title: string) => {
            const updatedAt = Date.now() * 1000;
            setSessions((prev) => {
                const next = prev.map((session) =>
                    session.sessionUuid === sessionUuid
                        ? { ...session, title, updatedAt }
                        : session,
                );
                next.sort((a, b) => b.updatedAt - a.updatedAt);
                return next;
            });
        },
        [],
    );

    const maybeGenerateSessionTitle = useCallback(
        async ({
            sessionUuid,
            assistantMessageUuid,
            wasInterrupted,
        }: {
            sessionUuid: string;
            assistantMessageUuid: string;
            wasInterrupted: boolean;
        }) => {
            if (!chatKey || wasInterrupted) return;
            if (sessionSummaryInFlightRef.current) return;
            sessionSummaryInFlightRef.current = true;

            try {
                const messages = await listMessages(sessionUuid, chatKey);
                const assistantMessages = messages.filter(
                    (message) => message.sender === "assistant",
                );
                if (assistantMessages.length !== 1) return;

                const firstAssistant = assistantMessages[0];
                if (!firstAssistant) return;
                if (firstAssistant.messageUuid !== assistantMessageUuid) return;

                const firstUser = messages.find(
                    (message) => message.sender === "self",
                );
                if (!firstUser) return;

                const userText = parseDocumentBlocks(firstUser.text).text;
                const assistantText = stripHiddenPartsText(firstAssistant.text);

                const fallbackSeed = trimToWords(userText, 7) || "New chat";
                const fallbackTitle = sessionTitleFromText(
                    fallbackSeed,
                    "New chat",
                );

                const summaryInput = `User: ${userText}\nAssistant: ${assistantText}`;
                const summary = await generateSessionSummary(summaryInput);
                const summarySeed = summary ? trimToWords(summary, 7) : "";
                const title = summarySeed
                    ? sessionTitleFromText(summarySeed, fallbackTitle)
                    : fallbackTitle;

                await updateSessionTitle(sessionUuid, title, chatKey);
                updateSessionTitleInState(sessionUuid, title);
            } catch (error) {
                log.error("Failed to generate session title", error);
            } finally {
                sessionSummaryInFlightRef.current = false;
            }
        },
        [
            chatKey,
            generateSessionSummary,
            trimToWords,
            updateSessionTitleInState,
        ],
    );

    const preloadModelIfAvailable = useCallback(async () => {
        setModelGateError(null);
        setModelGateStatus("checking");

        try {
            const provider = await ensureProvider();
            const settings = getModelSettings();
            const availability =
                await provider.checkModelAvailability(settings);
            const mmprojReady =
                availability.mmprojAvailable === undefined ||
                availability.mmprojAvailable;

            if (!availability.modelAvailable || !mmprojReady) {
                setModelGateStatus("missing");
                return;
            }

            setModelGateStatus("preloading");
            setDownloadStatus({ percent: 0, status: "Loading model..." });
            setIsDownloading(true);

            await provider.ensureModelReady(settings);
            setLoadedModelName(provider.getCurrentModel()?.name ?? null);
            setIsDownloading(false);
            setDownloadStatus({ percent: 100, status: "Ready" });
            setModelGateStatus("ready");
        } catch (error) {
            const message = formatErrorMessage(error);
            log.error("Failed to preload model", error);
            setModelGateError(message);
            setIsDownloading(false);
            setDownloadStatus(null);
            setModelGateStatus("error");
        }
    }, [ensureProvider, formatErrorMessage, getModelSettings]);

    const handleDownloadModel = useCallback(async () => {
        setModelGateError(null);
        setModelGateStatus("downloading");
        setDownloadStatus({ percent: 0, status: "Preparing download..." });
        setIsDownloading(true);

        try {
            const provider = await ensureProvider();
            const settings = getModelSettings();
            await provider.ensureModelReady(settings);
            setLoadedModelName(provider.getCurrentModel()?.name ?? null);
            setIsDownloading(false);
            setDownloadStatus({ percent: 100, status: "Ready" });
            setModelGateStatus("ready");
        } catch (error) {
            const message = formatErrorMessage(error);
            log.error("Failed to prepare model", error);
            setModelGateError(message);
            setIsDownloading(false);
            setDownloadStatus(null);
            setModelGateStatus("error");
            showMiniDialog({ title: "Model error", message });
        }
    }, [ensureProvider, formatErrorMessage, getModelSettings, showMiniDialog]);

    const prewarmSelectedImageInference = useCallback(() => {
        if (!isTauriRuntime) return;
        void (async () => {
            try {
                const provider = await ensureProvider();
                await provider.prewarmImageInferenceIfAvailable(
                    getModelSettings(),
                );
            } catch (error) {
                log.error("Failed to prewarm image inference", error);
            }
        })();
    }, [ensureProvider, getModelSettings, isTauriRuntime]);

    useEffect(() => {
        if (!firstPaintDone) return;
        const cancelIdle = scheduleIdleTask(() => {
            void preloadModelIfAvailable();
        }, 2000);
        return () => {
            cancelIdle();
        };
    }, [
        firstPaintDone,
        modelSettingsKey,
        preloadModelIfAvailable,
        scheduleIdleTask,
    ]);

    const updateBranchSelectionState = useCallback(
        async (
            selectionKey: string,
            selectedMessageUuid: string,
            persist = true,
        ) => {
            setBranchSelections((prev) => ({
                ...prev,
                [selectionKey]: selectedMessageUuid,
            }));

            if (
                !persist ||
                !rootSessionUuid ||
                selectedMessageUuid === STREAMING_SELECTION_KEY
            ) {
                return;
            }

            await setBranchSelection(
                rootSessionUuid,
                selectionKey,
                selectedMessageUuid,
            );
        },
        [rootSessionUuid],
    );

    const slicePathUntil = useCallback(
        (path: ChatMessage[], messageUuid?: string | null) => {
            if (!messageUuid) return path;
            const index = path.findIndex(
                (message) => message.messageUuid === messageUuid,
            );
            if (index === -1) return path;
            return path.slice(0, index + 1);
        },
        [],
    );

    const stripHiddenParts = useCallback((text: string) => {
        return stripHiddenPartsText(text);
    }, []);

    const getMessagePreview = useCallback(
        (message: ChatMessage) => {
            if (message.sender === "assistant") {
                return stripHiddenParts(message.text);
            }
            const parsed = parseDocumentBlocks(message.text);
            if (parsed.text.trim()) return parsed.text;

            const attachments = message.attachments ?? [];
            const imageCount = attachments.filter(
                (attachment) => attachment.kind === "image",
            ).length;

            if (imageCount > 0) return "Attached images";
            return "";
        },
        [stripHiddenParts],
    );

    const appendMessageToState = useCallback((message: ChatMessage) => {
        setAllMessages((prev) => {
            if (prev.some((item) => item.messageUuid === message.messageUuid)) {
                return prev;
            }
            return [...prev, message];
        });
    }, []);

    const updateSessionAfterMessage = useCallback(
        (message: ChatMessage) => {
            const preview = getMessagePreview(message);
            setSessions((prev) => {
                const next = prev.map((session) => {
                    if (session.sessionUuid !== message.sessionUuid) {
                        return session;
                    }

                    const nextTitle =
                        message.sender === "self" &&
                        session.title.toLowerCase() === "new chat"
                            ? sessionTitleFromText(
                                  parseDocumentBlocks(message.text).text ||
                                      message.text,
                                  "New chat",
                              )
                            : session.title;

                    return {
                        ...session,
                        title: nextTitle,
                        updatedAt: message.createdAt,
                        lastMessagePreview: preview,
                    };
                });

                next.sort((a, b) => b.updatedAt - a.updatedAt);
                return next;
            });
        },
        [getMessagePreview],
    );

    const approxTokens = useCallback((text: string) => {
        if (!text) return 0;
        const baseTokens = Math.ceil(text.length / 4);
        const imageCount = text.split(MEDIA_MARKER).length - 1;
        return baseTokens + imageCount * IMAGE_TOKEN_ESTIMATE;
    }, []);

    const buildHistory = useCallback(
        async (
            path: ChatMessage[],
            promptText: string,
            contextSize: number,
            maxTokensCount?: number,
            stopAtMessageUuid?: string | null,
        ): Promise<LlmMessage[]> => {
            const candidates = slicePathUntil(path, stopAtMessageUuid);
            const lastCandidate = candidates[candidates.length - 1];
            const trimmedCandidates =
                stopAtMessageUuid &&
                lastCandidate &&
                lastCandidate.messageUuid === stopAtMessageUuid
                    ? candidates.slice(0, -1)
                    : candidates;

            const safetyMargin = 256;
            let budget =
                contextSize -
                (maxTokensCount ?? DEFAULT_GENERATION_MAX_TOKENS) -
                safetyMargin;
            budget -= approxTokens(buildChatSystemPrompt(systemPrompt));
            budget -= approxTokens(promptText);

            if (budget <= 0) return [];

            const selected: LlmMessage[] = [];
            let used = 0;

            for (let idx = trimmedCandidates.length - 1; idx >= 0; idx -= 1) {
                const message = trimmedCandidates[idx];
                if (!message) continue;
                const isUser = message.sender === "self";
                let text = isUser
                    ? message.text
                    : stripHiddenParts(message.text);

                if (isUser) {
                    const parsed = parseDocumentBlocks(text);
                    text = parsed.text;

                    const imageCount = (message.attachments ?? []).filter(
                        (attachment) => attachment.kind === "image",
                    ).length;
                    if (imageCount > 0) {
                        text += `\n\n[${imageCount} attachment${imageCount === 1 ? "" : "s"} attached]`;
                    }
                }

                const cost = approxTokens(text);

                if (used + cost > budget) {
                    if (selected.length === 0 && budget > 0) {
                        const charBudget = Math.max(1, budget * 4);
                        const truncated = text.slice(-charBudget);
                        selected.push({
                            role: isUser ? "user" : "assistant",
                            content: truncated,
                        });
                    }
                    break;
                }

                selected.push({
                    role: isUser ? "user" : "assistant",
                    content: text,
                });
                used += cost;
            }

            return selected.reverse();
        },
        [approxTokens, slicePathUntil, stripHiddenParts, systemPrompt],
    );

    const handleNewChat = useCallback(() => {
        setCurrentSessionId(undefined);
        currentSessionIdRef.current = undefined;
        setAllMessages([]);
        setInput("");
        setEditingMessage(null);
        setPendingImages([]);
        setStreamingParentId(null);
        setStreamingText("");
        streamingBufferRef.current = "";
        streamingChunksRef.current = [];
        streamingCreatedAtRef.current = null;
        setIsGenerating(false);
        setIsStreamingOutro(false);
        setIsDraftSession(true);
        isDraftSessionRef.current = true;
        updateRouteSession(undefined, true);
        if (isSmall) setDrawerOpen(false);
        focusInput();
    }, [focusInput, isSmall, updateRouteSession]);

    const handleSelectSession = useCallback(
        (sessionId: string) => {
            setCurrentSessionId(sessionId);
            currentSessionIdRef.current = sessionId;
            setIsDraftSession(false);
            isDraftSessionRef.current = false;
            updateRouteSession(sessionId);
            if (isSmall) setDrawerOpen(false);
            focusInput();
        },
        [focusInput, isSmall, updateRouteSession],
    );

    const removeSessionFromState = useCallback(
        (sessionId: string) => {
            setSessions((prev) =>
                prev.filter((session) => session.sessionUuid !== sessionId),
            );
            setAllMessages((prev) =>
                prev.filter((message) => message.sessionUuid !== sessionId),
            );

            if (currentSessionIdRef.current === sessionId) {
                setCurrentSessionId(undefined);
                currentSessionIdRef.current = undefined;
                setIsDraftSession(true);
                isDraftSessionRef.current = true;
                updateRouteSession(undefined, true);
            }
        },
        [updateRouteSession],
    );

    const handleDeleteSession = useCallback(
        async (sessionId: string) => {
            if (!chatKey) return;

            if (currentSessionIdRef.current === sessionId) {
                generationTokenRef.current += 1;
                pendingCancelRef.current = false;
                stopRequestedRef.current = false;

                const jobId = currentJobIdRef.current;
                currentJobIdRef.current = null;
                providerRef.current?.cancelGeneration(jobId ?? -1);

                setIsGenerating(false);
                setIsStreamingOutro(false);
                setIsDownloading(false);
                setDownloadStatus(null);
                setStreamingParentId(null);
                setStreamingText("");
                streamingBufferRef.current = "";
                streamingChunksRef.current = [];
                streamingCreatedAtRef.current = null;
                lastGenerationRef.current = null;
            }

            await deleteSession(sessionId);
            removeSessionFromState(sessionId);
        },
        [chatKey, removeSessionFromState],
    );

    const requestDeleteSession = useCallback((sessionId: string) => {
        setDeleteSessionId(sessionId);
    }, []);

    const handleConfirmDeleteSession = useCallback(async () => {
        if (!deleteSessionId) return;
        try {
            await handleDeleteSession(deleteSessionId);
        } catch (error) {
            onGenericError(error);
        } finally {
            setDeleteSessionId(null);
        }
    }, [deleteSessionId, handleDeleteSession, onGenericError]);

    const handleCancelDeleteSession = useCallback(() => {
        setDeleteSessionId(null);
    }, []);

    const handleEditMessage = useCallback(
        async (message: ChatMessage) => {
            const parsed = parseDocumentBlocks(message.text);
            setEditingMessage(message);
            setInput(parsed.text);

            const attachments = message.attachments ?? [];
            const imageAttachments = attachments.filter(
                (attachment) => attachment.kind === "image",
            );

            if (imageAttachments.length === 0) {
                setPendingImages([]);
                return;
            }

            if (!chatKey) {
                showMiniDialog({
                    title: "Attachment error",
                    message:
                        "Attachments are unavailable until encryption is ready.",
                });
                setPendingImages([]);
                return;
            }

            try {
                const images = await Promise.all(
                    imageAttachments.map(async (attachment) => {
                        const bytes = await readDecryptedAttachmentBytes(
                            attachment.id,
                            chatKey,
                            message.sessionUuid,
                        );
                        const name =
                            attachment.name?.trim() || `image-${attachment.id}`;
                        const file = new File([toSafeBlobPart(bytes)], name, {
                            type: inferImageMime(name),
                        });
                        return {
                            id: attachment.id,
                            name,
                            size: bytes.length,
                            file,
                        } satisfies ImageAttachment;
                    }),
                );

                setPendingImages(images);
            } catch (error) {
                log.error("Failed to load attachment contents", error);
                showMiniDialog({
                    title: "Attachment error",
                    message:
                        "We could not load attachment contents for editing.",
                });
                setPendingImages([]);
            }
        },
        [chatKey, showMiniDialog, inferImageMime],
    );

    const handleCancelEdit = useCallback(() => {
        setEditingMessage(null);
        setInput("");
        setPendingDocuments([]);
        setPendingImages([]);
    }, []);

    const handleCopyMessage = useCallback(
        async (text: string) => {
            try {
                await navigator.clipboard.writeText(text);
                showToast({
                    title: "Copied to clipboard.",
                    color: "inherit",
                    autoHideDuration: 2000,
                });
            } catch (error) {
                log.error("Failed to copy message", error);
                showToast({
                    title: "Copy failed.",
                    color: "inherit",
                    autoHideDuration: 3000,
                });
            }
        },
        [showToast],
    );

    const closeImagePreview = useCallback(() => {
        setImagePreview(null);
        if (imagePreviewUrlRef.current) {
            URL.revokeObjectURL(imagePreviewUrlRef.current);
            imagePreviewUrlRef.current = null;
        }
    }, []);

    const handleOpenAttachment = useCallback(
        async (message: ChatMessage, attachment: ChatAttachment) => {
            if (!chatKey) return;

            try {
                const bytes = await readDecryptedAttachmentBytes(
                    attachment.id,
                    chatKey,
                    message.sessionUuid,
                );

                const baseName =
                    attachment.name?.trim() || `attachment-${attachment.id}`;
                const treatAsImage = attachment.kind === "image";
                const filename = treatAsImage
                    ? baseName
                    : baseName.toLowerCase().endsWith(".txt")
                      ? baseName
                      : baseName.includes(".")
                        ? `${baseName.replace(/\.[^/.]+$/, "")}.txt`
                        : `${baseName}.txt`;

                if (treatAsImage) {
                    const mime = inferImageMime(baseName);
                    const blob = new Blob([toSafeBlobPart(bytes)], {
                        type: mime,
                    });
                    const url = URL.createObjectURL(blob);
                    if (imagePreviewUrlRef.current) {
                        URL.revokeObjectURL(imagePreviewUrlRef.current);
                    }
                    imagePreviewUrlRef.current = url;
                    setImagePreview({ url, name: baseName });
                    return;
                }

                if (isTauriRuntime) {
                    const [
                        { appDataDir, join },
                        { mkdir, writeFile },
                        { openPath },
                    ] = await Promise.all([
                        import("@tauri-apps/api/path"),
                        import("@tauri-apps/plugin-fs"),
                        import("@tauri-apps/plugin-opener"),
                    ]);
                    const root = await appDataDir();
                    const dir = await join(root, "ensu_llmchat_attachments_v2");
                    await mkdir(dir, { recursive: true });
                    const filePath = await join(dir, filename);

                    await writeFile(filePath, bytes);
                    await openPath(filePath);
                    return;
                }

                if (!treatAsImage) {
                    const text = new TextDecoder().decode(bytes);
                    const blob = new Blob([text], {
                        type: "text/plain;charset=utf-8",
                    });
                    const url = URL.createObjectURL(blob);
                    window.open(url, "_blank", "noopener");
                    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
                    return;
                }
            } catch (error) {
                log.error("Failed to open attachment", error);
                showMiniDialog({
                    title: "Attachment open failed",
                    message:
                        "We could not open this attachment. Please try again.",
                });
            }
        },
        [chatKey, inferImageMime, isTauriRuntime, showMiniDialog],
    );

    useEffect(() => {
        return () => {
            if (imagePreviewUrlRef.current) {
                URL.revokeObjectURL(imagePreviewUrlRef.current);
                imagePreviewUrlRef.current = null;
            }
        };
    }, []);

    const flushStreamingText = useCallback(() => {
        if (streamingFlushTimerRef.current) {
            window.clearTimeout(streamingFlushTimerRef.current);
            streamingFlushTimerRef.current = null;
        }
        if (streamingChunksRef.current.length > 0) {
            streamingBufferRef.current += streamingChunksRef.current.join("");
            streamingChunksRef.current = [];
        }
        setStreamingText(streamingBufferRef.current);
    }, []);

    const scheduleStreamingFlush = useCallback(() => {
        if (streamingFlushTimerRef.current) return;
        streamingFlushTimerRef.current = window.setTimeout(() => {
            flushStreamingText();
            streamingFlushTimerRef.current = null;
        }, 100);
    }, [flushStreamingText]);

    const handleStopGeneration = useCallback(() => {
        const jobId = currentJobIdRef.current;
        pendingCancelRef.current = true;
        stopRequestedRef.current = true;
        generationTokenRef.current += 1;

        flushStreamingText();
        const finalText = streamingBufferRef.current.replace(/\u0000/g, "");
        const trimmedText = finalText.trim();
        const parentMessageUuid = streamingParentId;
        const activeSessionId = currentSessionIdRef.current ?? currentSessionId;

        const last = lastGenerationRef.current;

        setIsGenerating(false);
        setIsStreamingOutro(false);
        setIsDownloading(false);
        currentJobIdRef.current = null;

        const resetStreamingState = () => {
            setStreamingParentId(null);
            streamingBufferRef.current = "";
            streamingChunksRef.current = [];
            streamingCreatedAtRef.current = null;
            setStreamingText("");
        };

        if (trimmedText && parentMessageUuid && activeSessionId && chatKey) {
            void (async () => {
                try {
                    const assistantMessage = await addMessage(
                        activeSessionId,
                        "assistant",
                        finalText,
                        chatKey,
                        parentMessageUuid,
                    );

                    void updateBranchSelectionState(
                        parentMessageUuid,
                        assistantMessage.messageUuid,
                    );
                    appendMessageToState(assistantMessage);
                    updateSessionAfterMessage(assistantMessage);
                    void maybeGenerateSessionTitle({
                        sessionUuid: activeSessionId,
                        assistantMessageUuid: assistantMessage.messageUuid,
                        wasInterrupted: false,
                    });
                } catch (error) {
                    log.error("Failed to finalize stopped generation", error);
                    if (last?.previousSelection) {
                        void updateBranchSelectionState(
                            last.parentMessageUuid,
                            last.previousSelection,
                        );
                    }
                } finally {
                    resetStreamingState();
                }
            })();
        } else {
            if (last?.previousSelection) {
                void updateBranchSelectionState(
                    last.parentMessageUuid,
                    last.previousSelection,
                );
            }
            resetStreamingState();
        }

        const provider = providerRef.current;
        if (provider) {
            provider.cancelGeneration(jobId ?? -1);
            return;
        }

        void (async () => {
            try {
                const ensured = await ensureProvider();
                ensured.cancelGeneration(jobId ?? -1);
            } catch (error) {
                log.error("Failed to cancel generation", error);
            }
        })();
    }, [
        appendMessageToState,
        chatKey,
        currentSessionId,
        ensureProvider,
        flushStreamingText,
        maybeGenerateSessionTitle,
        streamingParentId,
        updateBranchSelectionState,
        updateSessionAfterMessage,
    ]);

    const startGeneration = useCallback(
        async ({
            promptText,
            parentMessageUuid,
            historyPath,
            stopAtMessageUuid,
            resetContext = false,
            sessionUuid,
            imagePaths,
            mediaMarker,
        }: {
            promptText: string;
            parentMessageUuid: string;
            historyPath: ChatMessage[];
            stopAtMessageUuid?: string | null;
            resetContext?: boolean;
            sessionUuid?: string;
            imagePaths?: string[];
            mediaMarker?: string;
        }) => {
            const activeSessionId =
                sessionUuid ?? currentSessionIdRef.current ?? currentSessionId;
            if (!chatKey || !activeSessionId) return;

            if (pendingCancelRef.current) {
                pendingCancelRef.current = false;
            }
            stopRequestedRef.current = false;

            const generationToken = generationTokenRef.current + 1;
            generationTokenRef.current = generationToken;

            const isActiveGeneration = () =>
                generationTokenRef.current === generationToken &&
                currentSessionIdRef.current === activeSessionId;

            const provider = await ensureProvider();
            const settings = getModelSettings();
            const { contextSize, maxTokens } =
                provider.resolveRuntimeSettings(settings);

            if (!isActiveGeneration()) {
                return;
            }

            const previousSelection = branchSelections[parentMessageUuid];
            lastGenerationRef.current = {
                parentMessageUuid,
                previousSelection,
            };

            void updateBranchSelectionState(
                parentMessageUuid,
                STREAMING_SELECTION_KEY,
                false,
            );
            setStreamingParentId(parentMessageUuid);
            setStreamingText("");
            streamingBufferRef.current = "";
            streamingChunksRef.current = [];
            streamingCreatedAtRef.current = Date.now() * 1000;
            setIsStreamingOutro(false);
            setIsGenerating(true);
            currentJobIdRef.current = null;

            let errorMessage: string | null = null;

            try {
                await provider.ensureModelReady(settings);
                setLoadedModelName(provider.getCurrentModel()?.name ?? null);
                setIsDownloading(false);
                setDownloadStatus({ percent: 100, status: "Ready" });

                if (!isActiveGeneration()) {
                    return;
                }

                if (resetContext) {
                    await provider.resetContext(contextSize);
                }

                const history =
                    (await buildHistory(
                        historyPath,
                        promptText,
                        contextSize,
                        maxTokens,
                        stopAtMessageUuid,
                    )) ?? [];

                const messages: LlmMessage[] = [
                    {
                        role: "system",
                        content: buildChatSystemPrompt(systemPrompt),
                    },
                    ...history,
                    { role: "user", content: promptText },
                ];
                const promptTokenEstimate = messages.reduce(
                    (total, message) => total + approxTokens(message.content),
                    0,
                );
                const inputBudget =
                    contextSize - maxTokens - OVERFLOW_SAFETY_TOKENS;
                if (promptTokenEstimate > inputBudget) {
                    throw new Error(
                        "Prompt exceeds the model context window. Reduce history, lower max tokens, or increase context length.",
                    );
                }

                if (pendingCancelRef.current || stopRequestedRef.current) {
                    pendingCancelRef.current = false;
                    stopRequestedRef.current = false;
                    provider.cancelGeneration(-1);
                    if (previousSelection) {
                        void updateBranchSelectionState(
                            parentMessageUuid,
                            previousSelection,
                        );
                    }
                    setIsGenerating(false);
                    setIsStreamingOutro(false);
                    setIsDownloading(false);
                    setStreamingParentId(null);
                    streamingBufferRef.current = "";
                    streamingChunksRef.current = [];
                    streamingCreatedAtRef.current = null;
                    setStreamingText("");
                    currentJobIdRef.current = null;
                    return;
                }

                const hasImages =
                    (imagePaths?.length ?? 0) > 0 &&
                    provider.getBackendKind() === "tauri";
                const mmprojPath = hasImages
                    ? provider.getCurrentMmprojPath()
                    : undefined;
                if (hasImages && !mmprojPath) {
                    throw new Error("MMProj model not available");
                }

                await provider
                    .generateChatStream(
                        {
                            messages,
                            imagePaths: hasImages ? imagePaths : undefined,
                            mmprojPath,
                            mediaMarker: hasImages
                                ? (mediaMarker ?? MEDIA_MARKER)
                                : undefined,
                            maxTokens,
                            temperature: 0.7,
                            topP: 0.9,
                            repeatPenalty: REPEAT_PENALTY,
                        },
                        (event: GenerateEvent) => {
                            if (!isActiveGeneration()) {
                                return;
                            }
                            if (event.type === "text") {
                                if (!currentJobIdRef.current) {
                                    currentJobIdRef.current = event.job_id;
                                    if (pendingCancelRef.current) {
                                        pendingCancelRef.current = false;
                                        provider.cancelGeneration(event.job_id);
                                        return;
                                    }
                                }
                                streamingChunksRef.current.push(event.text);
                                scheduleStreamingFlush();
                            } else if (event.type === "done") {
                                currentJobIdRef.current = event.summary.job_id;
                            }
                        },
                    )
                    .catch((error: unknown) => {
                        errorMessage =
                            error instanceof Error
                                ? error.message
                                : String(error);
                    });

                if (!isActiveGeneration()) {
                    return;
                }

                flushStreamingText();
                const finalText = streamingBufferRef.current;

                if (!finalText.trim()) {
                    if (errorMessage) {
                        showMiniDialog({
                            title: "Generation failed",
                            message: errorMessage,
                        });
                    }
                    if (previousSelection) {
                        void updateBranchSelectionState(
                            parentMessageUuid,
                            previousSelection,
                        );
                    }
                    return;
                }

                const assistantText = finalText.replace(/\u0000/g, "");
                setIsStreamingOutro(true);

                await new Promise<void>((resolve) => {
                    window.setTimeout(resolve, STREAMING_OUTRO_DURATION_MS);
                });

                if (!isActiveGeneration()) {
                    return;
                }

                const assistantMessage = await addMessage(
                    activeSessionId,
                    "assistant",
                    assistantText,
                    chatKey,
                    parentMessageUuid,
                );

                void updateBranchSelectionState(
                    parentMessageUuid,
                    assistantMessage.messageUuid,
                );
                appendMessageToState(assistantMessage);
                updateSessionAfterMessage(assistantMessage);

                void maybeGenerateSessionTitle({
                    sessionUuid: activeSessionId,
                    assistantMessageUuid: assistantMessage.messageUuid,
                    wasInterrupted: !!errorMessage,
                });
            } catch (error) {
                if (!isActiveGeneration()) {
                    return;
                }
                const message = formatErrorMessage(error);
                showMiniDialog({ title: "Model error", message });
                if (previousSelection) {
                    void updateBranchSelectionState(
                        parentMessageUuid,
                        previousSelection,
                    );
                }
            } finally {
                if (!isActiveGeneration()) {
                    return;
                }
                setIsGenerating(false);
                setIsStreamingOutro(false);
                setIsDownloading(false);
                streamingBufferRef.current = "";
                streamingChunksRef.current = [];
                setStreamingText("");
                setStreamingParentId(null);
                streamingCreatedAtRef.current = null;
                currentJobIdRef.current = null;
                pendingCancelRef.current = false;
            }
        },
        [
            chatKey,
            currentSessionId,
            ensureProvider,
            getModelSettings,
            buildHistory,
            branchSelections,
            updateBranchSelectionState,
            appendMessageToState,
            updateSessionAfterMessage,
            showMiniDialog,
            approxTokens,
            formatErrorMessage,
            scheduleStreamingFlush,
            flushStreamingText,
            maybeGenerateSessionTitle,
            systemPrompt,
        ],
    );

    const handleRetryMessage = useCallback(
        async (message: ChatMessage) => {
            if (message.sender !== "assistant") return;
            if (!chatKey || !currentSessionId) return;
            if (isDownloading) {
                showMiniDialog({
                    title: "Model download in progress",
                    message: "Please wait for the model to finish downloading.",
                });
                return;
            }
            if (isGenerating) {
                showMiniDialog({
                    title: "Already generating",
                    message: "Please wait for the current response to finish.",
                });
                return;
            }
            const parentUuid = message.parentMessageUuid;
            if (!parentUuid) {
                showMiniDialog({
                    title: "Retry failed",
                    message: "No parent message found for retry.",
                });
                return;
            }
            const parentMessage = allMessages.find(
                (item) => item.messageUuid === parentUuid,
            );
            if (!parentMessage) {
                showMiniDialog({
                    title: "Retry failed",
                    message: "Parent message is missing.",
                });
                return;
            }
            const historyPath = slicePathUntil(messageState.path, parentUuid);
            await startGeneration({
                promptText: parentMessage.text,
                parentMessageUuid: parentUuid,
                historyPath,
                stopAtMessageUuid: parentUuid,
                resetContext: true,
                sessionUuid: currentSessionId ?? undefined,
            });
        },
        [
            allMessages,
            chatKey,
            currentSessionId,
            isDownloading,
            isGenerating,
            messageState.path,
            slicePathUntil,
            startGeneration,
            showMiniDialog,
        ],
    );

    const handlePrevBranch = useCallback(
        (switcher: BranchSwitcher) => {
            if (!switcher || switcher.total <= 1) return;
            const nextIndex =
                (switcher.currentIndex - 1 + switcher.total) % switcher.total;
            const target = switcher.targets[nextIndex];
            if (!target) return;
            void updateBranchSelectionState(switcher.selectionKey, target);
        },
        [updateBranchSelectionState],
    );

    const handleNextBranch = useCallback(
        (switcher: BranchSwitcher) => {
            if (!switcher || switcher.total <= 1) return;
            const nextIndex = (switcher.currentIndex + 1) % switcher.total;
            const target = switcher.targets[nextIndex];
            if (!target) return;
            void updateBranchSelectionState(switcher.selectionKey, target);
        },
        [updateBranchSelectionState],
    );

    const handleOpenDrawer = useCallback(() => {
        if (isSmall) {
            setDrawerOpen(true);
            return;
        }
        setDrawerCollapsed(false);
    }, [isSmall]);

    const handleCloseDrawer = useCallback(() => {
        if (isSmall) {
            setDrawerOpen(false);
        } else {
            setDrawerCollapsed(true);
        }
    }, [isSmall]);

    const handleCollapseDrawer = useCallback(() => {
        handleCloseDrawer();
    }, [handleCloseDrawer]);

    const openSettingsModal = useCallback(() => setShowSettingsModal(true), []);
    const closeSettingsModal = useCallback(
        () => setShowSettingsModal(false),
        [],
    );

    const handleLogoClick = useCallback(() => {
        if (typeof window === "undefined") return;
        window.location.reload();
    }, []);

    const markUserScrollIntent = useCallback(() => {
        userScrollIntentRef.current = true;
        if (userScrollTimeoutRef.current) {
            window.clearTimeout(userScrollTimeoutRef.current);
        }
        userScrollTimeoutRef.current = window.setTimeout(() => {
            userScrollIntentRef.current = false;
            userScrollTimeoutRef.current = null;
        }, 200);
    }, []);

    const handleScroll = useCallback(() => {
        const container = scrollContainerRef.current;
        if (!container) return;
        const distance =
            container.scrollHeight -
            container.scrollTop -
            container.clientHeight;
        const atBottom = distance <= 120;
        const previousTop = lastScrollTopRef.current;
        const currentTop = container.scrollTop;
        lastScrollTopRef.current = currentTop;

        if (
            currentTop < previousTop - 4 &&
            userScrollIntentRef.current &&
            !atBottom
        ) {
            setStickToBottom(false);
            return;
        }

        if (atBottom) {
            setStickToBottom(true);
        }
    }, []);

    const handleStickToBottomChange = useCallback(
        (value: boolean) => {
            setStickToBottom(value);
        },
        [setStickToBottom],
    );

    useEffect(() => {
        if (!isGenerating || !stickToBottom) return;

        const frame = window.requestAnimationFrame(() => {
            const container = scrollContainerRef.current;
            if (!container) return;
            container.scrollTop = container.scrollHeight;
            lastScrollTopRef.current = container.scrollTop;
        });

        return () => {
            window.cancelAnimationFrame(frame);
        };
    }, [displayMessages, isGenerating, loadingDots, stickToBottom]);

    const handleOpenSessionSearch = useCallback(() => {
        setShowSessionSearch(true);
    }, []);
    const handleCloseSessionSearch = useCallback(() => {
        setSessionSearch("");
        setShowSessionSearch(false);
    }, []);

    const saveLogs = useCallback(async () => {
        log.info("Saving logs");
        const electron = globalThis.electron;
        if (electron) {
            await electron.openLogDirectory();
            return;
        }

        if (isTauriRuntime) {
            try {
                const { save } = await import("@tauri-apps/plugin-dialog");
                const filename = `ensu-web-logs-${Date.now()}.txt`;
                const path = await save({
                    defaultPath: filename,
                    filters: [{ name: "Logs", extensions: ["txt"] }],
                });
                if (!path) return;
                const { writeFile } = await import("@tauri-apps/plugin-fs");
                const encoded = new TextEncoder().encode(savedLogs());
                await writeFile(path, encoded);
                return;
            } catch (error) {
                log.error("Failed to export logs", error);
                showMiniDialog({
                    title: "Save logs failed",
                    message:
                        "We could not save the log file. Please check the console for errors.",
                });
                return;
            }
        }

        saveStringAsFile(savedLogs(), `ente-web-logs-${Date.now()}.txt`);
    }, [isTauriRuntime, showMiniDialog]);

    const handleCheckForUpdates = useCallback(async () => {
        await handleManualAppUpdateCheck(showMiniDialog);
    }, [showMiniDialog]);

    const openModelSettings = useCallback(() => {
        if (!advancedUnlocked) return;
        setShowModelSettings(true);
    }, [advancedUnlocked]);
    const closeModelSettings = useCallback(
        () => setShowModelSettings(false),
        [],
    );
    const openSystemPromptSettings = useCallback(() => {
        if (!advancedUnlocked) return;
        setShowSystemPromptSettings(true);
    }, [advancedUnlocked]);
    const closeSystemPromptSettings = useCallback(
        () => setShowSystemPromptSettings(false),
        [],
    );

    const handleBuildVersionTap = useCallback(() => {
        if (advancedUnlocked || typeof window === "undefined") return;
        if (buildVersionTapTimeoutRef.current) {
            window.clearTimeout(buildVersionTapTimeoutRef.current);
        }
        buildVersionTapCountRef.current += 1;
        if (buildVersionTapCountRef.current >= 5) {
            buildVersionTapCountRef.current = 0;
            setAdvancedUnlocked(true);
            window.localStorage.setItem(ADVANCED_SETTINGS_UNLOCK_KEY, "1");
            return;
        }
        buildVersionTapTimeoutRef.current = window.setTimeout(() => {
            buildVersionTapCountRef.current = 0;
            buildVersionTapTimeoutRef.current = null;
        }, 1800);
    }, [advancedUnlocked]);

    // Hardcoded fallbacks used when Rust defaults are not available (web-only
    // mode). These must stay in sync with rust/crates/ensu/src/config.rs.
    const fallbackSuggestedModels = useMemo(
        () =>
            isTauriRuntime
                ? FALLBACK_DESKTOP_MODEL_PRESETS
                : FALLBACK_MOBILE_MODEL_PRESETS,
        [isTauriRuntime],
    );
    const suggestedModels = resolvedModelPresets ?? fallbackSuggestedModels;

    const handleSaveModel = useCallback(
        (draft: {
            useCustomModel: boolean;
            modelUrl: string;
            mmprojUrl: string;
            contextLength: string;
            maxTokens: string;
        }) => {
            setIsSavingModel(true);
            const payload = {
                useCustomModel: draft.useCustomModel,
                modelUrl: draft.useCustomModel ? draft.modelUrl : "",
                mmprojUrl:
                    draft.useCustomModel && isTauriRuntime
                        ? draft.mmprojUrl
                        : "",
                contextLength: draft.contextLength,
                maxTokens: draft.maxTokens,
            };
            if (typeof window !== "undefined") {
                window.localStorage.setItem(
                    MODEL_SETTINGS_STORAGE_KEY,
                    JSON.stringify(payload),
                );
                void setKV(MODEL_SETTINGS_STORAGE_KEY, payload);
            }
            setUseCustomModel(draft.useCustomModel);
            setModelUrl(draft.modelUrl);
            setMmprojUrl(draft.mmprojUrl);
            setContextLength(draft.contextLength);
            setMaxTokens(draft.maxTokens);
            setLoadedModelName(null);
            setIsSavingModel(false);
            setShowModelSettings(false);
        },
        [isTauriRuntime],
    );

    const handleUseDefaultModel = useCallback(() => {
        if (typeof window !== "undefined") {
            window.localStorage.setItem(
                MODEL_SETTINGS_STORAGE_KEY,
                JSON.stringify({
                    useCustomModel: false,
                    modelUrl: "",
                    mmprojUrl: "",
                    contextLength: "",
                    maxTokens: "",
                }),
            );
            void removeKV(MODEL_SETTINGS_STORAGE_KEY);
        }
        setUseCustomModel(false);
        setModelUrl("");
        setMmprojUrl("");
        setContextLength("");
        setMaxTokens("");
        setLoadedModelName(null);
        setShowModelSettings(false);
    }, []);

    const handleSaveSystemPrompt = useCallback((promptText: string) => {
        const normalizedPrompt = promptText.trim();
        const isDefaultPrompt =
            !normalizedPrompt ||
            normalizedPrompt === DEFAULT_CHAT_SYSTEM_PROMPT_BODY;
        if (typeof window !== "undefined") {
            if (!isDefaultPrompt) {
                window.localStorage.setItem(
                    SYSTEM_PROMPT_STORAGE_KEY,
                    normalizedPrompt,
                );
            } else {
                window.localStorage.removeItem(SYSTEM_PROMPT_STORAGE_KEY);
            }
        }
        setSystemPrompt(
            isDefaultPrompt
                ? DEFAULT_CHAT_SYSTEM_PROMPT_BODY
                : normalizedPrompt,
        );
        setShowSystemPromptSettings(false);
    }, []);

    const handleUseDefaultSystemPrompt = useCallback(() => {
        if (typeof window !== "undefined") {
            window.localStorage.removeItem(SYSTEM_PROMPT_STORAGE_KEY);
        }
        setSystemPrompt(DEFAULT_CHAT_SYSTEM_PROMPT_BODY);
        setShowSystemPromptSettings(false);
    }, []);

    const closeAttachmentMenu = useCallback(() => {
        setAttachmentAnchor(null);
    }, []);

    const handleDocumentSelect = useCallback(
        (files: File[]) => {
            closeAttachmentMenu();
            void (async () => {
                const results = await Promise.allSettled(
                    files.map(async (file) => ({
                        id: createDocumentId(),
                        name: file.name,
                        text: await file.text(),
                        size: file.size,
                    })),
                );

                const successful = results
                    .filter(
                        (
                            result,
                        ): result is PromiseFulfilledResult<DocumentAttachment> =>
                            result.status === "fulfilled",
                    )
                    .map((result) => result.value);

                if (successful.length) {
                    setPendingDocuments((prev) => [...prev, ...successful]);
                }

                const failed = results.length - successful.length;
                if (failed > 0) {
                    showMiniDialog({
                        title: "Some documents failed",
                        message:
                            "We could not read some documents. Please try again.",
                    });
                }
            })();
        },
        [closeAttachmentMenu, showMiniDialog],
    );

    const handleDocumentCancel = useCallback(() => {
        closeAttachmentMenu();
    }, [closeAttachmentMenu]);

    const {
        getInputProps: getDocumentInputProps,
        openSelector: openDocumentSelector,
    } = useFileInput({
        directory: false,
        onSelect: handleDocumentSelect,
        onCancel: handleDocumentCancel,
    });
    const imageAttachmentSlotsRemaining = Math.max(
        0,
        MAX_IMAGE_ATTACHMENTS_PER_MESSAGE - pendingImages.length,
    );
    const isImageAttachmentLimitReached = imageAttachmentSlotsRemaining === 0;
    const canHandleImageDrop =
        showImageAttachment &&
        !isGenerating &&
        !isDownloading &&
        !showModelGate;
    const canAttachDroppedImages =
        canHandleImageDrop &&
        !isImageAttachmentLimitReached &&
        !isProcessingDroppedImages;
    const showImageDropOverlay =
        canHandleImageDrop && (isImageDragActive || isProcessingDroppedImages);
    const imageDropOverlayTitle = isProcessingDroppedImages
        ? "Attaching images..."
        : isImageAttachmentLimitReached
          ? "Image limit reached"
          : "Drop images to attach";
    const imageDropOverlayDescription = isImageAttachmentLimitReached
        ? `You can attach up to ${MAX_IMAGE_ATTACHMENTS_PER_MESSAGE} images per message.`
        : "PNG, JPG, WebP, GIF, BMP, HEIC, HEIF, AVIF";

    useEffect(() => {
        if (!canHandleImageDrop) {
            setIsImageDragActive(false);
        }
    }, [canHandleImageDrop]);

    const handleImageSelect = useCallback(
        (files: File[]) => {
            closeAttachmentMenu();
            if (imageAttachmentSlotsRemaining <= 0) return;
            const images = files.map((file) => ({
                id: createAttachmentId(),
                name: file.name.replace(/\0/g, ""),
                size: file.size,
                file,
            }));
            if (images.length) {
                setPendingImages((prev) => {
                    const slotsRemaining = Math.max(
                        0,
                        MAX_IMAGE_ATTACHMENTS_PER_MESSAGE - prev.length,
                    );
                    if (slotsRemaining === 0) return prev;
                    return [...prev, ...images.slice(0, slotsRemaining)];
                });
            }
        },
        [closeAttachmentMenu, imageAttachmentSlotsRemaining],
    );

    const handleImageCancel = useCallback(() => {
        closeAttachmentMenu();
    }, [closeAttachmentMenu]);

    const {
        getInputProps: getImageInputProps,
        openSelector: openImageSelector,
    } = useFileInput({
        directory: false,
        accept: IMAGE_SELECTOR_ACCEPT,
        onSelect: handleImageSelect,
        onCancel: handleImageCancel,
    });

    const processTauriImagePaths = useCallback(
        async (selectedPaths: string[], source: "picker" | "drop") => {
            if (imageAttachmentSlotsRemaining <= 0) return;
            const pathsToProcess = selectedPaths.slice(
                0,
                imageAttachmentSlotsRemaining,
            );
            if (pathsToProcess.length === 0) {
                handleImageCancel();
                return;
            }

            const isDrop = source === "drop";
            if (isDrop) setIsProcessingDroppedImages(true);

            try {
                const { invoke } = await import("@tauri-apps/api/core");
                const files = await Promise.all(
                    pathsToProcess.map(async (selectedPath) => {
                        const normalized = selectedPath.replace(/\\/g, "/");
                        const name =
                            normalized.split("/").pop()?.replace(/\0/g, "") ||
                            "image";
                        const compressed = await invoke<number[]>(
                            "chat_db_compress_attachment_image_file",
                            { path: selectedPath },
                        );
                        const bytes = new Uint8Array(compressed);
                        return new File(
                            [toSafeBlobPart(bytes)],
                            normalizedJpegAttachmentName(name),
                            { type: "image/jpeg" },
                        );
                    }),
                );

                log.info(
                    `Compressed ${source === "drop" ? "dropped" : "selected"} image attachments`,
                    {
                        count: files.length,
                        totalBytes: files.reduce(
                            (sum, file) => sum + file.size,
                            0,
                        ),
                    },
                );

                if (files.length > 0) {
                    handleImageSelect(files);
                    prewarmSelectedImageInference();
                } else {
                    handleImageCancel();
                }
            } catch (error) {
                log.error(
                    `Failed to process ${source === "drop" ? "dropped" : "selected"} image attachment: ${formatImageProcessingErrorForLog(error)}`,
                );
                showMiniDialog(
                    imageProcessingFailureDialog(error, pathsToProcess.length),
                );
                return;
            } finally {
                if (isDrop) setIsProcessingDroppedImages(false);
            }
        },
        [
            handleImageCancel,
            handleImageSelect,
            imageAttachmentSlotsRemaining,
            prewarmSelectedImageInference,
            showMiniDialog,
        ],
    );

    const openTauriImageSelector = useCallback(async () => {
        closeAttachmentMenu();
        if (imageAttachmentSlotsRemaining <= 0) return;
        try {
            const { open: openFileDialog } =
                await import("@tauri-apps/plugin-dialog");
            const selection = await openFileDialog({
                directory: false,
                multiple: true,
                filters: [
                    {
                        name: "Images",
                        extensions: [...IMAGE_SELECTOR_EXTENSIONS],
                    },
                ],
            });
            if (!selection) {
                handleImageCancel();
                return;
            }
            const selectedPaths = Array.isArray(selection)
                ? selection
                : [selection];
            if (selectedPaths.length === 0) {
                handleImageCancel();
                return;
            }
            await processTauriImagePaths(selectedPaths, "picker");
        } catch (error) {
            log.error("Failed to open image picker", error);
            showMiniDialog({
                title: "Image picker unavailable",
                message: "Could not open the image picker. Please try again.",
            });
        }
    }, [
        closeAttachmentMenu,
        handleImageCancel,
        imageAttachmentSlotsRemaining,
        processTauriImagePaths,
        showMiniDialog,
    ]);

    useEffect(() => {
        if (!isTauriRuntime || !showImageAttachment) return;

        let disposed = false;
        let unlisten: (() => void) | undefined;

        void import("@tauri-apps/api/webview")
            .then(({ getCurrentWebview }) =>
                getCurrentWebview().onDragDropEvent((event) => {
                    if (
                        event.payload.type === "enter" ||
                        event.payload.type === "over"
                    ) {
                        if (canHandleImageDrop) {
                            setIsImageDragActive(true);
                        }
                        return;
                    }

                    if (event.payload.type === "leave") {
                        setIsImageDragActive(false);
                        return;
                    }

                    setIsImageDragActive(false);
                    if (!canHandleImageDrop) return;
                    if (isImageAttachmentLimitReached) {
                        showMiniDialog({
                            title: "Image limit reached",
                            message: `You can attach up to ${MAX_IMAGE_ATTACHMENTS_PER_MESSAGE} images per message.`,
                        });
                        return;
                    }
                    if (!canAttachDroppedImages) return;

                    const imagePaths = event.payload.paths.filter((path) => {
                        const lowerPath = path.toLowerCase();
                        return IMAGE_SELECTOR_EXTENSIONS.some((extension) =>
                            lowerPath.endsWith(`.${extension}`),
                        );
                    });
                    if (imagePaths.length === 0) {
                        showMiniDialog({
                            title: "No supported images",
                            message:
                                "Drop PNG, JPG, WebP, GIF, BMP, HEIC, HEIF, or AVIF images.",
                        });
                        return;
                    }

                    void processTauriImagePaths(imagePaths, "drop");
                }),
            )
            .then((dispose) => {
                if (disposed) {
                    dispose();
                } else {
                    unlisten = dispose;
                }
            })
            .catch((error: unknown) => {
                log.error(
                    "Failed to subscribe to Tauri image drop events",
                    error,
                );
            });

        return () => {
            disposed = true;
            unlisten?.();
        };
    }, [
        canAttachDroppedImages,
        canHandleImageDrop,
        isImageAttachmentLimitReached,
        isTauriRuntime,
        processTauriImagePaths,
        showImageAttachment,
        showMiniDialog,
    ]);

    const openAttachmentMenu = useCallback(
        (_event: React.MouseEvent<HTMLElement>) => {
            closeAttachmentMenu();
            if (showImageAttachment) {
                if (isImageAttachmentLimitReached) return;
                if (isTauriRuntime) {
                    void openTauriImageSelector();
                } else {
                    openImageSelector();
                }
                return;
            }
            openDocumentSelector();
        },
        [
            closeAttachmentMenu,
            isTauriRuntime,
            isImageAttachmentLimitReached,
            openDocumentSelector,
            openImageSelector,
            openTauriImageSelector,
            showImageAttachment,
        ],
    );

    const handleAttachmentChoice = useCallback(
        (choice: "image" | "document") => {
            closeAttachmentMenu();
            if (choice === "image") {
                if (isImageAttachmentLimitReached) return;
                openImageSelector();
            } else {
                openDocumentSelector();
            }
        },
        [
            closeAttachmentMenu,
            isImageAttachmentLimitReached,
            openDocumentSelector,
            openImageSelector,
        ],
    );

    const removePendingDocument = useCallback((id: string) => {
        setPendingDocuments((prev) => prev.filter((doc) => doc.id !== id));
    }, []);

    const removePendingImage = useCallback((id: string) => {
        setPendingImages((prev) => prev.filter((img) => img.id !== id));
    }, []);

    const handleSend = useCallback(async () => {
        const trimmed = input.trim();
        const hasDocuments = pendingDocuments.length > 0;
        const hasImages = pendingImages.length > 0;
        if (!chatKey) {
            showMiniDialog({
                title: "Chat unavailable",
                message:
                    "Encryption is still initializing. Please try again in a moment.",
            });
            return;
        }
        if (!trimmed && !hasDocuments && !hasImages) {
            return;
        }
        if (isDownloading) {
            showMiniDialog({
                title: "Model download in progress",
                message: "Please wait for the model to finish downloading.",
            });
            return;
        }
        if (isGenerating) {
            showMiniDialog({
                title: "Already generating",
                message: "Please wait for the current response to finish.",
            });
            return;
        }

        setStickToBottom(true);

        let activeSessionId = currentSessionId;
        if (!activeSessionId) {
            try {
                activeSessionId = await createSession(chatKey);
            } catch (error) {
                onGenericError(error);
                return;
            }
            setCurrentSessionId(activeSessionId);
            currentSessionIdRef.current = activeSessionId;
            setIsDraftSession(false);
            isDraftSessionRef.current = false;
            updateRouteSession(activeSessionId, true);
            await refreshSessions();
        }

        const messageText = buildPromptWithDocuments(
            trimmed.replace(/\u0000/g, ""),
            pendingDocuments,
        );
        const persistedAttachmentIds = new Set(
            (editingMessage?.attachments ?? []).map(({ id }) => id),
        );
        const newAttachmentIds = [
            ...pendingDocuments.map(({ id }) => id),
            ...pendingImages.map(({ id }) => id),
        ].filter((id) => !persistedAttachmentIds.has(id));
        const cleanupUnstoredAttachments = async () => {
            await Promise.all(
                newAttachmentIds.map(async (id) => {
                    try {
                        await deleteAttachmentBytes(id);
                    } catch (error) {
                        log.warn(
                            `Failed to clean up attachment payload ${id}`,
                            error,
                        );
                    }
                }),
            );
        };
        let inferenceImagePaths: string[] = [];

        let attachments: ChatAttachment[] = [];
        if (pendingDocuments.length > 0 || pendingImages.length > 0) {
            try {
                const encoder = new TextEncoder();
                const documentAttachments = await Promise.all(
                    pendingDocuments.map(async (doc) => {
                        const bytes = encoder.encode(doc.text);
                        await storeEncryptedAttachmentBytes(
                            doc.id,
                            bytes,
                            chatKey,
                            activeSessionId,
                        );
                        return {
                            id: doc.id,
                            kind: "document",
                            name: doc.name.replace(/\0/g, ""),
                            size: bytes.length,
                        } satisfies ChatAttachment;
                    }),
                );
                const imageAttachments = await Promise.all(
                    pendingImages.map(async (img) => {
                        const bytes = new Uint8Array(
                            await img.file.arrayBuffer(),
                        );
                        await storeEncryptedAttachmentBytes(
                            img.id,
                            bytes,
                            chatKey,
                            activeSessionId,
                        );
                        const previewUrl = URL.createObjectURL(
                            new Blob([toSafeBlobPart(bytes)]),
                        );
                        attachmentPreviewUrlsRef.current[img.id] = previewUrl;
                        setAttachmentPreviews((prev) => ({
                            ...prev,
                            [img.id]: previewUrl,
                        }));
                        return {
                            id: img.id,
                            kind: "image",
                            name: img.name.replace(/\0/g, ""),
                            size: img.size,
                        } satisfies ChatAttachment;
                    }),
                );
                attachments = [...documentAttachments, ...imageAttachments];
            } catch (error) {
                await cleanupUnstoredAttachments();
                log.error("Failed to store attachments", error);
                showMiniDialog({
                    title: "Attachment error",
                    message: "We could not attach the files. Please try again.",
                });
                return;
            }
        }

        if (pendingImages.length > 0) {
            try {
                inferenceImagePaths = await writeInferenceImages(pendingImages);
            } catch (error) {
                await cleanupUnstoredAttachments();
                log.error("Failed to prepare images for inference", error);
                showMiniDialog({
                    title: "Attachment error",
                    message:
                        "We could not prepare the images for inference. Please try again.",
                });
                return;
            }
        }

        const promptText = buildPromptWithImages(
            messageText,
            inferenceImagePaths.length,
        );

        setInput("");

        let messageStored = false;
        try {
            if (editingMessage) {
                const parentUuid = editingMessage.parentMessageUuid;
                const selectionKey = parentUuid ?? ROOT_SELECTION_KEY;
                const historyPath = parentUuid
                    ? slicePathUntil(messageState.path, parentUuid)
                    : [];

                const newUserMessage = await addMessage(
                    activeSessionId,
                    "self",
                    messageText,
                    chatKey,
                    parentUuid,
                    attachments,
                );
                messageStored = true;

                void updateBranchSelectionState(
                    selectionKey,
                    newUserMessage.messageUuid,
                );
                appendMessageToState(newUserMessage);
                updateSessionAfterMessage(newUserMessage);
                setEditingMessage(null);
                setPendingDocuments([]);
                setPendingImages([]);

                await startGeneration({
                    promptText,
                    parentMessageUuid: newUserMessage.messageUuid,
                    historyPath,
                    sessionUuid: activeSessionId,
                    imagePaths: inferenceImagePaths,
                    mediaMarker: MEDIA_MARKER,
                });
                return;
            }

            const basePath = messageState.path;
            const leaf = basePath[basePath.length - 1];
            const parentUuid = leaf?.messageUuid;
            const selectionKey = parentUuid ?? ROOT_SELECTION_KEY;

            const userMessage = await addMessage(
                activeSessionId,
                "self",
                messageText,
                chatKey,
                parentUuid,
                attachments,
            );
            messageStored = true;

            void updateBranchSelectionState(
                selectionKey,
                userMessage.messageUuid,
            );
            appendMessageToState(userMessage);
            updateSessionAfterMessage(userMessage);
            setPendingDocuments([]);
            setPendingImages([]);

            await startGeneration({
                promptText,
                parentMessageUuid: userMessage.messageUuid,
                historyPath: basePath,
                sessionUuid: activeSessionId,
                imagePaths: inferenceImagePaths,
                mediaMarker: MEDIA_MARKER,
            });
        } catch (error) {
            if (!messageStored) await cleanupUnstoredAttachments();
            log.error("Failed to store chat message", error);
        } finally {
            await cleanupInferenceImages(inferenceImagePaths);
        }
    }, [
        input,
        chatKey,
        currentSessionId,
        editingMessage,
        isDownloading,
        isGenerating,
        messageState.path,
        pendingDocuments,
        pendingImages,
        showMiniDialog,
        onGenericError,
        slicePathUntil,
        startGeneration,
        writeInferenceImages,
        cleanupInferenceImages,
        updateBranchSelectionState,
        updateRouteSession,
        appendMessageToState,
        updateSessionAfterMessage,
        refreshSessions,
    ]);

    useEffect(() => {
        return () => {
            if (streamingFlushTimerRef.current) {
                window.clearTimeout(streamingFlushTimerRef.current);
            }
            if (downloadProgressTimerRef.current) {
                window.clearTimeout(downloadProgressTimerRef.current);
            }
            if (userScrollTimeoutRef.current) {
                window.clearTimeout(userScrollTimeoutRef.current);
            }
        };
    }, []);

    const sidebar = (
        <ChatSidebar
            drawerCollapsed={drawerCollapsed}
            drawerIconButtonSx={drawerIconButtonSx}
            actionButtonSx={actionButtonSx}
            smallIconProps={smallIconProps}
            tinyIconProps={tinyIconProps}
            actionIconProps={actionIconProps}
            showSessionSearch={showSessionSearch}
            sessionSearch={sessionSearch}
            setSessionSearch={setSessionSearch}
            handleOpenSessionSearch={handleOpenSessionSearch}
            handleCloseSessionSearch={handleCloseSessionSearch}
            handleNewChat={handleNewChat}
            handleOpenDrawer={handleOpenDrawer}
            handleCollapseDrawer={handleCollapseDrawer}
            groupedSessions={groupedSessions}
            currentSessionId={currentSessionId}
            handleSelectSession={handleSelectSession}
            requestDeleteSession={requestDeleteSession}
            openSettingsModal={openSettingsModal}
        />
    );

    if (loading) return <></>;

    return (
        <>
            <Box
                sx={{
                    display: "flex",
                    height: "var(--ensu-viewport-height, 100svh)",
                    width: "100%",
                    maxWidth: "100vw",
                    bgcolor: "background.default",
                    fontFamily: messageFontFamily,
                    overflow: "hidden",
                }}
            >
                <Drawer
                    variant={isSmall ? "temporary" : "permanent"}
                    open={isSmall ? drawerOpen : true}
                    onClose={handleCloseDrawer}
                    ModalProps={isSmall ? { keepMounted: true } : undefined}
                    sx={{
                        flexShrink: 0,
                        "& .MuiDrawer-paper": {
                            width: drawerWidth,
                            boxSizing: "border-box",
                            position: isSmall ? "fixed" : "relative",
                            overflowX: "hidden",
                            pointerEvents:
                                isSmall || !drawerCollapsed ? "auto" : "none",
                        },
                    }}
                    slotProps={{
                        paper: {
                            sx: {
                                backgroundColor: "background.default",
                                borderRightColor: drawerCollapsed
                                    ? "transparent"
                                    : "divider",
                            },
                        },
                    }}
                >
                    {sidebar}
                </Drawer>

                <Box
                    ref={chatViewportRef}
                    sx={{
                        flex: 1,
                        display: "flex",
                        flexDirection: "column",
                        height: "100%",
                        position: "relative",
                        minWidth: 0,
                        maxWidth: "100%",
                        overflow: "hidden",
                    }}
                >
                    <NavbarBase
                        sx={{
                            justifyContent: "space-between",
                            px: 2,
                            height: 64,
                            minHeight: 64,
                            bgcolor: isDesktopOverlay
                                ? "transparent"
                                : "background.paper",
                            borderBottom: isDesktopOverlay ? "none" : undefined,
                            position: isDesktopOverlay
                                ? "absolute"
                                : "relative",
                            top: isDesktopOverlay ? 0 : undefined,
                            left: isDesktopOverlay ? 0 : undefined,
                            right: isDesktopOverlay ? 0 : undefined,
                            zIndex: isDesktopOverlay ? 10 : undefined,
                        }}
                    >
                        <Stack
                            direction="row"
                            sx={{ gap: 1.5, alignItems: "center" }}
                        >
                            {showDrawerToggle && (
                                <IconButton
                                    aria-label="Open menu"
                                    onClick={handleOpenDrawer}
                                    sx={drawerIconButtonSx}
                                >
                                    <HugeiconsIcon
                                        icon={Menu01Icon}
                                        {...smallIconProps}
                                    />
                                </IconButton>
                            )}
                            <Stack sx={{ gap: 0 }}>
                                <Box
                                    component="button"
                                    onClick={handleLogoClick}
                                    onMouseDown={(event) =>
                                        event.preventDefault()
                                    }
                                    onDoubleClick={(event) =>
                                        event.preventDefault()
                                    }
                                    onPointerDown={(event) =>
                                        event.preventDefault()
                                    }
                                    sx={{
                                        border: "none",
                                        padding: 0,
                                        background: "transparent",
                                        cursor: "pointer",
                                        display: "flex",
                                        alignItems: "center",
                                        userSelect: "none",
                                        WebkitUserSelect: "none",
                                        MozUserSelect: "none",
                                        msUserSelect: "none",
                                        outline: "none",
                                    }}
                                >
                                    <Box
                                        component="img"
                                        src={logoSrc}
                                        alt="ensu"
                                        draggable={false}
                                        sx={{
                                            height: 16,
                                            width: "auto",
                                            filter: logoFilter,
                                        }}
                                    />
                                </Box>
                            </Stack>
                        </Stack>
                    </NavbarBase>

                    <ChatMessageList
                        messages={displayMessages}
                        attachmentPreviews={attachmentPreviews}
                        branchSwitchers={branchSwitchers}
                        loadingPhrase={loadingPhrase}
                        loadingDots={loadingDots}
                        isGenerating={isGenerating}
                        isStreamingOutro={isStreamingOutro}
                        stickToBottom={stickToBottom}
                        onStickToBottomChange={handleStickToBottomChange}
                        scrollContainerRef={scrollContainerRef}
                        onScroll={handleScroll}
                        onUserScrollIntent={markUserScrollIntent}
                        onOpenAttachment={handleOpenAttachment}
                        onEditMessage={handleEditMessage}
                        onCopyMessage={handleCopyMessage}
                        onRetryMessage={handleRetryMessage}
                        onPrevBranch={handlePrevBranch}
                        onNextBranch={handleNextBranch}
                        onRequestPreview={loadAttachmentPreview}
                        parseDocumentBlocks={parseDocumentBlocks}
                        stripHiddenParts={stripHiddenParts}
                        formatTime={formatTime}
                        isDesktopOverlay={isDesktopOverlay}
                        userBubbleBackground={userBubbleBackground}
                        userMessageTextSx={userMessageTextSx}
                        assistantTextSx={assistantTextSx}
                        assistantMarkdownSx={assistantMarkdownSx}
                        streamingMessageSx={streamingMessageSx}
                        actionButtonSx={actionButtonSx}
                        smallIconProps={smallIconProps}
                        actionIconProps={actionIconProps}
                    />

                    <ChatComposer
                        showModelGate={showModelGate}
                        showDownloadProgress={showDownloadProgress}
                        downloadStatus={downloadStatus}
                        downloadStatusLabel={downloadStatusLabel}
                        downloadSizeLabel={downloadSizeLabel}
                        modelGateStatus={modelGateStatus}
                        modelGateError={modelGateError}
                        isDownloading={isDownloading}
                        handleDownloadModel={handleDownloadModel}
                        editingMessage={editingMessage}
                        handleCancelEdit={handleCancelEdit}
                        pendingDocuments={pendingDocuments}
                        pendingImages={pendingImages}
                        pendingImagePreviews={pendingImagePreviews}
                        removePendingDocument={removePendingDocument}
                        removePendingImage={removePendingImage}
                        formatBytes={formatBytes}
                        input={input}
                        onInputChange={setInput}
                        inputRef={inputRef}
                        isGenerating={isGenerating}
                        handleSend={handleSend}
                        handleStopGeneration={handleStopGeneration}
                        showAttachmentPicker={isTauriRuntime}
                        openAttachmentMenu={openAttachmentMenu}
                        attachmentAnchor={attachmentAnchor}
                        closeAttachmentMenu={closeAttachmentMenu}
                        handleAttachmentChoice={handleAttachmentChoice}
                        showImageAttachment={showImageAttachment}
                        isImageAttachmentLimitReached={
                            isImageAttachmentLimitReached
                        }
                        getDocumentInputProps={getDocumentInputProps}
                        getImageInputProps={getImageInputProps}
                        actionButtonSx={actionButtonSx}
                        drawerIconButtonSx={drawerIconButtonSx}
                        smallIconProps={smallIconProps}
                        compactIconProps={compactIconProps}
                        actionIconProps={actionIconProps}
                        stopButtonColor={theme.palette.error.main}
                    />
                    {showImageDropOverlay && (
                        <Box
                            sx={{
                                position: "absolute",
                                inset: 0,
                                zIndex: 40,
                                display: "flex",
                                alignItems: "center",
                                justifyContent: "center",
                                pointerEvents: "none",
                                bgcolor: "rgba(0, 0, 0, 0.38)",
                                backdropFilter: "blur(10px)",
                                WebkitBackdropFilter: "blur(10px)",
                            }}
                        >
                            <Stack
                                sx={{
                                    alignItems: "center",
                                    gap: 0.75,
                                    px: 3,
                                    py: 2,
                                    borderRadius: 2,
                                    border: "1px solid rgba(255, 255, 255, 0.32)",
                                    bgcolor: "rgba(0, 0, 0, 0.42)",
                                    color: "#fff",
                                    boxShadow:
                                        "0 18px 48px rgba(0, 0, 0, 0.22)",
                                }}
                            >
                                <Typography
                                    variant="small"
                                    sx={{ fontWeight: 700, color: "inherit" }}
                                >
                                    {imageDropOverlayTitle}
                                </Typography>
                                <Typography
                                    variant="mini"
                                    sx={{ color: "rgba(255, 255, 255, 0.78)" }}
                                >
                                    {imageDropOverlayDescription}
                                </Typography>
                            </Stack>
                        </Box>
                    )}
                </Box>
            </Box>

            <ChatDialogs
                showSettingsModal={showSettingsModal}
                closeSettingsModal={closeSettingsModal}
                dialogPaperSx={dialogPaperSx}
                dialogTitleSx={dialogTitleSx}
                actionButtonSx={actionButtonSx}
                settingsItemSx={settingsItemSx}
                smallIconProps={smallIconProps}
                compactIconProps={compactIconProps}
                saveLogs={saveLogs}
                handleCheckForUpdates={handleCheckForUpdates}
                advancedUnlocked={advancedUnlocked}
                buildVersion={buildVersion}
                handleBuildVersionTap={handleBuildVersionTap}
                openModelSettings={openModelSettings}
                openSystemPromptSettings={openSystemPromptSettings}
                isSmall={isSmall}
                deleteSessionId={deleteSessionId}
                deleteSessionLabel={deleteSessionLabel}
                handleCancelDeleteSession={handleCancelDeleteSession}
                handleConfirmDeleteSession={handleConfirmDeleteSession}
                showModelSettings={showModelSettings}
                closeModelSettings={closeModelSettings}
                useCustomModel={useCustomModel}
                defaultModelName={resolvedDefaultModel.name}
                defaultModelUrl={resolvedDefaultModel.url}
                defaultModelMmproj={resolvedDefaultModel.mmprojUrl}
                loadedModelName={loadedModelName}
                allowMmproj={allowMmproj}
                isTauriRuntime={isTauriRuntime}
                modelUrl={modelUrl}
                mmprojUrl={mmprojUrl}
                suggestedModels={suggestedModels}
                contextLength={contextLength}
                maxTokens={maxTokens}
                isSavingModel={isSavingModel}
                handleSaveModel={handleSaveModel}
                handleUseDefaultModel={handleUseDefaultModel}
                showSystemPromptSettings={showSystemPromptSettings}
                closeSystemPromptSettings={closeSystemPromptSettings}
                systemPrompt={systemPrompt}
                handleSaveSystemPrompt={handleSaveSystemPrompt}
                handleUseDefaultSystemPrompt={handleUseDefaultSystemPrompt}
                chatNotificationOpen={chatNotificationOpen}
                setChatNotificationOpen={setChatNotificationOpen}
                chatNotification={chatNotification}
                modelGateStatus={modelGateStatus}
                imagePreview={imagePreview}
                closeImagePreview={closeImagePreview}
            />
        </>
    );
};

export default Page;
