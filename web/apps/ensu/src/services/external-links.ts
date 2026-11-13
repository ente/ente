import { isTauriRuntime } from "@/services/tauri-runtime";
import type { MiniDialogAttributes } from "ente-base/components/MiniDialog";
import type { MouseEvent } from "react";

export const safeExternalUrl = (href: string | undefined) => {
    if (!href) return undefined;
    try {
        const url = new URL(href);
        return ["http:", "https:", "mailto:"].includes(url.protocol)
            ? url.toString()
            : undefined;
    } catch {
        return undefined;
    }
};

export const handleExternalLinkClick = (
    event: MouseEvent<HTMLAnchorElement>,
    showMiniDialog: (attributes: MiniDialogAttributes) => void,
) => {
    if (!isTauriRuntime() || event.button !== 0) return;
    const href = safeExternalUrl(event.currentTarget.href);
    if (!href) return;
    event.preventDefault();
    void import("@tauri-apps/plugin-opener")
        .then(({ openUrl }) => openUrl(href))
        .catch(() =>
            showMiniDialog({
                title: "Unable to open link",
                message: href,
                continue: {
                    text: "Copy link",
                    action: () => navigator.clipboard.writeText(href),
                },
                cancel: "Close",
            }),
        );
};
