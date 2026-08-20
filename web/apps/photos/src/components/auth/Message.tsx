import {
    Alert02Icon,
    AlertCircleIcon,
    InformationCircleIcon,
    Tick02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { styled } from "@mui/material";
import type React from "react";
import { authMiniTypography, authTransientProps } from "./styles";

export type MessageKind = "error" | "warning" | "success" | "info";

export interface MessageProps {
    children: React.ReactNode;
    kind?: MessageKind;
    note?: boolean;
    id?: string;
}

export function Message({
    children,
    kind = "info",
    note = false,
    id,
}: MessageProps): React.JSX.Element {
    const icon = messageIcons[kind];

    return (
        <MessageRoot
            id={id}
            role={kind === "error" ? "alert" : "status"}
            $kind={kind}
            $note={note}
        >
            <HugeiconsIcon
                icon={icon}
                size={14}
                strokeWidth={2}
                aria-hidden="true"
            />
            <span>{children}</span>
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
)<{ $kind: MessageKind; $note: boolean }>(({ $kind, $note }) => ({
    ...authMiniTypography,
    display: "inline-flex",
    alignItems: $note ? "flex-start" : "center",
    gap: $note ? "8px" : "4px",
    color:
        $kind === "error"
            ? "var(--photos-auth-warning)"
            : $kind === "warning"
              ? "var(--photos-auth-caution)"
              : $kind === "success"
                ? "var(--photos-auth-success)"
                : "var(--photos-auth-text-muted)",
    "& > svg": { flexShrink: 0 },
}));
