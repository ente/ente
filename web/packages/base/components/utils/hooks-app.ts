import type { NotificationAttributes } from "ente-base/components/Notification";
import { setupI18n } from "ente-base/i18n";
import { attachRustLogHook, disableDiskLogs } from "ente-base/log";
import { logUnhandledErrorsAndRejections } from "ente-base/log-web";
import { useRouter } from "next/router";
import { useCallback, useEffect, useState } from "react";

export const useSetupI18n = () => {
    const [isI18nReady, setIsI18nReady] = useState(false);

    useEffect(() => {
        void setupI18n().finally(() => setIsI18nReady(true));
    }, []);

    return isI18nReady;
};

interface SetupLoggingOptions {
    disableDiskLogs?: boolean;
}

export const useSetupLogs = (opts?: SetupLoggingOptions) => {
    useEffect(() => {
        if (opts?.disableDiskLogs) disableDiskLogs();
        attachRustLogHook();
        logUnhandledErrorsAndRejections(true);
        return () => logUnhandledErrorsAndRejections(false);
    }, []);
};

export const useIsRouteChangeInProgress = () => {
    const router = useRouter();
    const [loading, setLoading] = useState(false);

    useEffect(() => {
        const handleRouteChangeStart = (url: string) => {
            const newPathname = url.split("?")[0];
            if (window.location.pathname !== newPathname) {
                setLoading(true);
            }
        };

        const handleRouteChangeComplete = () => {
            setLoading(false);
        };

        router.events.on("routeChangeStart", handleRouteChangeStart);
        router.events.on("routeChangeComplete", handleRouteChangeComplete);

        return () => {
            router.events.off("routeChangeStart", handleRouteChangeStart);
            router.events.off("routeChangeComplete", handleRouteChangeComplete);
        };
    }, [router]);

    return loading;
};

export const useNotification = () => {
    const [attributes, setAttributes] = useState<
        NotificationAttributes | undefined
    >(undefined);

    const [open, setOpen] = useState(false);
    const [notificationID, setNotificationID] = useState(0);

    const showNotification = useCallback(
        (attributes: NotificationAttributes) => {
            setNotificationID((id) => id + 1);
            setAttributes(attributes);
            setOpen(true);
        },
        [],
    );

    const handleClose = useCallback(() => setOpen(false), []);

    return {
        showNotification,
        notificationProps: {
            notificationID,
            open,
            onClose: handleClose,
            attributes,
        },
    };
};
