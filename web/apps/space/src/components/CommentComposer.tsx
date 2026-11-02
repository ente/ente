import { Navigation03Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import React from "react";
import {
    spaceControlBackground,
    spaceControlBackgroundHover,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import { clampSpaceMessageText } from "utils/message-limits";

export const SpaceCommentsButton: React.FC<{
    backgroundColor?: string;
    hoverBackgroundColor?: string;
    count: number;
    disabled?: boolean;
    onClick: () => void;
}> = ({
    backgroundColor = spaceControlBackground,
    hoverBackgroundColor = spaceControlBackgroundHover,
    count,
    disabled,
    onClick,
}) => (
    <Box
        component="button"
        type="button"
        aria-label={`Open comments, ${count} ${count == 1 ? "comment" : "comments"}`}
        disabled={disabled}
        onClick={onClick}
        sx={{
            alignItems: "center",
            bgcolor: backgroundColor,
            border: 0,
            borderRadius: "24px",
            color: spaceText,
            cursor: "pointer",
            display: "flex",
            flex: "0 0 auto",
            font: "inherit",
            fontSize: 14,
            fontWeight: 500,
            gap: 1,
            height: 48,
            justifyContent: "center",
            minWidth: 68,
            px: 1.5,
            "&:disabled": { opacity: 0.4, cursor: "default" },
            "&:hover": { bgcolor: hoverBackgroundColor },
            "&:focus-visible": {
                outline: "2px solid #08C225",
                outlineOffset: 2,
            },
        }}
    >
        <svg
            width={28}
            height={28}
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth={1.8}
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden="true"
            style={{ transform: "translateY(-1px)" }}
        >
            <path d="M20 16.5A9.5 8.5 0 1 0 16.5 19.5L21.5 21Z" />
        </svg>
        <Box component="span" sx={{ color: "#C4C4C8" }}>
            {count}
        </Box>
    </Box>
);

export const SpaceCommentComposer: React.FC<{
    autoFocus?: boolean;
    onSend: (text: string) => Promise<void>;
    text?: string;
    onTextChange?: (text: string) => void;
    disabled?: boolean;
    sendDisabled?: boolean;
    placeholder?: string;
    inputRef?: React.RefObject<HTMLTextAreaElement | null>;
}> = ({
    autoFocus,
    onSend,
    text: draftText,
    onTextChange,
    disabled,
    sendDisabled,
    placeholder = "Add a comment…",
    inputRef,
}) => {
    const [localText, setLocalText] = React.useState("");
    const text = draftText ?? localText;
    const setText = onTextChange ?? setLocalText;
    const [isSending, setIsSending] = React.useState(false);
    const [error, setError] = React.useState(false);
    const internalRef = React.useRef<HTMLTextAreaElement>(null);
    const ref = inputRef ?? internalRef;
    React.useLayoutEffect(() => {
        const input = ref.current;
        if (!input) return;
        input.style.height = "46px";
        input.style.height = `${Math.min(input.scrollHeight, 112)}px`;
    }, [ref, text]);
    const send = async () => {
        if (!text.trim() || isSending || disabled || sendDisabled) return;
        setIsSending(true);
        setError(false);
        try {
            await onSend(text);
            if (!onTextChange) setLocalText("");
        } catch {
            setError(true);
        } finally {
            setIsSending(false);
        }
    };
    return (
        <Box sx={{ flex: "1 1 auto", minWidth: 0 }}>
            <Box
                component="form"
                onSubmit={(event) => {
                    event.preventDefault();
                    void send();
                }}
                sx={{
                    alignItems: "flex-end",
                    border: "1px solid rgba(255, 255, 255, 0.08)",
                    borderRadius: "24px",
                    display: "flex",
                    minWidth: 0,
                    "&:focus-within": {
                        borderColor: "rgba(255, 255, 255, 0.32)",
                    },
                }}
            >
                <Box
                    ref={ref}
                    component="textarea"
                    autoFocus={autoFocus}
                    aria-label={
                        placeholder.startsWith("Reply")
                            ? "Reply to comment"
                            : "Comment"
                    }
                    placeholder={placeholder}
                    rows={1}
                    value={text}
                    disabled={disabled || isSending}
                    onChange={(event) =>
                        setText(clampSpaceMessageText(event.target.value))
                    }
                    onKeyDown={(event) => {
                        if (
                            event.key == "Enter" &&
                            !event.shiftKey &&
                            !event.nativeEvent.isComposing
                        ) {
                            event.preventDefault();
                            void send();
                        }
                    }}
                    sx={{
                        bgcolor: "transparent",
                        border: 0,
                        boxSizing: "border-box",
                        color: spaceText,
                        flex: "1 1 auto",
                        font: "inherit",
                        fontSize: 14,
                        lineHeight: "20px",
                        minHeight: 46,
                        minWidth: 0,
                        outline: 0,
                        p: "13px 16px",
                        resize: "none",
                        "&::placeholder": { color: spaceTextMuted },
                    }}
                />
                {text.trim() && (
                    <Box
                        component="button"
                        type="submit"
                        className="green-bg"
                        aria-label={
                            isSending ? "Sending comment" : "Send comment"
                        }
                        disabled={disabled || sendDisabled || isSending}
                        onPointerDown={(event) => event.preventDefault()}
                        sx={{
                            alignItems: "center",
                            bgcolor: "#08C225",
                            border: 0,
                            borderRadius: "50%",
                            color: spaceText,
                            cursor:
                                disabled || sendDisabled || isSending
                                    ? "default"
                                    : "pointer",
                            display: "flex",
                            flexShrink: 0,
                            height: 36,
                            justifyContent: "center",
                            m: "5px",
                            width: 36,
                            opacity:
                                disabled || sendDisabled || isSending ? 0.4 : 1,
                            "&:focus-visible": {
                                outline: "2px solid #08C225",
                                outlineOffset: 2,
                            },
                        }}
                    >
                        <HugeiconsIcon
                            icon={Navigation03Icon}
                            size={20}
                            strokeWidth={1.8}
                        />
                    </Box>
                )}
            </Box>
            {error && (
                <Box
                    role="alert"
                    sx={{ color: spaceTextMuted, fontSize: 12, px: 1, pt: 1 }}
                >
                    Couldn’t send. Please try again.
                </Box>
            )}
        </Box>
    );
};
