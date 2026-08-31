import { Navigation06Icon, Upload01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, IconButton, InputBase } from "@mui/material";
import type { SxProps, Theme } from "@mui/material/styles";
import React, {
    forwardRef,
    memo,
    useImperativeHandle,
    useRef,
    useState,
} from "react";

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
    drawerIconButtonSx: SxProps<Theme>;
    handleSend: (input: string) => void | Promise<void>;
    handleStopGeneration: () => void;
    hasPendingAttachments: boolean;
    initialText: string;
    isAttachingImages: boolean;
    isDownloading: boolean;
    isGenerating: boolean;
    isModelPreparationActive: boolean;
    openAttachmentMenu: (event: React.MouseEvent<HTMLElement>) => void;
    onTextChange: (text: string) => void;
    showAttachmentPicker: boolean;
    stopButtonColor: string;
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
            openAttachmentMenu,
            onTextChange,
            showAttachmentPicker,
            stopButtonColor,
        },
        ref,
    ) {
        const [input, setInput] = useState(initialText);
        const inputRef = useRef<HTMLTextAreaElement | null>(null);

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
            isModelPreparationActive ||
            isDownloading ||
            (!isGenerating &&
                (isAttachingImages ||
                    (!input.trim() && !hasPendingAttachments)));

        return (
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
                    inputComponent="textarea"
                    inputProps={{ rows: 1, type: undefined }}
                    inputRef={inputRef}
                    placeholder={
                        isDownloading
                            ? "Downloading model..."
                            : "Write a message..."
                    }
                    value={input}
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
                            fieldSizing: "content",
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
                {showAttachmentPicker && (
                    <IconButton
                        aria-label="Add attachment"
                        sx={drawerIconButtonSx}
                        disabled={disableAttachmentButton}
                        onClick={openAttachmentMenu}
                    >
                        <HugeiconsIcon
                            icon={Upload01Icon}
                            {...actionIconProps}
                        />
                    </IconButton>
                )}
                <IconButton
                    aria-label={isGenerating ? "Stop" : "Send message"}
                    onClick={isGenerating ? handleStopGeneration : send}
                    disabled={disableSend}
                    sx={{
                        width: 44,
                        height: 44,
                        borderRadius: 2,
                        bgcolor: "transparent",
                        color: isGenerating ? "critical.main" : "text.muted",
                        "&:hover": { bgcolor: "fill.faint" },
                        "&.Mui-disabled": { color: "text.faint" },
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
                                justifyContent: "center",
                            }}
                        >
                            <Box
                                component="svg"
                                viewBox="0 0 24 24"
                                sx={{ width: 12, height: 12, display: "block" }}
                            >
                                <path
                                    d="M4 12C4 8.72077 4 7.08116 4.81382 5.91891C5.1149 5.48891 5.48891 5.1149 5.91891 4.81382C7.08116 4 8.72077 4 12 4C15.2792 4 16.9188 4 18.0811 4.81382C18.5111 5.1149 18.8851 5.48891 19.1862 5.91891C20 7.08116 20 8.72077 20 12C20 15.2792 20 16.9188 19.1862 18.0811C18.8851 18.5111 18.5111 18.8851 18.0811 19.1862C16.9188 20 15.2792 20 12 20C8.72077 20 7.08116 20 5.91891 19.1862C5.48891 18.8851 5.1149 18.5111 4.81382 18.0811C4 16.9188 4 15.2792 4 12Z"
                                    fill={stopButtonColor}
                                />
                            </Box>
                        </Box>
                    ) : (
                        <Box
                            sx={{ transform: "rotate(90deg)", display: "flex" }}
                        >
                            <HugeiconsIcon
                                icon={Navigation06Icon}
                                {...actionIconProps}
                            />
                        </Box>
                    )}
                </IconButton>
            </Box>
        );
    }),
);
