import { useVoiceInput, type WithVoiceInput } from "@/hooks/use-voice-input";
import { isTauriRuntime } from "@/services/tauri-runtime";
import { insertVoiceText, voiceTransport } from "@/services/voice";
import {
    ImagePlusIcon,
    Mic01Icon,
    Navigation06Icon,
    StopIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Box,
    CircularProgress,
    IconButton,
    InputBase,
    Tooltip,
    Typography,
} from "@mui/material";
import { alpha, type SxProps, type Theme } from "@mui/material/styles";
import {
    forwardRef,
    memo,
    useEffect,
    useImperativeHandle,
    useLayoutEffect,
    useRef,
    useState,
} from "react";
import { VoiceInputControls } from "./VoiceInputControls";

const sendButtonColor = "#E66A28";

interface IconProps {
    size: number;
    strokeWidth: number;
}

export interface ChatInputHandle {
    focus: () => void;
    setText: (text: string) => void;
}

interface ChatInputProps {
    actionIconProps: IconProps;
    disableAttachmentButton: boolean;
    drawerIconButtonSx: Exclude<SxProps<Theme>, readonly unknown[]>;
    handleSend: (input: string) => void | Promise<void>;
    handleStopGeneration: () => void;
    hasPendingAttachments: boolean;
    initialText: string;
    destination: string;
    withVoiceInput: WithVoiceInput;
    isAttachingImages: boolean;
    isDownloading: boolean;
    isGenerating: boolean;
    isModelPreparationActive: boolean;
    openPhotoPicker: () => void;
    onTextChange: (text: string) => void;
    sourcesLoading: boolean;
    isPreparingMessage: boolean;
    showAttachmentPicker: boolean;
}

export const ChatInput = memo(
    forwardRef<ChatInputHandle, ChatInputProps>(function ChatInput(
        {
            actionIconProps,
            disableAttachmentButton,
            drawerIconButtonSx,
            handleSend,
            handleStopGeneration,
            hasPendingAttachments,
            initialText,
            destination,
            withVoiceInput,
            isAttachingImages,
            isDownloading,
            isGenerating,
            isModelPreparationActive,
            openPhotoPicker,
            onTextChange,
            sourcesLoading,
            isPreparingMessage,
            showAttachmentPicker,
        },
        ref,
    ) {
        const [input, setInput] = useState(initialText);
        const [desktop, setDesktop] = useState(false);
        const [hasMicrophone, setHasMicrophone] = useState(false);
        const [voiceUnavailable, setVoiceUnavailable] = useState<string | null>(
            "Checking voice input…",
        );
        useEffect(() => {
            if (!isTauriRuntime()) return;
            setDesktop(true);
            const mediaDevices = (navigator as { mediaDevices?: MediaDevices })
                .mediaDevices;
            if (
                typeof mediaDevices?.enumerateDevices !== "function" ||
                typeof mediaDevices.getUserMedia !== "function" ||
                typeof globalThis.AudioWorkletNode !== "function"
            ) {
                setVoiceUnavailable(
                    "This system webview does not support microphone capture.",
                );
                return;
            }
            let active = true;
            let deviceCheck = 0;
            const updateMicrophone = () => {
                const check = ++deviceCheck;
                void mediaDevices
                    .enumerateDevices()
                    .then((devices) => {
                        if (active && check === deviceCheck)
                            setHasMicrophone(
                                devices.some(
                                    (device) => device.kind === "audioinput",
                                ),
                            );
                    })
                    .catch(() => {
                        if (active && check === deviceCheck)
                            setHasMicrophone(false);
                    });
            };
            updateMicrophone();
            mediaDevices.addEventListener("devicechange", updateMicrophone);
            window.addEventListener("focus", updateMicrophone);
            const deviceTimer = window.setInterval(() => {
                if (!document.hidden) updateMicrophone();
            }, 5000);
            void voiceTransport()
                .then(({ invoke }) =>
                    invoke<string | null>("voice_unavailable_reason"),
                )
                .then((reason) => {
                    if (active) setVoiceUnavailable(reason);
                })
                .catch(() => {
                    if (active)
                        setVoiceUnavailable(
                            "Voice input is unavailable. Restart Ensu and try again.",
                        );
                });
            return () => {
                active = false;
                mediaDevices.removeEventListener(
                    "devicechange",
                    updateMicrophone,
                );
                window.removeEventListener("focus", updateMicrophone);
                window.clearInterval(deviceTimer);
            };
        }, []);
        const draft = useRef({ text: initialText, revision: 0 });
        const pendingInsertion = useRef<
            | {
                  draft: typeof draft.current;
                  destination: string;
                  caret: number;
              }
            | undefined
        >(undefined);
        const composing = useRef(false);
        const [isComposing, setIsComposing] = useState(false);
        const inputRef = useRef<HTMLTextAreaElement | null>(null);

        const voice = useVoiceInput(
            destination,
            withVoiceInput,
            async (voiceText, anchor, isCurrent) => {
                const canApply = () => isCurrent() && !composing.current;
                const snapshot = draft.current;
                if (!canApply()) return;
                const inserted = await insertVoiceText({
                    anchor,
                    destination,
                    revision: snapshot.revision,
                    text: snapshot.text,
                    voiceText,
                    composing: composing.current,
                });
                if (!canApply() || snapshot !== draft.current) return;
                const insertedDraft = {
                    text: inserted.text,
                    revision: snapshot.revision + 1,
                };
                draft.current = insertedDraft;
                pendingInsertion.current = {
                    draft: insertedDraft,
                    destination: anchor.destination,
                    caret: inserted.caretUtf16,
                };
                setInput(inserted.text);
                onTextChange(inserted.text);
            },
        );

        const displayedInput = voice.view?.preview?.text ?? input;
        const previewCaret = voice.view?.preview?.caretUtf16;
        const listening =
            voice.view?.phase === "listening" ||
            voice.view?.phase === "countdown";

        useLayoutEffect(() => {
            const textarea = inputRef.current;
            if (!textarea) return;
            updateInputLayout(textarea, displayedInput);
            if (previewCaret !== undefined)
                scrollInputToCaret(textarea, previewCaret);
        }, [displayedInput, previewCaret]);

        useLayoutEffect(() => {
            const insertion = pendingInsertion.current;
            if (!insertion || voice.view) return;
            pendingInsertion.current = undefined;
            if (
                draft.current !== insertion.draft ||
                destination !== insertion.destination
            )
                return;
            const textarea = inputRef.current;
            if (textarea) {
                textarea.focus();
                scrollInputToCaret(textarea, insertion.caret);
            }
        });

        const cancelVoice = voice.cancel;
        useImperativeHandle(
            ref,
            () => ({
                focus: () => inputRef.current?.focus(),
                setText: (text) => {
                    cancelVoice();
                    draft.current = {
                        text,
                        revision: draft.current.revision + 1,
                    };
                    setInput(text);
                },
            }),
            [cancelVoice],
        );

        const send = () => {
            if (!voice.busy() && !composing.current && !disableSend)
                void handleSend(input);
        };
        const disableSend =
            !!voice.view ||
            (isPreparingMessage && !isGenerating) ||
            isModelPreparationActive ||
            sourcesLoading ||
            isDownloading ||
            (!isGenerating &&
                (isAttachingImages ||
                    (!input.trim() && !hasPendingAttachments)));

        const startVoice = () => {
            if (composing.current || voice.busy()) return;
            const textarea = inputRef.current;
            void voice.start(
                {
                    destination,
                    revision: draft.current.revision,
                    startUtf16: textarea?.selectionStart ?? input.length,
                    endUtf16: textarea?.selectionEnd ?? input.length,
                },
                draft.current.text,
            );
        };
        const voiceDisabledReason =
            voiceUnavailable ??
            (hasMicrophone
                ? null
                : "No microphone found. Connect a microphone to dictate.");

        return (
            <>
                {voice.error && (
                    <Typography
                        role="alert"
                        variant="small"
                        sx={{ px: 2, py: 1, color: "critical.main" }}
                    >
                        {voice.error}
                    </Typography>
                )}
                {voice.view && (
                    <VoiceInputControls
                        view={voice.view}
                        onCancel={voice.cancel}
                    />
                )}
                <Box
                    sx={{
                        display: "flex",
                        alignItems: "center",
                        gap: 0.5,
                        px: 1,
                        py: 0.75,
                        borderRadius: 2,
                        bgcolor:
                            "color-mix(in srgb, var(--mui-palette-background-default) 45%, var(--mui-palette-background-paper) 55%)",
                    }}
                >
                    {showAttachmentPicker && (
                        <IconButton
                            aria-label="Add photos"
                            disabled={disableAttachmentButton || !!voice.view}
                            sx={[
                                drawerIconButtonSx,
                                { width: 32, p: 0, flexShrink: 0 },
                            ]}
                            onClick={openPhotoPicker}
                        >
                            <HugeiconsIcon
                                icon={ImagePlusIcon}
                                {...actionIconProps}
                            />
                        </IconButton>
                    )}
                    <InputBase
                        multiline
                        inputComponent="textarea"
                        inputProps={{ rows: 1, type: undefined, wrap: "soft" }}
                        readOnly={!!voice.view}
                        onCompositionStart={() => {
                            composing.current = true;
                            setIsComposing(true);
                        }}
                        onCompositionEnd={() => {
                            composing.current = false;
                            setIsComposing(false);
                        }}
                        inputRef={inputRef}
                        placeholder={
                            isDownloading ? "Downloading model..." : "Ask Ensu"
                        }
                        value={displayedInput}
                        onPasteCapture={(event) => {
                            if (voice.busy()) return;
                            const textarea = inputRef.current;
                            if (!textarea) return;
                            const pasted =
                                event.clipboardData.getData("text/plain");
                            const next =
                                textarea.value.slice(
                                    0,
                                    textarea.selectionStart,
                                ) +
                                pasted +
                                textarea.value.slice(textarea.selectionEnd);
                            updateInputLayout(textarea, next);
                            requestAnimationFrame(() =>
                                updateInputLayout(textarea, textarea.value),
                            );
                        }}
                        onChange={(event) => {
                            if (voice.busy()) return;
                            const text = event.target.value;
                            draft.current = {
                                text,
                                revision: draft.current.revision + 1,
                            };
                            setInput(text);
                            onTextChange(text);
                        }}
                        onKeyDown={(event) => {
                            if (event.key === "Escape" && voice.busy()) {
                                event.preventDefault();
                                voice.cancel();
                                return;
                            }
                            if (
                                event.key === "Enter" &&
                                !event.shiftKey &&
                                !event.nativeEvent.isComposing &&
                                !composing.current &&
                                Reflect.get(event, "keyCode") !== 229
                            ) {
                                event.preventDefault();
                                send();
                            }
                        }}
                        sx={{
                            flex: 1,
                            minWidth: 0,
                            bgcolor: "transparent",
                            borderRadius: 2,
                            pl: 0,
                            pr: 1.5,
                            py: 1.5,
                            minHeight: 48,
                            display: "flex",
                            alignItems: "center",
                            fontFamily: "inherit",
                            fontSize: "15px",
                            lineHeight: 1.7,
                            color: "text.base",
                            "& textarea": {
                                fieldSizing: "content",
                                width: "100%",
                                maxHeight: "8.5em",
                                overflowY: "auto",
                                padding: 0,
                                margin: 0,
                            },
                            "& code": {
                                fontFamily:
                                    'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace',
                            },
                        }}
                    />
                    {desktop && voice.view ? (
                        listening ? (
                            <IconButton
                                aria-label="Finish voice input"
                                onClick={() => void voice.finish()}
                                sx={[
                                    drawerIconButtonSx,
                                    { color: sendButtonColor, flexShrink: 0 },
                                ]}
                            >
                                <HugeiconsIcon
                                    icon={StopIcon}
                                    {...actionIconProps}
                                />
                            </IconButton>
                        ) : (
                            <Box
                                sx={{
                                    width: 44,
                                    height: 44,
                                    flexShrink: 0,
                                    display: "grid",
                                    placeItems: "center",
                                }}
                            >
                                <CircularProgress size={20} />
                            </Box>
                        )
                    ) : (
                        desktop && (
                            <Tooltip
                                title={voiceDisabledReason ?? "Dictate message"}
                            >
                                <Box
                                    component="span"
                                    sx={{ display: "inline-flex" }}
                                >
                                    <IconButton
                                        aria-label="Dictate message"
                                        sx={drawerIconButtonSx}
                                        disabled={
                                            !!voiceDisabledReason ||
                                            isComposing ||
                                            isGenerating ||
                                            isPreparingMessage ||
                                            isModelPreparationActive ||
                                            isDownloading ||
                                            sourcesLoading
                                        }
                                        onMouseDown={(event) =>
                                            event.preventDefault()
                                        }
                                        onClick={startVoice}
                                    >
                                        <HugeiconsIcon
                                            icon={Mic01Icon}
                                            {...actionIconProps}
                                        />
                                    </IconButton>
                                </Box>
                            </Tooltip>
                        )
                    )}
                    <IconButton
                        aria-label={isGenerating ? "Stop" : "Send message"}
                        onClick={isGenerating ? handleStopGeneration : send}
                        disabled={disableSend}
                        sx={{
                            width: 44,
                            height: 44,
                            ml: 0.5,
                            borderRadius: 2,
                            bgcolor: "transparent",
                            color: sendButtonColor,
                            "&:hover": { bgcolor: "fill.faint" },
                            "&.Mui-disabled": {
                                color: alpha(sendButtonColor, 0.45),
                            },
                        }}
                    >
                        <Box
                            sx={{
                                transform: isGenerating
                                    ? undefined
                                    : "rotate(90deg)",
                                display: "flex",
                            }}
                        >
                            <HugeiconsIcon
                                icon={
                                    isGenerating ? StopIcon : Navigation06Icon
                                }
                                {...actionIconProps}
                            />
                        </Box>
                    </IconButton>
                </Box>
            </>
        );
    }),
);

function scrollInputToCaret(textarea: HTMLTextAreaElement, caret: number) {
    textarea.setSelectionRange(caret, caret);
    if (caret === textarea.value.length) {
        textarea.scrollTop = textarea.scrollHeight;
        return;
    }
    const measure = textarea.cloneNode() as HTMLTextAreaElement;
    measure.removeAttribute("id");
    measure.removeAttribute("name");
    measure.setAttribute("aria-hidden", "true");
    measure.tabIndex = -1;
    measure.value = textarea.value.slice(0, caret) + "\u200b";
    Object.assign(measure.style, {
        position: "absolute",
        visibility: "hidden",
        width: `${textarea.clientWidth}px`,
        height: "0",
        minHeight: "0",
        maxHeight: "none",
        boxSizing: "border-box",
        border: "0",
        overflow: "hidden",
    });
    measure.style.setProperty("field-sizing", "fixed");
    textarea.parentElement?.append(measure);
    const bottom = measure.scrollHeight;
    measure.remove();
    const top = bottom - parseFloat(getComputedStyle(textarea).lineHeight);
    textarea.scrollTop = Math.max(
        bottom - textarea.clientHeight,
        Math.min(textarea.scrollTop, top),
    );
}

function updateInputLayout(textarea: HTMLTextAreaElement, text: string) {
    let run = 0;
    let expensive = false;
    for (let i = 0; i < text.length; i++) {
        const code = text.charCodeAt(i);
        run = code > 32 && code < 127 ? run + 1 : 0;
        if (run > 16384) {
            expensive = true;
            break;
        }
    }
    textarea.style.setProperty("field-sizing", expensive ? "fixed" : "content");
    textarea.style.height = expensive ? "8.5em" : "";
    textarea.style.fontKerning = expensive ? "none" : "";
    textarea.style.fontVariantLigatures = expensive ? "none" : "";
}
