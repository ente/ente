import {
    Alert02Icon,
    AlertCircleIcon,
    InformationCircleIcon,
    Tick02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { styled } from "@mui/material";
import type React from "react";
import { useEffect, useRef } from "react";
import { authMiniTypography, authTransientProps } from "./styles";

export type MessageKind = "error" | "warning" | "success" | "info";

export interface MessageProps {
    children: React.ReactNode;
    kind?: MessageKind;
    note?: boolean;
    visible?: boolean;
    id?: string;
}

export function Message({
    children,
    kind = "info",
    note = false,
    visible,
    id,
}: MessageProps): React.JSX.Element {
    const isVisible = visible ?? true;
    const lastVisibleContent = useRef({ children, kind });
    const displayedContent = isVisible
        ? { children, kind }
        : lastVisibleContent.current;

    useEffect(() => {
        if (isVisible) lastVisibleContent.current = { children, kind };
    }, [children, isVisible, kind]);

    return (
        <MessageRoot
            id={id}
            role={displayedContent.kind === "error" ? "alert" : "status"}
            aria-hidden={!isVisible || undefined}
            $kind={displayedContent.kind}
            $animated={visible !== undefined}
            $visible={isVisible}
        >
            <MessageContent $note={note}>
                <HugeiconsIcon
                    icon={messageIcons[displayedContent.kind]}
                    size={14}
                    strokeWidth={2}
                    aria-hidden="true"
                />
                <span>{displayedContent.children}</span>
            </MessageContent>
        </MessageRoot>
    );
}

const messageIcons = {
    error: AlertCircleIcon,
    warning: Alert02Icon,
    success: Tick02Icon,
    info: InformationCircleIcon,
} as const;

const MessageRoot = styled(
    "span",
    authTransientProps,
)<{ $kind: MessageKind; $animated: boolean; $visible: boolean }>(({
    $kind,
    $animated,
    $visible,
}) => {
    const delay = $visible ? "40ms" : "0ms";

    return {
        ...authMiniTypography,
        display: "inline-grid",
        gridTemplateRows: $visible ? "1fr" : "0fr",
        marginTop:
            $animated && !$visible
                ? "calc(-1 * var(--locker-auth-message-gap, 8px))"
                : 0,
        opacity: $visible ? 1 : 0,
        transform: $visible ? "translateY(0)" : "translateY(-4px)",
        visibility: $visible ? "visible" : "hidden",
        color:
            $kind === "error"
                ? "var(--locker-auth-warning)"
                : $kind === "warning"
                  ? "var(--locker-auth-caution)"
                  : $kind === "success"
                    ? "var(--locker-auth-success)"
                    : "var(--locker-auth-text-muted)",
        ...($animated && {
            overflow: "hidden",
            transition: [
                `grid-template-rows 360ms cubic-bezier(0.22, 1, 0.36, 1) ${delay}`,
                `margin-top 360ms cubic-bezier(0.22, 1, 0.36, 1) ${delay}`,
                `opacity 360ms cubic-bezier(0.22, 1, 0.36, 1) ${delay}`,
                `transform 360ms cubic-bezier(0.22, 1, 0.36, 1) ${delay}`,
                `visibility 0s linear ${$visible ? "0ms" : "360ms"}`,
            ].join(", "),
            "@media (prefers-reduced-motion: reduce)": { transition: "none" },
        }),
    };
});

const MessageContent = styled(
    "span",
    authTransientProps,
)<{ $note: boolean }>(({ $note }) => ({
    minHeight: 0,
    display: "inline-flex",
    alignItems: $note ? "flex-start" : "center",
    gap: $note ? "8px" : "4px",
    "& > svg": { flexShrink: 0 },
}));
