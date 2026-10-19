import {
    ImagePlusIcon,
    Navigation06Icon,
    StopIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, IconButton, InputBase } from "@mui/material";
import { alpha, type SxProps, type Theme } from "@mui/material/styles";
import {
    forwardRef,
    memo,
    useImperativeHandle,
    useLayoutEffect,
    useRef,
    useState,
} from "react";

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
        const inputRef = useRef<HTMLTextAreaElement | null>(null);

        useLayoutEffect(() => {
            if (inputRef.current) updateInputLayout(inputRef.current, input);
        }, [input]);

        useImperativeHandle(
            ref,
            () => ({
                focus: () => inputRef.current?.focus(),
                setText: setInput,
            }),
            [],
        );

        const send = () => void handleSend(input);
        const disableSend =
            (isPreparingMessage && !isGenerating) ||
            isModelPreparationActive ||
            sourcesLoading ||
            isDownloading ||
            (!isGenerating &&
                (isAttachingImages ||
                    (!input.trim() && !hasPendingAttachments)));

        return (
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
                        disabled={disableAttachmentButton}
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
                    inputRef={inputRef}
                    placeholder={
                        isDownloading ? "Downloading model..." : "Ask Ensu"
                    }
                    value={input}
                    onPasteCapture={(event) => {
                        const textarea = inputRef.current;
                        if (!textarea) return;
                        const pasted =
                            event.clipboardData.getData("text/plain");
                        const next =
                            textarea.value.slice(0, textarea.selectionStart) +
                            pasted +
                            textarea.value.slice(textarea.selectionEnd);
                        updateInputLayout(textarea, next);
                        requestAnimationFrame(() =>
                            updateInputLayout(textarea, textarea.value),
                        );
                    }}
                    onChange={(event) => {
                        const text = event.target.value;
                        setInput(text);
                        onTextChange(text);
                    }}
                    onKeyDown={(event) => {
                        if (event.key === "Enter" && !event.shiftKey) {
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
                            icon={isGenerating ? StopIcon : Navigation06Icon}
                            {...actionIconProps}
                        />
                    </Box>
                </IconButton>
            </Box>
        );
    }),
);

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
