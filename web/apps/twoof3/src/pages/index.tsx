import {
    MAX_SECRET_BYTES_FOR_PRINTED_CARD,
    canvasToBlob,
    downloadBlob,
    offlineRecoveryFile,
    preparePrintWindow,
    printBlob,
    renderShareCard,
    sanitizeFilename,
    shareFiles,
} from "@/features/twoof3/utils/export";
import {
    createQrSvgData,
    decodeQrFromFile,
} from "@/features/twoof3/utils/qrCode";
import {
    combineShares,
    parseShare,
    splitSecret,
} from "@/features/twoof3/utils/shamir";
import {
    Box,
    Button,
    Container,
    Stack,
    TextField,
    Typography,
} from "@mui/material";
import { useColorScheme } from "@mui/material/styles";
import Head from "next/head";
import type { ChangeEvent, DragEvent, ReactNode } from "react";
import {
    memo,
    startTransition,
    useCallback,
    useDeferredValue,
    useEffect,
    useRef,
    useState,
} from "react";

const APP_LINK = "2of3.ente.com";
const MAX_CARD_TITLE_LENGTH = 80;
const CARD_LABEL_FALLBACK = "Today";
const textEncoder = new TextEncoder();
const graphemeSegmenter =
    typeof Intl !== "undefined" && "Segmenter" in Intl
        ? new Intl.Segmenter(undefined, { granularity: "grapheme" })
        : null;

const byteLength = (value: string) => textEncoder.encode(value).length;

const splitGraphemes = (value: string) =>
    graphemeSegmenter
        ? Array.from(graphemeSegmenter.segment(value), ({ segment }) => segment)
        : Array.from(value);

const trimToByteLength = (value: string, maxBytes: number) => {
    if (byteLength(value) <= maxBytes) return value;

    const chars = splitGraphemes(value);
    while (chars.length > 0 && byteLength(chars.join("")) > maxBytes) {
        chars.pop();
    }

    return chars.join("");
};

const trimToCharacterLength = (value: string, maxChars: number) =>
    splitGraphemes(value).slice(0, maxChars).join("");

interface ShareCardState {
    encoded: string;
    fingerprint: string;
    index: 1 | 2 | 3;
    qr: NonNullable<ReturnType<typeof createQrSvgData>>;
}

interface SplitSnapshot {
    cards: ShareCardState[];
    error: string | null;
    secret: string;
}

interface RecoverSlot {
    fileName: string;
    value: string;
}

interface RecoverSlotDetails {
    fingerprint: string;
    index: 1 | 2 | 3;
    length: number;
}

const todayLabel = () =>
    new Intl.DateTimeFormat(undefined, {
        day: "numeric",
        month: "long",
        year: "numeric",
    }).format(new Date());

const shareFingerprint = (value: string) =>
    parseShare(value).id.slice(0, 8).toUpperCase();

const EMPTY_SPLIT_SNAPSHOT: SplitSnapshot = {
    cards: [],
    error: null,
    secret: "",
};

const RECOVER_SLOT_LABELS = ["A", "B"] as const;

const HELP_FAQS = [
    {
        question: "What is 2of3, exactly?",
        answer: "It turns one secret into three recovery cards. Any two cards can bring the secret back. One card by itself is not enough.",
    },
    {
        question: "When is this useful?",
        answer: "Use it for something important that feels risky to keep in one place: an Ente recovery key, a password manager master password, a wallet recovery phrase, or another recovery code you do not want to lose.",
    },
    {
        question: "Why not keep the secret in one note?",
        answer: "A single note is a single point of failure. If that one place is lost, stolen, or forgotten, recovery becomes hard. 2of3 lets you spread the risk without making recovery too difficult.",
    },
    {
        question: "Where should the cards go?",
        answer: "Keep the three cards in different safe places. Home, a safe, a trusted family member, or a document locker are all reasonable options. The important part is separation.",
    },
    {
        question: "Do I need all three cards later?",
        answer: "No. Any two are enough. The third card is there so one missing card does not lock you out.",
    },
    {
        question: "Can one card reveal my secret?",
        answer: "No. A single card cannot recover the original secret.",
    },
    {
        question: "How do I recover later?",
        answer: "Open 2of3 again, or use the offline recovery page that downloads with the cards. Upload any two card images, or paste their codes, and the secret appears on your device.",
    },
    {
        question: "Does this send my secret to Ente?",
        answer: "No. Your secret is split and recovered in your browser. The downloaded recovery page also works fully offline.",
    },
    {
        question: "What if 2of3.ente.com is unavailable?",
        answer: (
            <>
                A fully offline HTML recovery page is included when you use{" "}
                &quot;Download all cards&quot;. Open that file locally, add any
                two matching cards, and recover without needing the site. 2of3
                is also{" "}
                <Box
                    component="a"
                    href="https://github.com/ente/ente"
                    target="_blank"
                    rel="noopener"
                    sx={{
                        color: "inherit",
                        textDecorationColor: "currentColor",
                        textUnderlineOffset: "0.14em",
                    }}
                >
                    open source
                </Box>
                , so the format is inspectable and recovery is not locked to one
                hosted service.
            </>
        ),
    },
    {
        question: "What if I need to change the secret?",
        answer: "Treat it as a new set. Make three fresh cards and replace the old ones together. Do not mix cards from different IDs.",
    },
    {
        question: "Should I print the cards, download them, or both?",
        answer: "Either is fine. Printed cards are easy to store offline. Downloaded images are easier to duplicate carefully. Many people will want both.",
    },
    {
        question: "All this sounds magical, how does it work?",
        answer: "It uses Shamir secret sharing. Your secret is split into three shares in a way where mathematically any two parts reconstruct it while one alone reveals nothing. Think of it like a lock which needs 2 of 3 keys to open.",
    },
    {
        question: "Should I test recovery before storing the cards?",
        answer: "Yes. Before you put the cards away, try recovering the secret once with any two of them. It is the quickest way to catch a bad print, a saving mistake, or a card from the wrong set.",
    },
    {
        question: "Is the source code open?",
        answer: (
            <>
                Yes! 2of3 is part of Ente&apos;s{" "}
                <Box
                    component="a"
                    href="https://github.com/ente/ente"
                    target="_blank"
                    rel="noopener"
                    sx={{
                        color: "inherit",
                        textDecorationColor: "currentColor",
                        textUnderlineOffset: "0.14em",
                    }}
                >
                    open source
                </Box>{" "}
                repo.
            </>
        ),
    },
] as const;

const HELP_USE_CASES = [
    {
        title: "Legacy account recovery",
        detail: "You want a spouse, adult child, or executor to recover something important if you are not around to explain it. One card can stay with your documents, one in a safe place at home, and one with a trusted person. Any two are enough when the time comes.",
        tone: "accent",
        span: 7,
    },
    {
        title: "Saving 'root' credentials",
        detail: "You have one break-glass credential that matters a lot: a root password, a production recovery key, or the master secret behind your setup. 2of3 lets you avoid the two bad outcomes at once: one lost copy that locks you out, or one stolen copy that gives everything away.",
        tone: "plain",
        span: 5,
    },
    {
        title: "Family emergency pack",
        detail: "Some secrets are only needed during stressful moments: a password manager emergency kit, a wallet recovery phrase, or the one recovery code your household cannot afford to lose. Splitting it across three places means recovery stays possible even when one place fails.",
        tone: "soft",
        span: 12,
    },
] as const;

const HELP_CARD_LAYOUTS = [
    { offset: "0rem", span: 7, tone: "accent" },
    { offset: "1.5rem", span: 5, tone: "plain" },
    { offset: "0rem", span: 4, tone: "soft" },
    { offset: "1rem", span: 8, tone: "plain" },
    { offset: "1.4rem", span: 5, tone: "plain" },
    { offset: "0rem", span: 7, tone: "soft" },
    { offset: "0rem", span: 6, tone: "plain" },
    { offset: "1.2rem", span: 6, tone: "accent" },
    { offset: "1rem", span: 8, tone: "plain" },
    { offset: "0rem", span: 4, tone: "soft" },
    { offset: "0.45rem", span: 5, tone: "plain" },
    { offset: "1.35rem", span: 7, tone: "soft" },
    { offset: "0.25rem", span: 6, tone: "plain" },
    { offset: "0.95rem", span: 6, tone: "accent" },
] as const;

const recoverSlotLabel = (index: number) =>
    RECOVER_SLOT_LABELS[index] ?? String(index + 1);

const fieldSx = {
    "& .MuiOutlinedInput-root": {
        borderRadius: "18px",
        bgcolor: "var(--paper)",
        "& fieldset": {
            borderWidth: "1.5px",
            borderColor: "var(--line-strong)",
        },
        "&:hover fieldset": { borderWidth: "1.5px", borderColor: "var(--ink)" },
        "&.Mui-focused fieldset": {
            borderWidth: "1.5px",
            borderColor: "var(--ink)",
        },
    },
    "& .MuiInputBase-input": { fontSize: "0.98rem", lineHeight: 1.55 },
    "& .MuiInputLabel-root": { fontWeight: 700, color: "var(--muted)" },
    "& .MuiInputLabel-root.Mui-focused": { color: "var(--ink)" },
};

const Note = ({
    children,
    tone = "plain",
}: {
    children: ReactNode;
    tone?: "plain" | "accent" | "field";
}) => (
    <Box
        sx={{
            border: "1.5px solid",
            borderColor:
                tone === "accent"
                    ? "#111111"
                    : tone === "plain"
                      ? "var(--line-strong)"
                      : "var(--ink)",
            borderRadius: "18px",
            px: 1.5,
            py: 1.15,
            bgcolor:
                tone === "accent"
                    ? "var(--accent)"
                    : tone === "field"
                      ? "var(--field-soft)"
                      : "var(--paper)",
        }}
    >
        <Typography
            sx={{
                color: tone === "accent" ? "#111111" : "var(--ink)",
                fontSize: "0.95rem",
                lineHeight: 1.45,
                fontWeight: tone === "accent" ? 700 : 500,
            }}
        >
            {children}
        </Typography>
    </Box>
);

const QrPreview = memo(
    ({ value }: { value: NonNullable<ReturnType<typeof createQrSvgData>> }) => (
        <svg
            viewBox={`0 0 ${value.viewBoxSize} ${value.viewBoxSize}`}
            role="img"
            aria-label="QR code"
            shapeRendering="crispEdges"
            style={{
                width: "100%",
                height: "100%",
                display: "block",
                background: "#ffffff",
                imageRendering: "pixelated",
            }}
        >
            <rect
                width={value.viewBoxSize}
                height={value.viewBoxSize}
                rx="2.5"
                fill="#ffffff"
            />
            {value.modules.map((module) => (
                <rect
                    key={`${module.x}-${module.y}`}
                    x={module.x}
                    y={module.y}
                    width="1"
                    height="1"
                    rx="0.08"
                    fill="#111111"
                />
            ))}
        </svg>
    ),
);

interface ShareCardPanelProps {
    busy: boolean;
    card: ShareCardState | undefined;
    cardLabel: string;
    copied: boolean;
    index: number;
    onCardAction: (
        kind: "download" | "print" | "share",
        card: ShareCardState,
        displayIndex: number,
        label: string,
    ) => void;
    onCopyCardCode: (card: ShareCardState, displayIndex: number) => void;
}

const ShareCardPanel = memo(
    ({
        busy,
        card,
        cardLabel,
        copied,
        index,
        onCardAction,
        onCopyCardCode,
    }: ShareCardPanelProps) => {
        const fingerprint = card ? `ID ${card.fingerprint}` : null;

        return (
            <Stack
                sx={{
                    border: "1.5px solid",
                    borderColor: "var(--edge)",
                    borderRadius: "26px",
                    bgcolor: "var(--paper)",
                    boxShadow: "var(--shadow-card)",
                    minHeight: 0,
                    overflow: "hidden",
                }}
            >
                <Box
                    sx={{
                        px: 1.35,
                        py: 1.05,
                        bgcolor: "var(--accent)",
                        borderBottom: "1.5px solid",
                        borderColor: "var(--accent-edge)",
                    }}
                >
                    <Stack
                        direction="row"
                        spacing={1}
                        sx={{
                            justifyContent: "space-between",
                            alignItems: "center",
                        }}
                    >
                        <Typography
                            sx={{
                                fontWeight: 700,
                                fontSize: "0.92rem",
                                color: "#111111",
                            }}
                        >
                            Card {index + 1}
                        </Typography>
                        <Typography
                            sx={{
                                color: "rgba(17,17,17,0.62)",
                                fontSize: "0.8rem",
                                fontWeight: 500,
                            }}
                        >
                            {APP_LINK}
                        </Typography>
                    </Stack>
                </Box>

                <Stack spacing={1.2} sx={{ p: 1.35 }}>
                    <Typography
                        sx={{
                            fontWeight: 700,
                            fontSize: "1rem",
                            lineHeight: 1.2,
                            minHeight: "2.4em",
                            maxHeight: "2.4em",
                            overflow: "hidden",
                            textOverflow: "clip",
                            whiteSpace: "normal",
                            wordBreak: "normal",
                            overflowWrap: "normal",
                        }}
                    >
                        {cardLabel}
                    </Typography>

                    <Box
                        sx={{
                            aspectRatio: "1 / 1",
                            border: "1.5px solid",
                            borderColor: "var(--line-strong)",
                            bgcolor: "#ffffff",
                            borderRadius: "22px",
                            overflow: "hidden",
                            p: 1.35,
                            display: "grid",
                            placeItems: "center",
                        }}
                    >
                        {card ? (
                            <QrPreview value={card.qr} />
                        ) : (
                            <Typography
                                sx={{
                                    textAlign: "center",
                                    color: "#111111",
                                    opacity: 0.6,
                                    px: 3,
                                    fontSize: "0.95rem",
                                }}
                            >
                                Enter a secret to generate card {index + 1}.
                            </Typography>
                        )}
                    </Box>

                    {card && (
                        <Stack
                            direction="row"
                            spacing={1}
                            sx={{
                                justifyContent: "space-between",
                                alignItems: "center",
                                mt: 0.15,
                            }}
                        >
                            <Button
                                variant="text"
                                size="small"
                                disabled={busy}
                                onClick={() => {
                                    onCopyCardCode(card, index);
                                }}
                                sx={{
                                    minWidth: 0,
                                    px: 0,
                                    py: 0,
                                    color: "var(--muted)",
                                    fontSize: "0.8rem",
                                    fontWeight: 700,
                                    textTransform: "none",
                                    "&:hover": {
                                        bgcolor: "transparent",
                                        color: "var(--ink)",
                                    },
                                }}
                            >
                                {copied ? "Copied" : "Copy code"}
                            </Button>
                            <Typography
                                sx={{
                                    color: "var(--muted)",
                                    fontSize: "0.78rem",
                                    fontWeight: 500,
                                    textAlign: "right",
                                }}
                            >
                                {fingerprint}
                            </Typography>
                        </Stack>
                    )}

                    <Stack
                        direction="row"
                        spacing={0.8}
                        useFlexGap
                        sx={{ flexWrap: "wrap" }}
                    >
                        <ActionButton
                            disabled={!card || busy}
                            onClick={() => {
                                if (!card) return;
                                onCardAction("print", card, index, cardLabel);
                            }}
                        >
                            Print
                        </ActionButton>
                        <ActionButton
                            disabled={!card || busy}
                            onClick={() => {
                                if (!card) return;
                                onCardAction(
                                    "download",
                                    card,
                                    index,
                                    cardLabel,
                                );
                            }}
                        >
                            Download
                        </ActionButton>
                        <ActionButton
                            disabled={!card || busy}
                            onClick={() => {
                                if (!card) return;
                                onCardAction("share", card, index, cardLabel);
                            }}
                        >
                            Share
                        </ActionButton>
                    </Stack>
                </Stack>
            </Stack>
        );
    },
    (previous, next) =>
        previous.busy === next.busy &&
        previous.card?.encoded === next.card?.encoded &&
        previous.cardLabel === next.cardLabel &&
        previous.copied === next.copied &&
        previous.index === next.index,
);

const ActionButton = ({
    children,
    onClick,
    disabled,
}: {
    children: ReactNode;
    disabled?: boolean;
    onClick: () => void;
}) => (
    <Button
        variant="outlined"
        size="small"
        disabled={disabled}
        onClick={onClick}
        sx={{
            minWidth: 0,
            px: 1.35,
            py: 0.75,
            borderRadius: "999px",
            borderWidth: "1.5px",
            borderColor: "var(--line-strong)",
            color: "var(--ink)",
            bgcolor: "transparent",
            "&:hover": {
                borderWidth: "1.5px",
                borderColor: "var(--ink)",
                bgcolor: "var(--button-surface-hover)",
            },
            "&.Mui-disabled": {
                bgcolor: "transparent",
                borderColor: "var(--line)",
                color: "var(--disabled-ink)",
            },
        }}
    >
        {children}
    </Button>
);

const splitIfPossible = (secret: string): SplitSnapshot => {
    if (!secret.trim()) return EMPTY_SPLIT_SNAPSHOT;

    try {
        const rawShares = splitSecret(secret);
        const cards = rawShares.map((share) => {
            const qr = createQrSvgData(share.encoded);
            if (!qr) {
                throw new Error(
                    "This secret is too long for a clean QR. Keep it shorter.",
                );
            }

            return { ...share, qr };
        });

        return {
            cards: cards.map((card) => ({
                ...card,
                fingerprint: shareFingerprint(card.encoded),
            })),
            error: null,
            secret,
        };
    } catch (error) {
        return {
            cards: [],
            error:
                error instanceof Error
                    ? error.message
                    : "Could not split this secret.",
            secret,
        };
    }
};

const describeRecoverSlot = (value: string): RecoverSlotDetails | null => {
    if (!value.trim()) return null;

    try {
        const parsed = parseShare(value);
        return {
            fingerprint: parsed.id.slice(0, 8).toUpperCase(),
            index: parsed.index,
            length: parsed.length,
        };
    } catch {
        return null;
    }
};

const readShareFile = async (file: File) => {
    const canBeText =
        file.type.startsWith("text/") ||
        !file.type ||
        /\.txt$/iu.test(file.name);

    if (canBeText) {
        const text = (await file.text()).trim();
        if (!text) {
            if (file.type.startsWith("text/") || /\.txt$/iu.test(file.name)) {
                throw new Error(
                    "That text file does not look like a 2of3 share.",
                );
            }
        } else {
            try {
                parseShare(text);
                return text;
            } catch {
                if (
                    file.type.startsWith("text/") ||
                    /\.txt$/iu.test(file.name)
                ) {
                    throw new Error(
                        "That text file does not look like a 2of3 share.",
                    );
                }
            }
        }
    }

    return decodeQrFromFile(file);
};

const copyTextToClipboard = async (value: string) => {
    if ("clipboard" in navigator) {
        await navigator.clipboard.writeText(value);
        return;
    }

    throw new Error("Copy is not supported in this browser.");
};

const Page = () => {
    const { systemMode, setMode } = useColorScheme();
    const [secret, setSecret] = useState("");
    const [title, setTitle] = useState("");
    const [defaultTitle, setDefaultTitle] = useState("");
    const [busyCard, setBusyCard] = useState<number | null>(null);
    const [downloadAllBusy, setDownloadAllBusy] = useState(false);
    const [actionError, setActionError] = useState<string | null>(null);
    const [copiedCardIndex, setCopiedCardIndex] = useState<number | null>(null);
    const [recoverSlots, setRecoverSlots] = useState<RecoverSlot[]>([
        { fileName: "", value: "" },
        { fileName: "", value: "" },
    ]);
    const [recoverError, setRecoverError] = useState<string | null>(null);
    const [recoveredSecret, setRecoveredSecret] = useState("");
    const [copiedRecoveredSecret, setCopiedRecoveredSecret] = useState(false);
    const [recoverDropTarget, setRecoverDropTarget] = useState<number | null>(
        null,
    );
    const [splitSnapshot, setSplitSnapshot] =
        useState<SplitSnapshot>(EMPTY_SPLIT_SNAPSHOT);
    const deferredSecret = useDeferredValue(secret);
    const isCardsStaleRef = useRef(false);
    const isDarkMode = systemMode === "dark";

    useEffect(() => {
        setMode("system");
    }, [setMode]);

    const cards = splitSnapshot.cards;
    const isCardsStale = splitSnapshot.secret !== secret;
    const splitError = isCardsStale ? null : splitSnapshot.error;
    const inputStatus = splitError ?? actionError;
    const secretLength = byteLength(secret);
    const cardLabel = title.trim() || defaultTitle || CARD_LABEL_FALLBACK;
    const recoverSlotDetails = recoverSlots.map((slot) =>
        describeRecoverSlot(slot.value),
    );
    const recoverMismatch =
        recoverSlotDetails[0] &&
        recoverSlotDetails[1] &&
        (recoverSlotDetails[0].fingerprint !==
            recoverSlotDetails[1].fingerprint ||
            recoverSlotDetails[0].length !== recoverSlotDetails[1].length);
    const recoverDuplicateCards =
        !recoverMismatch &&
        recoverSlotDetails[0] != null &&
        recoverSlotDetails[0].index === recoverSlotDetails[1]?.index;
    const hasTwoRecoverValues = recoverSlots.every((slot) => slot.value.trim());
    const canRecover =
        hasTwoRecoverValues && !recoverMismatch && !recoverDuplicateCards;
    const recoverStatus = recoverMismatch
        ? "These two cards are from different sets. Match the ID on both cards."
        : recoverDuplicateCards
          ? "Use two different cards from the same set."
          : recoverError;

    isCardsStaleRef.current = isCardsStale;

    useEffect(() => {
        if (!secret.trim()) {
            startTransition(() => {
                setSplitSnapshot(EMPTY_SPLIT_SNAPSHOT);
            });
        }
    }, [secret]);

    useEffect(() => {
        const nextDefaultTitle = todayLabel();
        setDefaultTitle(nextDefaultTitle);
        setTitle((current) => current || nextDefaultTitle);
    }, []);

    useEffect(() => {
        if (!deferredSecret.trim()) return;
        startTransition(() => {
            setSplitSnapshot(splitIfPossible(deferredSecret));
        });
    }, [deferredSecret]);

    useEffect(() => {
        setRecoveredSecret("");
        setRecoverError(null);
    }, [recoverSlots]);

    useEffect(() => {
        setActionError(null);
        setCopiedCardIndex(null);
    }, [secret]);

    useEffect(() => {
        if (copiedCardIndex === null) return;
        const timer = window.setTimeout(() => {
            setCopiedCardIndex(null);
        }, 1600);
        return () => window.clearTimeout(timer);
    }, [copiedCardIndex]);

    useEffect(() => {
        if (!copiedRecoveredSecret) return;
        const timer = window.setTimeout(() => {
            setCopiedRecoveredSecret(false);
        }, 1600);
        return () => window.clearTimeout(timer);
    }, [copiedRecoveredSecret]);

    const makeCardFile = useCallback(
        async (card: ShareCardState, label: string) => {
            const canvas = await renderShareCard({
                qrModules: card.qr.modules,
                qrSize: card.qr.viewBoxSize,
                shareIndex: card.index,
                shareText: card.encoded,
                title: label,
            });
            const blob = await canvasToBlob(canvas);
            const filename = `${sanitizeFilename(label)}-set-${card.fingerprint.toLowerCase()}-card-${card.index}.png`;
            return new File([blob], filename, { type: "image/png" });
        },
        [],
    );

    const makeCardFilename = useCallback(
        (card: ShareCardState, label: string) =>
            `${sanitizeFilename(label)}-set-${card.fingerprint.toLowerCase()}-card-${card.index}.png`,
        [],
    );

    const onCardAction = useCallback(
        async (
            kind: "download" | "print" | "share",
            card: ShareCardState,
            displayIndex: number,
            label: string,
        ) => {
            if (isCardsStaleRef.current) return;
            setActionError(null);
            setBusyCard(displayIndex);
            let printPopup: Window | null = null;

            try {
                if (kind === "print") {
                    printPopup = preparePrintWindow(
                        makeCardFilename(card, label),
                    );
                }
                const file = await makeCardFile(card, label);
                if (kind === "print") {
                    await printBlob(file, file.name, printPopup ?? undefined);
                } else if (kind === "download") {
                    downloadBlob(file, file.name);
                } else {
                    try {
                        await shareFiles([file]);
                    } catch (error) {
                        if (
                            (error instanceof DOMException &&
                                error.name === "AbortError") ||
                            (error instanceof Error &&
                                /abort/i.test(error.message))
                        ) {
                            return;
                        }
                        downloadBlob(file, file.name);
                    }
                }
            } catch (error) {
                setActionError(
                    error instanceof Error
                        ? error.message
                        : "That action failed.",
                );
                if (printPopup && !printPopup.closed) {
                    printPopup.close();
                }
            } finally {
                setBusyCard(null);
            }
        },
        [makeCardFile, makeCardFilename],
    );

    const onDownloadAll = async () => {
        if (isCardsStaleRef.current || cards.length !== 3) return;
        setActionError(null);
        setDownloadAllBusy(true);

        try {
            for (const card of cards) {
                const file = await makeCardFile(card, cardLabel);
                downloadBlob(file, file.name);
            }

            const recovery = await offlineRecoveryFile();
            downloadBlob(recovery, recovery.name);
        } catch (error) {
            setActionError(
                error instanceof Error
                    ? error.message
                    : "Could not download the kit.",
            );
        } finally {
            setDownloadAllBusy(false);
        }
    };

    const onRecover = () => {
        setRecoveredSecret("");
        setRecoverError(null);
        setCopiedRecoveredSecret(false);

        if (!hasTwoRecoverValues) {
            setRecoverError("Upload or paste two cards first.");
            return;
        }

        if (recoverMismatch) {
            setRecoverError(
                "These two cards are from different sets. Match the ID on both cards.",
            );
            return;
        }

        if (recoverDuplicateCards) {
            setRecoverError("Use two different cards from the same set.");
            return;
        }

        try {
            const result = combineShares(
                recoverSlots[0]!.value,
                recoverSlots[1]!.value,
            );
            setRecoveredSecret(result);
        } catch (error) {
            setRecoverError(
                error instanceof Error
                    ? error.message
                    : "Could not recover secret.",
            );
        }
    };

    const onCopyCardCode = useCallback(
        async (card: ShareCardState, displayIndex: number) => {
            if (isCardsStaleRef.current) return;
            setActionError(null);

            try {
                await copyTextToClipboard(card.encoded);
                setCopiedCardIndex(displayIndex);
            } catch (error) {
                setActionError(
                    error instanceof Error
                        ? error.message
                        : "Could not copy that code.",
                );
            }
        },
        [],
    );

    const onRecoverFile = async (slotIndex: number, file: File) => {
        try {
            const value = await readShareFile(file);
            parseShare(value);
            setRecoverSlots((previous) =>
                previous.map((slot, index) =>
                    index === slotIndex ? { fileName: file.name, value } : slot,
                ),
            );
            setRecoverError(null);
        } catch (error) {
            setRecoverError(
                error instanceof Error
                    ? error.message
                    : "Could not read that share.",
            );
        } finally {
            setRecoverDropTarget((current) =>
                current === slotIndex ? null : current,
            );
        }
    };

    const onRecoverFileChange = async (
        slotIndex: number,
        event: ChangeEvent<HTMLInputElement>,
    ) => {
        const file = event.target.files?.[0];
        if (!file) return;

        try {
            await onRecoverFile(slotIndex, file);
        } finally {
            event.target.value = "";
        }
    };

    const onRecoverDrop = async (
        slotIndex: number,
        event: DragEvent<HTMLDivElement>,
    ) => {
        event.preventDefault();
        setRecoverDropTarget(null);

        const file = event.dataTransfer.files[0];
        if (!file) return;

        await onRecoverFile(slotIndex, file);
    };

    return (
        <>
            <Head>
                <meta
                    name="description"
                    content="Turn one important secret into 3 recovery cards you can keep in different places. Any 2 cards bring it back."
                />
                <meta property="og:title" content="2of3 by Ente" />
                <meta
                    property="og:description"
                    content="Turn one important secret into 3 recovery cards you can keep in different places. Any 2 cards bring it back."
                />
            </Head>

            <Box
                sx={{
                    "--app-bg": isDarkMode ? "#0b0b0b" : "#ffffff",
                    "--shell": isDarkMode ? "#101010" : "#ffffff",
                    "--paper": isDarkMode ? "#181818" : "#ffffff",
                    "--edge": isDarkMode ? "rgba(255,255,255,0.7)" : "#111111",
                    "--accent-edge": "#111111",
                    "--field": isDarkMode
                        ? "rgba(252,239,93,0.12)"
                        : "rgba(252,239,93,0.18)",
                    "--field-soft": isDarkMode
                        ? "rgba(252,239,93,0.08)"
                        : "rgba(252,239,93,0.12)",
                    "--ink": isDarkMode ? "#fafafa" : "#111111",
                    "--muted": isDarkMode
                        ? "rgba(250,250,250,0.72)"
                        : "rgba(17,17,17,0.68)",
                    "--line": isDarkMode
                        ? "rgba(255,255,255,0.16)"
                        : "rgba(17,17,17,0.18)",
                    "--line-strong": isDarkMode
                        ? "rgba(255,255,255,0.28)"
                        : "rgba(17,17,17,0.22)",
                    "--soft-card-bg": isDarkMode
                        ? "rgba(252,239,93,0.045)"
                        : "rgba(252,239,93,0.12)",
                    "--button-surface": isDarkMode
                        ? "rgba(255,255,255,0.04)"
                        : "rgba(255,255,255,0.88)",
                    "--button-surface-hover": isDarkMode
                        ? "rgba(255,255,255,0.08)"
                        : "#ffffff",
                    "--chip-bg": isDarkMode
                        ? "rgba(255,255,255,0.06)"
                        : "rgba(255,255,255,0.72)",
                    "--chip-accent-bg": isDarkMode
                        ? "rgba(255,255,255,0.2)"
                        : "rgba(255,255,255,0.62)",
                    "--disabled-ink": isDarkMode
                        ? "rgba(250,250,250,0.28)"
                        : "rgba(17,17,17,0.28)",
                    "--shadow-shell": isDarkMode
                        ? "0 18px 42px rgba(0,0,0,0.38)"
                        : "0 22px 48px rgba(17,17,17,0.06)",
                    "--shadow-card": isDarkMode
                        ? "0 12px 28px rgba(0,0,0,0.24)"
                        : "0 14px 28px rgba(17,17,17,0.06)",
                    "--shadow-accent": isDarkMode
                        ? "0 14px 32px rgba(0,0,0,0.26)"
                        : "0 14px 28px rgba(17,17,17,0.05)",
                    "--accent": "rgb(252, 239, 93)",
                    minHeight: "100vh",
                    bgcolor: "var(--app-bg)",
                    color: "var(--ink)",
                    backgroundImage: "none",
                }}
            >
                <Container maxWidth="xl" sx={{ py: { xs: 2, md: 3 } }}>
                    <Stack spacing={3}>
                        <Stack
                            direction="row"
                            sx={{
                                justifyContent: "space-between",
                                alignItems: "center",
                                px: { xs: 0.5, md: 1 },
                            }}
                        >
                            <Typography
                                sx={{
                                    fontWeight: 700,
                                    letterSpacing: "-0.07em",
                                    fontSize: { xs: "1.7rem", md: "2rem" },
                                }}
                            >
                                2of3
                            </Typography>
                            <Box
                                sx={{
                                    fontSize: { xs: "0.85rem", md: "0.95rem" },
                                    color: "var(--muted)",
                                    display: "flex",
                                    alignItems: "center",
                                    gap: 0.4,
                                }}
                            >
                                <Box component="span">by</Box>
                                <Box
                                    component="a"
                                    href="https://ente.com"
                                    target="_blank"
                                    rel="noopener"
                                    sx={{
                                        color: "var(--ink)",
                                        fontWeight: 700,
                                        textDecoration: "none",
                                        "&:hover": {
                                            textDecoration: "underline",
                                        },
                                    }}
                                >
                                    Ente
                                </Box>
                            </Box>
                        </Stack>

                        <Box
                            sx={{
                                border: "2px solid",
                                borderColor: "var(--edge)",
                                borderRadius: "32px",
                                overflow: "hidden",
                                bgcolor: "var(--shell)",
                                boxShadow: "var(--shadow-shell)",
                                display: "grid",
                                gridTemplateColumns: {
                                    xs: "1fr",
                                    lg: "minmax(320px, 430px) minmax(0, 1fr)",
                                },
                                minHeight: { lg: "calc(100svh - 112px)" },
                            }}
                        >
                            <Stack
                                spacing={2.2}
                                sx={{
                                    p: { xs: 2.25, md: 3 },
                                    bgcolor: "var(--paper)",
                                    borderRight: {
                                        xs: "none",
                                        lg: "2px solid",
                                    },
                                    borderBottom: {
                                        xs: "2px solid",
                                        lg: "none",
                                    },
                                    borderColor: "var(--edge)",
                                }}
                            >
                                <Box
                                    sx={{
                                        width: "fit-content",
                                        px: 1.35,
                                        py: 0.7,
                                        borderRadius: "999px",
                                        border: "1.5px solid",
                                        borderColor: "var(--accent-edge)",
                                        bgcolor: "var(--accent)",
                                    }}
                                >
                                    <Typography
                                        sx={{
                                            fontSize: "0.86rem",
                                            fontWeight: 700,
                                            color: "#111111",
                                        }}
                                    >
                                        Any 2 cards recover it
                                    </Typography>
                                </Box>

                                <Typography
                                    variant="h1"
                                    sx={{
                                        fontSize: {
                                            xs: "2.65rem",
                                            md: "3.45rem",
                                        },
                                        lineHeight: 0.9,
                                        maxWidth: 360,
                                    }}
                                >
                                    Enter a secret.
                                    <br />
                                    Get 3 cards.
                                </Typography>

                                <Typography
                                    sx={{
                                        color: "var(--muted)",
                                        maxWidth: 360,
                                        fontSize: "0.98rem",
                                    }}
                                >
                                    Turn a recovery key, password, or other
                                    secret into 3 cards you can keep in
                                    different places.
                                </Typography>

                                <Typography
                                    sx={{
                                        color: "var(--muted)",
                                        maxWidth: 360,
                                        fontSize: "0.98rem",
                                    }}
                                >
                                    Your secret never leaves your browser.
                                </Typography>

                                <TextField
                                    label="Secret"
                                    multiline
                                    minRows={7}
                                    maxRows={12}
                                    value={secret}
                                    onChange={(event) =>
                                        setSecret(
                                            trimToByteLength(
                                                event.target.value,
                                                MAX_SECRET_BYTES_FOR_PRINTED_CARD,
                                            ),
                                        )
                                    }
                                    sx={fieldSx}
                                />

                                <Stack spacing={0.8}>
                                    <TextField
                                        label="Card label (optional)"
                                        value={title}
                                        placeholder={
                                            defaultTitle || CARD_LABEL_FALLBACK
                                        }
                                        onChange={(event) =>
                                            setTitle(
                                                trimToCharacterLength(
                                                    event.target.value,
                                                    MAX_CARD_TITLE_LENGTH,
                                                ),
                                            )
                                        }
                                        slotProps={{
                                            htmlInput: {
                                                maxLength:
                                                    MAX_CARD_TITLE_LENGTH,
                                            },
                                        }}
                                        sx={fieldSx}
                                    />
                                    <Typography
                                        sx={{
                                            color: "var(--muted)",
                                            fontSize: "0.88rem",
                                            textAlign: "right",
                                        }}
                                    >
                                        {secretLength}/
                                        {MAX_SECRET_BYTES_FOR_PRINTED_CARD}
                                    </Typography>
                                </Stack>

                                <Stack
                                    spacing={1.1}
                                    sx={{ alignItems: "flex-start" }}
                                >
                                    <Button
                                        variant="contained"
                                        size="large"
                                        disabled={
                                            cards.length !== 3 ||
                                            !!splitSnapshot.error ||
                                            downloadAllBusy
                                        }
                                        onClick={() => {
                                            void onDownloadAll();
                                        }}
                                        sx={{
                                            px: 2.6,
                                            py: 1.25,
                                            borderRadius: "999px",
                                            border: "1.5px solid",
                                            borderColor: "var(--accent-edge)",
                                            bgcolor: "var(--accent)",
                                            color: "#111111",
                                            boxShadow: "none",
                                            "&:hover": {
                                                boxShadow: "none",
                                                borderColor:
                                                    "var(--accent-edge)",
                                                bgcolor: "var(--accent)",
                                            },
                                            "&.Mui-disabled": {
                                                bgcolor: "transparent",
                                                color: "var(--muted)",
                                                borderColor:
                                                    "var(--line-strong)",
                                            },
                                        }}
                                    >
                                        {downloadAllBusy
                                            ? "Preparing downloads..."
                                            : "Download all cards"}
                                    </Button>
                                    <Typography
                                        sx={{
                                            color: "var(--muted)",
                                            fontSize: "0.9rem",
                                        }}
                                    >
                                        Includes an offline recovery page.
                                    </Typography>
                                </Stack>

                                {inputStatus && (
                                    <Note tone="accent">{inputStatus}</Note>
                                )}
                            </Stack>

                            <Stack
                                spacing={2}
                                sx={{ p: { xs: 1.75, md: 2.25 } }}
                            >
                                <Stack
                                    spacing={0.65}
                                    sx={{ px: { xs: 0.3, md: 0.6 } }}
                                >
                                    <Typography
                                        sx={{
                                            fontWeight: 700,
                                            fontSize: "1.05rem",
                                        }}
                                    >
                                        3 recovery cards
                                    </Typography>
                                    <Typography
                                        sx={{
                                            color: "var(--muted)",
                                            fontSize: "0.93rem",
                                        }}
                                    >
                                        Each card is harmless on its own. Print,
                                        save, or share them separately.
                                    </Typography>
                                </Stack>

                                <Box
                                    sx={{
                                        display: "grid",
                                        gridTemplateColumns: {
                                            xs: "1fr",
                                            md: "repeat(2, minmax(0, 1fr))",
                                        },
                                        gap: 1.5,
                                        alignContent: "start",
                                    }}
                                >
                                    {Array.from({ length: 3 }, (_, index) => {
                                        const card = cards[index];

                                        return (
                                            <ShareCardPanel
                                                key={index}
                                                busy={busyCard === index}
                                                card={card}
                                                cardLabel={cardLabel}
                                                copied={
                                                    copiedCardIndex === index
                                                }
                                                index={index}
                                                onCardAction={onCardAction}
                                                onCopyCardCode={onCopyCardCode}
                                            />
                                        );
                                    })}
                                </Box>
                            </Stack>
                        </Box>

                        <Box
                            sx={{
                                display: "flex",
                                justifyContent: "center",
                                py: { xs: 0.35, md: 0.8 },
                            }}
                        >
                            <Stack
                                spacing={0.75}
                                sx={{
                                    alignItems: "center",
                                    minHeight: { xs: 54, md: 72 },
                                }}
                            >
                                <Box
                                    sx={{
                                        width: 11,
                                        height: 11,
                                        borderRadius: "50%",
                                        bgcolor: "var(--accent)",
                                        ...(isDarkMode
                                            ? {
                                                  boxShadow:
                                                      "0 0 0 2px var(--app-bg), 0 0 0 1px rgba(255,255,255,0.18)",
                                              }
                                            : {
                                                  border: "1.5px solid",
                                                  borderColor:
                                                      "var(--accent-edge)",
                                              }),
                                    }}
                                />
                                <Box
                                    sx={{
                                        width: isDarkMode ? "1px" : "1.5px",
                                        flex: 1,
                                        minHeight: { xs: 28, md: 44 },
                                        bgcolor: isDarkMode
                                            ? "var(--line)"
                                            : "var(--line-strong)",
                                    }}
                                />
                                <Box
                                    sx={{
                                        width: 11,
                                        height: 11,
                                        borderRadius: "50%",
                                        bgcolor: "var(--accent)",
                                        ...(isDarkMode
                                            ? {
                                                  boxShadow:
                                                      "0 0 0 2px var(--app-bg), 0 0 0 1px rgba(255,255,255,0.18)",
                                              }
                                            : {
                                                  border: "1.5px solid",
                                                  borderColor:
                                                      "var(--accent-edge)",
                                              }),
                                    }}
                                />
                            </Stack>
                        </Box>

                        <Box
                            sx={{
                                border: "2px solid",
                                borderColor: "var(--edge)",
                                borderRadius: "28px",
                                overflow: "hidden",
                                bgcolor: "var(--shell)",
                                boxShadow: "var(--shadow-card)",
                            }}
                        >
                            <Stack
                                spacing={2.25}
                                sx={{ p: { xs: 2.1, md: 2.6 } }}
                            >
                                <Box
                                    sx={{
                                        width: "fit-content",
                                        px: 1.1,
                                        py: 0.45,
                                        borderRadius: "999px",
                                        bgcolor: "var(--paper)",
                                        border: "1.5px solid",
                                        borderColor: "var(--line-strong)",
                                    }}
                                >
                                    <Typography
                                        sx={{
                                            fontWeight: 700,
                                            fontSize: "0.82rem",
                                        }}
                                    >
                                        Recover
                                    </Typography>
                                </Box>

                                <Box>
                                    <Typography
                                        variant="h2"
                                        sx={{
                                            fontSize: {
                                                xs: "2rem",
                                                md: "2.55rem",
                                            },
                                            lineHeight: 0.92,
                                        }}
                                    >
                                        Use any 2 cards to recover
                                    </Typography>
                                    <Typography
                                        sx={{
                                            color: "var(--muted)",
                                            mt: 1,
                                            maxWidth: 680,
                                        }}
                                    >
                                        Upload two card images, or paste their
                                        codes.
                                    </Typography>
                                </Box>

                                <Box
                                    sx={{
                                        display: "grid",
                                        gridTemplateColumns: {
                                            xs: "1fr",
                                            md: "repeat(2, minmax(0, 1fr))",
                                        },
                                        gap: 1.5,
                                    }}
                                >
                                    {recoverSlots.map((slot, index) => {
                                        const slotDetails =
                                            recoverSlotDetails[index];
                                        const slotLabel =
                                            recoverSlotLabel(index);
                                        const isDropActive =
                                            recoverDropTarget === index;

                                        return (
                                            <Stack
                                                key={index}
                                                spacing={1.15}
                                                onDragEnter={(event) => {
                                                    event.preventDefault();
                                                    setRecoverDropTarget(index);
                                                }}
                                                onDragLeave={() => {
                                                    setRecoverDropTarget(
                                                        (current) =>
                                                            current === index
                                                                ? null
                                                                : current,
                                                    );
                                                }}
                                                onDragOver={(event) => {
                                                    event.preventDefault();
                                                    event.dataTransfer.dropEffect =
                                                        "copy";
                                                    setRecoverDropTarget(index);
                                                }}
                                                onDrop={(event) => {
                                                    void onRecoverDrop(
                                                        index,
                                                        event,
                                                    );
                                                }}
                                                sx={{
                                                    p: 1.45,
                                                    border: "1.5px solid",
                                                    borderColor: isDropActive
                                                        ? "var(--ink)"
                                                        : "var(--line-strong)",
                                                    borderRadius: "24px",
                                                    bgcolor: isDropActive
                                                        ? "var(--field-soft)"
                                                        : "var(--paper)",
                                                    transition:
                                                        "border-color 140ms ease, background-color 140ms ease, transform 140ms ease",
                                                    transform: isDropActive
                                                        ? "translateY(-1px)"
                                                        : "translateY(0)",
                                                }}
                                            >
                                                <Stack
                                                    direction="row"
                                                    spacing={1}
                                                    sx={{
                                                        justifyContent:
                                                            "space-between",
                                                        alignItems: "center",
                                                    }}
                                                >
                                                    <Box
                                                        sx={{
                                                            width: "fit-content",
                                                            px: 1,
                                                            py: 0.42,
                                                            borderRadius:
                                                                "999px",
                                                            border: "1.5px solid",
                                                            borderColor:
                                                                "var(--line-strong)",
                                                        }}
                                                    >
                                                        <Typography
                                                            sx={{
                                                                fontWeight: 700,
                                                                fontSize:
                                                                    "0.84rem",
                                                            }}
                                                        >
                                                            Card {slotLabel}
                                                        </Typography>
                                                    </Box>
                                                    <Button
                                                        variant="outlined"
                                                        component="label"
                                                        size="small"
                                                        sx={{
                                                            alignSelf:
                                                                "flex-start",
                                                            borderWidth:
                                                                "1.5px",
                                                            borderColor:
                                                                "var(--line-strong)",
                                                            color: "var(--ink)",
                                                            bgcolor:
                                                                "var(--paper)",
                                                            "&:hover": {
                                                                borderWidth:
                                                                    "1.5px",
                                                                borderColor:
                                                                    "var(--ink)",
                                                            },
                                                        }}
                                                    >
                                                        {slot.fileName
                                                            ? "Replace image"
                                                            : "Upload image"}
                                                        <input
                                                            hidden
                                                            type="file"
                                                            accept="image/*,text/plain"
                                                            onChange={(
                                                                event,
                                                            ) => {
                                                                void onRecoverFileChange(
                                                                    index,
                                                                    event,
                                                                );
                                                            }}
                                                        />
                                                    </Button>
                                                </Stack>

                                                <Typography
                                                    sx={{
                                                        color:
                                                            slot.fileName ||
                                                            slotDetails
                                                                ? "var(--ink)"
                                                                : "var(--muted)",
                                                        fontSize: "0.88rem",
                                                    }}
                                                >
                                                    {slotDetails
                                                        ? `${slot.fileName ? `${slot.fileName} - ` : ""}Card ${slotDetails.index} from ID ${slotDetails.fingerprint}`
                                                        : slot.fileName
                                                          ? slot.fileName
                                                          : "Drop a saved card image here, or paste a copied code."}
                                                </Typography>
                                                <TextField
                                                    label={`Code ${slotLabel}`}
                                                    multiline
                                                    minRows={6}
                                                    value={slot.value}
                                                    onChange={(event) =>
                                                        setRecoverSlots(
                                                            (previous) =>
                                                                previous.map(
                                                                    (
                                                                        current,
                                                                        currentIndex,
                                                                    ) =>
                                                                        currentIndex ===
                                                                        index
                                                                            ? {
                                                                                  ...current,
                                                                                  fileName:
                                                                                      "",
                                                                                  value: event
                                                                                      .target
                                                                                      .value,
                                                                              }
                                                                            : current,
                                                                ),
                                                        )
                                                    }
                                                    placeholder={`Paste code ${slotLabel}`}
                                                    sx={fieldSx}
                                                />
                                            </Stack>
                                        );
                                    })}
                                </Box>

                                {recoverStatus && (
                                    <Note tone="accent">{recoverStatus}</Note>
                                )}

                                <Stack
                                    direction={{ xs: "column", sm: "row" }}
                                    spacing={1.25}
                                    sx={{
                                        alignItems: {
                                            xs: "stretch",
                                            sm: "flex-start",
                                        },
                                    }}
                                >
                                    <Button
                                        variant="outlined"
                                        size="large"
                                        onClick={onRecover}
                                        disabled={!canRecover}
                                        sx={{
                                            alignSelf: "flex-start",
                                            px: 2.3,
                                            py: 1.15,
                                            borderRadius: "999px",
                                            borderWidth: "1.5px",
                                            borderColor: "var(--accent-edge)",
                                            color: "#111111",
                                            bgcolor: "var(--accent)",
                                            "&:hover": {
                                                borderWidth: "1.5px",
                                                borderColor:
                                                    "var(--accent-edge)",
                                                bgcolor: "var(--accent)",
                                            },
                                            "&.Mui-disabled": {
                                                bgcolor: "transparent",
                                                color: "var(--muted)",
                                                borderColor:
                                                    "var(--line-strong)",
                                            },
                                        }}
                                    >
                                        Recover secret
                                    </Button>
                                </Stack>

                                {recoveredSecret && (
                                    <Stack
                                        spacing={1.2}
                                        sx={{
                                            p: 1.45,
                                            border: "1.5px solid",
                                            borderColor: "var(--edge)",
                                            borderRadius: "24px",
                                            bgcolor: "var(--paper)",
                                        }}
                                    >
                                        <Stack
                                            direction={{
                                                xs: "column",
                                                sm: "row",
                                            }}
                                            spacing={1}
                                            sx={{
                                                justifyContent: "space-between",
                                                alignItems: {
                                                    xs: "flex-start",
                                                    sm: "center",
                                                },
                                            }}
                                        >
                                            <Typography
                                                sx={{
                                                    fontWeight: 700,
                                                    fontSize: "1rem",
                                                }}
                                            >
                                                Recovered secret
                                            </Typography>
                                            <Button
                                                variant="outlined"
                                                size="small"
                                                onClick={() => {
                                                    void copyTextToClipboard(
                                                        recoveredSecret,
                                                    )
                                                        .then(() => {
                                                            setCopiedRecoveredSecret(
                                                                true,
                                                            );
                                                        })
                                                        .catch(
                                                            (
                                                                error: unknown,
                                                            ) => {
                                                                setRecoverError(
                                                                    error instanceof
                                                                        Error
                                                                        ? error.message
                                                                        : "Could not copy the recovered secret.",
                                                                );
                                                            },
                                                        );
                                                }}
                                                sx={{
                                                    borderWidth: "1.5px",
                                                    borderColor:
                                                        "var(--accent-edge)",
                                                    color: "#111111",
                                                    bgcolor: "var(--accent)",
                                                    "&:hover": {
                                                        borderWidth: "1.5px",
                                                        borderColor:
                                                            "var(--accent-edge)",
                                                        bgcolor:
                                                            "var(--accent)",
                                                    },
                                                }}
                                            >
                                                {copiedRecoveredSecret
                                                    ? "Copied"
                                                    : "Copy"}
                                            </Button>
                                        </Stack>

                                        <TextField
                                            multiline
                                            minRows={4}
                                            value={recoveredSecret}
                                            slotProps={{
                                                input: { readOnly: true },
                                            }}
                                            sx={fieldSx}
                                        />
                                    </Stack>
                                )}
                            </Stack>
                        </Box>

                        <Box
                            sx={{
                                pt: { xs: 5.2, md: 8.3 },
                                pb: { xs: 2.8, md: 4.7 },
                            }}
                        >
                            <Box
                                sx={{
                                    width: "auto",
                                    ml: "calc(50% - 50vw)",
                                    mr: "calc(50% - 50vw)",
                                    height: "1.5px",
                                    bgcolor: "var(--line-strong)",
                                }}
                            />
                        </Box>

                        <Box
                            sx={{
                                px: { xs: 0.4, md: 1 },
                                pt: { xs: 2.8, md: 4.7 },
                                pb: { xs: 1.5, md: 2.5 },
                                position: "relative",
                                "&::before": {
                                    content: '""',
                                    position: "absolute",
                                    inset: {
                                        xs: "18px auto auto 6%",
                                        md: "22px auto auto 12%",
                                    },
                                    width: { xs: 180, md: 240 },
                                    height: { xs: 180, md: 240 },
                                    borderRadius: "50%",
                                    background: isDarkMode
                                        ? "radial-gradient(circle, rgba(252,239,93,0.08) 0%, rgba(252,239,93,0.03) 34%, rgba(252,239,93,0) 72%)"
                                        : "radial-gradient(circle, rgba(252,239,93,0.14) 0%, rgba(252,239,93,0.05) 36%, rgba(252,239,93,0) 72%)",
                                    pointerEvents: "none",
                                    filter: "blur(8px)",
                                },
                            }}
                        >
                            <Stack
                                spacing={3.8}
                                sx={{
                                    width: "min(100%, 980px)",
                                    mx: "auto",
                                    position: "relative",
                                }}
                            >
                                <Stack spacing={0.9} sx={{ maxWidth: 680 }}>
                                    <Stack
                                        direction="row"
                                        spacing={0.8}
                                        sx={{ alignItems: "center" }}
                                    >
                                        <Box
                                            sx={{
                                                width: "fit-content",
                                                px: 1.05,
                                                py: 0.42,
                                                borderRadius: "999px",
                                                border: "1.5px solid",
                                                borderColor:
                                                    "var(--accent-edge)",
                                                bgcolor: "var(--accent)",
                                            }}
                                        >
                                            <Typography
                                                sx={{
                                                    fontSize: "0.8rem",
                                                    fontWeight: 700,
                                                    color: "#111111",
                                                    letterSpacing: "0.06em",
                                                    textTransform: "uppercase",
                                                }}
                                            >
                                                Help
                                            </Typography>
                                        </Box>
                                        <Typography
                                            sx={{
                                                color: "var(--muted)",
                                                fontSize: "0.82rem",
                                                fontWeight: 700,
                                                textTransform: "uppercase",
                                                letterSpacing: "0.08em",
                                            }}
                                        >
                                            Why & What
                                        </Typography>
                                    </Stack>
                                </Stack>

                                <Box
                                    sx={{
                                        display: "grid",
                                        gridTemplateColumns: {
                                            xs: "1fr",
                                            md: "repeat(12, minmax(0, 1fr))",
                                        },
                                        gap: 1.35,
                                        alignItems: "start",
                                    }}
                                >
                                    <Stack
                                        spacing={0.65}
                                        sx={{
                                            gridColumn: {
                                                xs: "span 1",
                                                md: "span 12",
                                            },
                                            pt: { xs: 1, md: 1.6 },
                                            pb: { xs: 1.7, md: 2.5 },
                                        }}
                                    >
                                        <Typography
                                            variant="h2"
                                            sx={{
                                                fontSize: {
                                                    xs: "1.95rem",
                                                    md: "2.35rem",
                                                },
                                                lineHeight: 0.96,
                                                maxWidth: 620,
                                            }}
                                        >
                                            Use cases
                                        </Typography>
                                    </Stack>
                                    {HELP_USE_CASES.map((item) => {
                                        const isAccent = item.tone === "accent";
                                        const isSoft = item.tone === "soft";

                                        return (
                                            <Stack
                                                key={item.title}
                                                spacing={1}
                                                sx={{
                                                    gridColumn: {
                                                        xs: "span 1",
                                                        md: `span ${item.span}`,
                                                    },
                                                    p: { xs: 1.6, md: 1.9 },
                                                    border: "1.5px solid",
                                                    borderColor: isAccent
                                                        ? "var(--accent-edge)"
                                                        : "var(--line-strong)",
                                                    borderRadius: "28px",
                                                    bgcolor: isAccent
                                                        ? "var(--accent)"
                                                        : isSoft
                                                          ? "var(--soft-card-bg)"
                                                          : "var(--paper)",
                                                    boxShadow: isAccent
                                                        ? "var(--shadow-accent)"
                                                        : "none",
                                                }}
                                            >
                                                <Box
                                                    sx={{
                                                        width: "fit-content",
                                                        px: 0.82,
                                                        py: 0.34,
                                                        borderRadius: "999px",
                                                        border: "1.5px solid",
                                                        borderColor: isAccent
                                                            ? "rgba(17,17,17,0.2)"
                                                            : "var(--line-strong)",
                                                        bgcolor: isAccent
                                                            ? "var(--chip-accent-bg)"
                                                            : "var(--chip-bg)",
                                                    }}
                                                >
                                                    <Typography
                                                        sx={{
                                                            fontSize: "0.75rem",
                                                            fontWeight: 700,
                                                            color: isAccent
                                                                ? "#111111"
                                                                : "var(--ink)",
                                                            letterSpacing:
                                                                "0.04em",
                                                            textTransform:
                                                                "uppercase",
                                                        }}
                                                    >
                                                        Scenario
                                                    </Typography>
                                                </Box>
                                                <Typography
                                                    sx={{
                                                        fontWeight: 700,
                                                        fontSize: {
                                                            xs: "1.1rem",
                                                            md: "1.18rem",
                                                        },
                                                        lineHeight: 1.25,
                                                        color: isAccent
                                                            ? "#111111"
                                                            : "var(--ink)",
                                                        maxWidth: 520,
                                                    }}
                                                >
                                                    {item.title}
                                                </Typography>
                                                <Typography
                                                    sx={{
                                                        color: isAccent
                                                            ? "rgba(17,17,17,0.76)"
                                                            : "var(--muted)",
                                                        fontSize: "0.98rem",
                                                        lineHeight: 1.7,
                                                        maxWidth: 760,
                                                    }}
                                                >
                                                    {item.detail}
                                                </Typography>
                                            </Stack>
                                        );
                                    })}
                                    <Stack
                                        spacing={0.65}
                                        sx={{
                                            gridColumn: {
                                                xs: "span 1",
                                                md: "span 12",
                                            },
                                            pt: { xs: 4.2, md: 7.2 },
                                            pb: { xs: 1.7, md: 2.5 },
                                        }}
                                    >
                                        <Typography
                                            variant="h2"
                                            sx={{
                                                fontSize: {
                                                    xs: "1.95rem",
                                                    md: "2.35rem",
                                                },
                                                lineHeight: 0.96,
                                                maxWidth: 620,
                                            }}
                                        >
                                            FAQ
                                        </Typography>
                                    </Stack>
                                    {HELP_FAQS.map((item, index) => {
                                        const layout =
                                            HELP_CARD_LAYOUTS[index]!;
                                        const isAccent =
                                            layout.tone === "accent";
                                        const isSoft = layout.tone === "soft";

                                        return (
                                            <Stack
                                                key={item.question}
                                                spacing={0.95}
                                                sx={{
                                                    gridColumn: {
                                                        xs: "span 1",
                                                        md: `span ${layout.span}`,
                                                    },
                                                    mt: {
                                                        xs: 0,
                                                        md: layout.offset,
                                                    },
                                                    p: { xs: 1.45, md: 1.7 },
                                                    border: "1.5px solid",
                                                    borderColor: isAccent
                                                        ? "var(--accent-edge)"
                                                        : "var(--line-strong)",
                                                    borderRadius: "26px",
                                                    bgcolor: isAccent
                                                        ? "var(--accent)"
                                                        : isSoft
                                                          ? "var(--soft-card-bg)"
                                                          : "var(--paper)",
                                                    boxShadow: isAccent
                                                        ? "var(--shadow-accent)"
                                                        : "none",
                                                }}
                                            >
                                                <Stack
                                                    direction="row"
                                                    spacing={1}
                                                    sx={{
                                                        justifyContent:
                                                            "space-between",
                                                        alignItems: "center",
                                                    }}
                                                >
                                                    <Box
                                                        sx={{
                                                            width: "fit-content",
                                                            px: 0.8,
                                                            py: 0.32,
                                                            borderRadius:
                                                                "999px",
                                                            border: "1.5px solid",
                                                            borderColor:
                                                                isAccent
                                                                    ? "rgba(17,17,17,0.2)"
                                                                    : "var(--line-strong)",
                                                            bgcolor: isAccent
                                                                ? "var(--chip-accent-bg)"
                                                                : "var(--chip-bg)",
                                                        }}
                                                    >
                                                        <Typography
                                                            sx={{
                                                                fontSize:
                                                                    "0.75rem",
                                                                fontWeight: 700,
                                                                color: isAccent
                                                                    ? "#111111"
                                                                    : "var(--ink)",
                                                                letterSpacing:
                                                                    "0.04em",
                                                                textTransform:
                                                                    "uppercase",
                                                            }}
                                                        >
                                                            Q&A
                                                        </Typography>
                                                    </Box>
                                                    <Typography
                                                        sx={{
                                                            color: isAccent
                                                                ? "rgba(17,17,17,0.6)"
                                                                : "var(--muted)",
                                                            fontSize: "0.76rem",
                                                            fontWeight: 700,
                                                            letterSpacing:
                                                                "0.06em",
                                                            textTransform:
                                                                "uppercase",
                                                        }}
                                                    >
                                                        2of3
                                                    </Typography>
                                                </Stack>
                                                <Typography
                                                    sx={{
                                                        fontWeight: 700,
                                                        fontSize: {
                                                            xs: "1.02rem",
                                                            md: "1.08rem",
                                                        },
                                                        lineHeight: 1.28,
                                                        color: isAccent
                                                            ? "#111111"
                                                            : "var(--ink)",
                                                        maxWidth: 620,
                                                    }}
                                                >
                                                    {item.question}
                                                </Typography>
                                                <Typography
                                                    sx={{
                                                        color: isAccent
                                                            ? "rgba(17,17,17,0.74)"
                                                            : "var(--muted)",
                                                        fontSize: "0.96rem",
                                                        lineHeight: 1.68,
                                                        maxWidth: 720,
                                                    }}
                                                >
                                                    {item.answer}
                                                </Typography>
                                            </Stack>
                                        );
                                    })}
                                </Box>
                            </Stack>
                        </Box>

                        <Box
                            component="footer"
                            sx={{
                                pt: { xs: 7, md: 11 },
                                pb: { xs: 4, md: 6.5 },
                                display: "flex",
                                justifyContent: "center",
                            }}
                        >
                            <Box
                                sx={{
                                    display: "flex",
                                    alignItems: "center",
                                    gap: { xs: 1, md: 1.25 },
                                }}
                            >
                                <Box
                                    component="a"
                                    href="https://ente.com"
                                    target="_blank"
                                    rel="noopener"
                                    sx={{
                                        color: "var(--ink)",
                                        fontWeight: 500,
                                        fontSize: {
                                            xs: "0.98rem",
                                            md: "1.06rem",
                                        },
                                        textDecoration: "none",
                                        display: "inline-flex",
                                        alignItems: "center",
                                        gap: 0.45,
                                        opacity: 0.58,
                                        transition: "opacity 140ms ease",
                                        "&:hover": {
                                            opacity: 1,
                                            textDecoration: "none",
                                        },
                                    }}
                                >
                                    <Box component="span">Made with</Box>
                                    <Box
                                        component="span"
                                        sx={{
                                            display: "inline-flex",
                                            alignItems: "center",
                                            justifyContent: "center",
                                        }}
                                    >
                                        <Box
                                            component="svg"
                                            viewBox="0 0 24 24"
                                            aria-hidden="true"
                                            sx={{
                                                width: 16,
                                                height: 16,
                                                display: "block",
                                                fill: "#d84a4a",
                                            }}
                                        >
                                            <path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z" />
                                        </Box>
                                    </Box>
                                    <Box component="span">by</Box>
                                    <Box
                                        component="span"
                                        sx={{ fontWeight: 700 }}
                                    >
                                        Ente
                                    </Box>
                                </Box>
                                <Box
                                    component="svg"
                                    aria-hidden="true"
                                    viewBox="0 0 6 6"
                                    sx={{
                                        width: 4,
                                        height: 4,
                                        display: "block",
                                        fill: "var(--line-strong)",
                                        opacity: 0.55,
                                    }}
                                >
                                    <circle cx="3" cy="3" r="3" />
                                </Box>
                                <Box
                                    component="a"
                                    href="https://github.com/ente/ente"
                                    target="_blank"
                                    rel="noopener"
                                    aria-label="View source on GitHub"
                                    sx={{
                                        color: "var(--ink)",
                                        display: "inline-flex",
                                        alignItems: "center",
                                        justifyContent: "center",
                                        opacity: 0.58,
                                        transition: "opacity 140ms ease",
                                        "&:hover": { opacity: 1 },
                                    }}
                                >
                                    <Box
                                        component="svg"
                                        viewBox="0 0 24 24"
                                        aria-hidden="true"
                                        sx={{
                                            width: 19,
                                            height: 19,
                                            display: "block",
                                            fill: "currentColor",
                                        }}
                                    >
                                        <path d="M12 .5C5.65.5.5 5.65.5 12A11.5 11.5 0 0 0 8.36 22.9c.58.1.79-.25.79-.56v-2.18c-3.2.7-3.88-1.36-3.88-1.36-.52-1.32-1.28-1.67-1.28-1.67-1.05-.72.08-.71.08-.71 1.15.08 1.76 1.18 1.76 1.18 1.03 1.76 2.7 1.25 3.36.96.1-.75.4-1.25.73-1.54-2.55-.29-5.24-1.28-5.24-5.68 0-1.25.45-2.27 1.17-3.07-.12-.29-.51-1.46.11-3.05 0 0 .96-.31 3.14 1.17a10.8 10.8 0 0 1 5.72 0c2.18-1.48 3.14-1.17 3.14-1.17.62 1.59.23 2.76.11 3.05.73.8 1.17 1.82 1.17 3.07 0 4.41-2.69 5.39-5.25 5.68.41.35.78 1.05.78 2.11v3.12c0 .31.21.67.8.56A11.5 11.5 0 0 0 23.5 12C23.5 5.65 18.35.5 12 .5Z" />
                                    </Box>
                                </Box>
                            </Box>
                        </Box>
                    </Stack>
                </Container>
            </Box>
        </>
    );
};

export default Page;
