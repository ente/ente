import {
    subscribeMainWindowBlur,
    subscribeMainWindowFocus,
} from "ente-base/electron";
import log from "ente-base/log";
import { updateSessionFromElectronSafeStorageIfNeeded } from "ente-base/session";
import { useEffect, useRef, useState } from "react";
import {
    appLockSnapshot,
    clearAutoLockBlurSuppression,
    initAppLock,
    lock,
    refreshAppLockStateFromSession,
    shouldSuppressAutoLockOnBlur,
    type AppLockState,
} from "../../services/app-lock";

const hydrateSessionFromSafeStorageIfNeeded = async () => {
    try {
        /**
         * The current session's master key might already exist in the OS's safe
         * storage, so if found then write it back into browser sessionStorage.
         *
         * Without this the user would need to re-enter the password on every
         * desktop launch.
         */
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

/**
 * Initialize app lock and return its bootstrap state and retry callback.
 *
 * This is meant to be called once from the top-level `_app.tsx`.
 */
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

/**
 * Start and clear auto-lock timers as the app moves between background and
 * foreground states.
 */
export const useAutoLockWhenBackgrounded = (
    enabled: AppLockState["enabled"],
    isLocked: AppLockState["isLocked"],
    autoLockTimeMs: AppLockState["autoLockTimeMs"],
) => {
    // Holds the current timeout handle for a scheduled auto-lock.
    const pendingAutoLockTimeoutRef = useRef<ReturnType<
        typeof setTimeout
    > | null>(null);
    // Stores the exact timestamp when auto-lock should happen.
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
            // Return early if the lock deadline has not been reached yet.
            // If the deadline has passed, clear timer state and lock now.
            const deadline = autoLockDueAtTimestampRef.current;
            if (deadline === null) return false;
            if (Date.now() < deadline) return false;

            clearAutoLockTimer();
            lock();
            return true;
        };

        // Called when the app is backgrounded.
        // Starts auto-lock unless the app is already locked.
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

        // On foreground, lock immediately if the deadline passed; otherwise clear pending timer.
        const handleAppForegrounded = () => {
            clearAutoLockBlurSuppression();
            if (lockIfDeadlineElapsed()) return;
            clearAutoLockTimer();
        };

        // Hidden means backgrounded, so start auto-lock countdown.
        // Visible means foregrounded, so re-check deadline and clear timer if needed.
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

        // cleanup
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
