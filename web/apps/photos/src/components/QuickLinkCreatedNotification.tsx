import { Copy01Icon, Tick02Icon } from "@hugeicons/core-free-icons";
import { Notification } from "ente-base/components/Notification";
import { t } from "i18next";
import React, { useEffect, useRef, useState } from "react";

interface QuickLinkCreatedNotificationProps {
    open: boolean;
    onClose: () => void;
    onCopy: () => void;
}

export const QuickLinkCreatedNotification: React.FC<
    QuickLinkCreatedNotificationProps
> = ({ open, onClose, onCopy }) => {
    const [copied, setCopied] = useState(false);
    const closeTimerRef = useRef<number | undefined>(undefined);

    useEffect(() => {
        if (open) {
            // Reset on open, not during the close animation.
            setCopied(false);
            return;
        }
        if (closeTimerRef.current) {
            window.clearTimeout(closeTimerRef.current);
            closeTimerRef.current = undefined;
        }
    }, [open]);

    useEffect(
        () => () => {
            if (closeTimerRef.current) {
                window.clearTimeout(closeTimerRef.current);
            }
        },
        [],
    );

    const handleCopy = () => {
        onCopy();
        setCopied(true);
        if (closeTimerRef.current) {
            window.clearTimeout(closeTimerRef.current);
        }
        closeTimerRef.current = window.setTimeout(() => {
            onClose();
            closeTimerRef.current = undefined;
        }, 2500);
    };

    return (
        <Notification
            open={open}
            onClose={onClose}
            keepOpenOnClick
            autoHideDuration={null}
            attributes={{
                color: "inherit",
                startIcon: null,
                title: t("link_created"),
                endIcon: copied ? Tick02Icon : Copy01Icon,
                endIconLabel: t("copy_link"),
                onEndIconClick: handleCopy,
            }}
        />
    );
};
