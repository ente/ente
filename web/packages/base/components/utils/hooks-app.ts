import type { NotificationAttributes } from "ente-base/components/Notification";
import { setupI18n } from "ente-base/i18n";
import { disableDiskLogs } from "ente-base/log";
import { logUnhandledErrorsAndRejections } from "ente-base/log-web";
import { useRouter } from "next/router";
import { useCallback, useEffect, useState } from "react";

/**
 * A hook that initializes the localization library that we use.
 *
 * This is only meant to be called from the top level `_app.tsx`, as this
 * initialization is intended to happen only once for the lifetime of the app.
 *
 * @returns a boolean which will be set to true when the localized strings have
 * been loaded.
 */
export const useSetupI18n = () => {
    const [isI18nReady, setIsI18nReady] = useState(false);

    useEffect(() => {
        void setupI18n().finally(() => setIsI18nReady(true));
    }, []);

    return isI18nReady;
};

interface SetupLoggingOptions {
    /** If true, then the logs will not be saved to local storage. */
    disableDiskLogs?: boolean;
}

/**
 * A hook that initializes the logging subsystem.
 *
 * This is only meant to be called from the top level `_app.tsx`, as this
 * initialization is intended to happen only once for the lifetime of the app.
 *
 * @param opts Optional {@link SetupLoggingOptions} to customize the setup.
 */
export const useSetupLogs = (opts?: SetupLoggingOptions) => {
    useEffect(() => {
        if (opts?.disableDiskLogs) disableDiskLogs();
        logUnhandledErrorsAndRejections(true);
        return () => logUnhandledErrorsAndRejections(false);
    }, []);
};

/**
 * A hook that keeps track of whether or not we are in the middle of a Next.js
 * route change.
 *
 * The top level app component uses this to show a loading indicator.
 */
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

/**
 * A React hook for simplifying the provisioning of a {@link showNotification}
 * function to inject in app contexts, and of the other props that are needed to
 * be passed to the {@link Notification}.
 */
export const useNotification = () => {
    const [attributes, setAttributes] = useState<
        NotificationAttributes | undefined
    >(undefined);

    const [open, setOpen] = useState(false);

    const showNotification = useCallback(
        (attributes: NotificationAttributes) => {
            setAttributes(attributes);
            setOpen(true);
        },
        [],
    );

    const handleClose = useCallback(() => setOpen(false), []);

    return {
        showNotification,
        notificationProps: { open, onClose: handleClose, attributes },
    };
};
