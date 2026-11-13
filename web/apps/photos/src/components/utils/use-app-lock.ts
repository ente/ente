import {
    subscribeMainWindowBlur,
    subscribeMainWindowFocus,
} from "ente-base/electron";
import log from "ente-base/log";
import { updateSessionFromElectronSafeStorageIfNeeded } from "ente-new/photos/services/account-keys";
import {
    appLockSnapshot,
    clearAutoLockBlurSuppression,
    initAppLock,
    lock,
    refreshAppLockStateFromSession,
    shouldSuppressAutoLockOnBlur,
    type AppLockState,
} from "ente-new/photos/services/app-lock";
import { useEffect, useRef, useState } from "react";

const hydrateSessionFromSafeStorageIfNeeded = async () => {
    try {
        // Restore the master key before refreshing the lock state.
        await updateSessionFromElectronSafeStorageIfNeeded();
    } catch (e) {
        log.warn(
            "Failed to hydrate session from Electron safe storage during app lock bootstrap",
            e,
        );
    }
};

const bootstrapAppLock = async () => {
    await initAppLock();

    if (!appLockSnapshot().enabled) {
        return;
    }

    await hydrateSessionFromSafeStorageIfNeeded();
    await refreshAppLockStateFromSession();
};

export const useSetupAppLock = () => {
    const [status, setStatus] = useState<"loading" | "ready" | "error">(
        "loading",
    );
    const [attempt, setAttempt] = useState(0);

    useEffect(() => {
        let cancelled = false;

        const runBootstrap = async () => {
            try {
                await bootstrapAppLock();
                if (!cancelled) setStatus("ready");
            } catch (e) {
                log.error("Failed to bootstrap app lock", e);
                if (!cancelled) setStatus("error");
            }
        };

        void runBootstrap();

        return () => {
            cancelled = true;
        };
    }, [attempt]);

    return {
        isAppLockReady: status === "ready",
        appLockSetupFailed: status === "error",
        retryAppLockSetup: () => {
            setStatus("loading");
            setAttempt((attempt) => attempt + 1);
        },
    };
};

export const useAutoLockWhenBackgrounded = (
    enabled: AppLockState["enabled"],
    isLocked: AppLockState["isLocked"],
    autoLockTimeMs: AppLockState["autoLockTimeMs"],
) => {
    const pendingAutoLockTimeoutRef = useRef<ReturnType<
        typeof setTimeout
    > | null>(null);
    const autoLockDueAtTimestampRef = useRef<number | null>(null);

    useEffect(() => {
        if (!enabled) return;

        const clearAutoLockTimer = () => {
            if (pendingAutoLockTimeoutRef.current) {
                clearTimeout(pendingAutoLockTimeoutRef.current);
                pendingAutoLockTimeoutRef.current = null;
            }
            autoLockDueAtTimestampRef.current = null;
        };

        const lockIfDeadlineElapsed = () => {
            const deadline = autoLockDueAtTimestampRef.current;
            if (deadline === null) return false;
            if (Date.now() < deadline) return false;

            clearAutoLockTimer();
            lock();
            return true;
        };

        const startAutoLockTimer = () => {
            if (isLocked) return;
            if (shouldSuppressAutoLockOnBlur()) return;

            const existingDeadline = autoLockDueAtTimestampRef.current;
            if (existingDeadline !== null && Date.now() < existingDeadline) {
                return;
            }

            if (autoLockTimeMs <= 0) {
                clearAutoLockTimer();
                lock();
                return;
            }

            if (pendingAutoLockTimeoutRef.current) {
                clearTimeout(pendingAutoLockTimeoutRef.current);
            }
            autoLockDueAtTimestampRef.current = Date.now() + autoLockTimeMs;
            pendingAutoLockTimeoutRef.current = setTimeout(() => {
                autoLockDueAtTimestampRef.current = null;
                lock();
            }, autoLockTimeMs);
        };

        const handleAppForegrounded = () => {
            clearAutoLockBlurSuppression();
            if (lockIfDeadlineElapsed()) return;
            clearAutoLockTimer();
        };

        const handleVisibilityChange = () => {
            if (document.hidden) {
                startAutoLockTimer();
            } else {
                handleAppForegrounded();
            }
        };

        const handleWindowFocus = () => {
            handleAppForegrounded();
        };

        let unsubscribeMainWindowFocus: (() => void) | undefined;
        let unsubscribeMainWindowBlur: (() => void) | undefined;
        if (globalThis.electron) {
            unsubscribeMainWindowFocus = subscribeMainWindowFocus(
                handleAppForegrounded,
            );
            unsubscribeMainWindowBlur =
                subscribeMainWindowBlur(startAutoLockTimer);
        }

        document.addEventListener("visibilitychange", handleVisibilityChange);
        window.addEventListener("focus", handleWindowFocus);

        return () => {
            document.removeEventListener(
                "visibilitychange",
                handleVisibilityChange,
            );
            window.removeEventListener("focus", handleWindowFocus);
            unsubscribeMainWindowFocus?.();
            unsubscribeMainWindowBlur?.();
            clearAutoLockTimer();
        };
    }, [enabled, isLocked, autoLockTimeMs]);
};
