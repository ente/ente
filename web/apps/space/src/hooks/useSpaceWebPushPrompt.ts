import { savedPartialLocalUser } from "ente-accounts-rs/services/accounts-db";
import { isSpaceIOS, isSpaceStandalone } from "hooks/useSpacePWAInstallPrompt";
import React from "react";
import {
    isBravePushServiceError,
    isSpaceWebPushSupported,
    reconcileSpaceWebPush,
    subscribeToSpaceWebPush,
    unsubscribeFromSpaceWebPush,
    type SpaceWebPushState,
} from "services/spaceWebPush";
import { isSpaceWebPushPilotAccount } from "services/spaceWebPushPilot";

type PromptStatus = "enabling" | "error" | "hidden" | "loading" | "ready";

const dismissedUntilKey = "space.webPush.dismissedUntil";
const dismissalDurationMs = 14 * 24 * 60 * 60 * 1000;

const storageGet = (key: string) => {
    try {
        return window.localStorage.getItem(key);
    } catch {
        return null;
    }
};

const storageSet = (key: string, value: string) => {
    try {
        window.localStorage.setItem(key, value);
    } catch {
        return;
    }
};

const storageRemove = (key: string) => {
    try {
        window.localStorage.removeItem(key);
    } catch {
        return;
    }
};

const isDismissed = () => {
    const dismissedUntil = Number(storageGet(dismissedUntilKey));
    if (!Number.isFinite(dismissedUntil) || dismissedUntil <= 0) return false;
    if (dismissedUntil > Date.now()) return true;
    storageRemove(dismissedUntilKey);
    return false;
};

export const useSpaceWebPushPrompt = () => {
    const updating = React.useRef(false);
    const [isAvailable, setIsAvailable] = React.useState(false);
    const [isPilotEligible, setIsPilotEligible] = React.useState(false);
    const [isSubscribed, setIsSubscribed] = React.useState<boolean | null>(
        null,
    );
    const [needsRecovery, setNeedsRecovery] = React.useState(false);
    const [needsBravePushMessaging, setNeedsBravePushMessaging] =
        React.useState(false);
    const [permissionDenied, setPermissionDenied] = React.useState(false);
    const [status, setStatus] = React.useState<PromptStatus>("loading");

    React.useEffect(() => {
        const pilotEligible = isSpaceWebPushPilotAccount(
            savedPartialLocalUser()?.email,
        );
        setIsPilotEligible(pilotEligible);
        const available =
            pilotEligible &&
            isSpaceWebPushSupported() &&
            (!isSpaceIOS() || isSpaceStandalone());
        setIsAvailable(available);
        if (!available) {
            setStatus("hidden");
            return;
        }

        let cancelled = false;
        let running = false;
        const applyState = (state: SpaceWebPushState) => {
            if (cancelled) return;
            const subscribed = state == "subscribed";
            const recovery = state == "recovery";
            const denied =
                state == "denied" || Notification.permission == "denied";
            const available = state != "unavailable";
            setIsAvailable(available);
            setIsSubscribed(available ? subscribed : null);
            setNeedsRecovery(recovery);
            setPermissionDenied(denied);
            setStatus(
                available &&
                    (state == "unsubscribed" || recovery) &&
                    !isDismissed()
                    ? "ready"
                    : "hidden",
            );
        };
        const reconcile = async () => {
            if (running || updating.current) return;
            running = true;
            try {
                applyState(await reconcileSpaceWebPush());
            } catch (error) {
                console.warn("Failed to prepare Space notifications", error);
                if (!cancelled) setStatus(isDismissed() ? "hidden" : "error");
            } finally {
                running = false;
            }
        };
        const visible = () => {
            if (document.visibilityState == "visible") void reconcile();
        };

        void reconcile();
        window.addEventListener("focus", reconcile);
        document.addEventListener("visibilitychange", visible);
        return () => {
            cancelled = true;
            window.removeEventListener("focus", reconcile);
            document.removeEventListener("visibilitychange", visible);
        };
    }, []);

    const dismiss = React.useCallback(() => {
        storageSet(dismissedUntilKey, String(Date.now() + dismissalDurationMs));
        setStatus("hidden");
    }, []);

    const enable = React.useCallback(async () => {
        updating.current = true;
        setNeedsBravePushMessaging(false);
        setStatus("enabling");
        try {
            const permission = await subscribeToSpaceWebPush();
            if (permission == "granted") {
                setIsSubscribed(true);
                setNeedsRecovery(false);
                setPermissionDenied(false);
                setStatus("hidden");
            } else if (permission == "default") {
                dismiss();
            } else {
                setIsSubscribed(false);
                setPermissionDenied(true);
                setStatus("hidden");
            }
        } catch (error) {
            if (await isBravePushServiceError(error)) {
                setNeedsBravePushMessaging(true);
            } else {
                console.warn("Failed to enable Space notifications", error);
            }
            setStatus("error");
        } finally {
            updating.current = false;
        }
    }, [dismiss]);

    const disable = React.useCallback(async () => {
        updating.current = true;
        setStatus("enabling");
        try {
            await unsubscribeFromSpaceWebPush();
            setIsSubscribed(false);
            setNeedsRecovery(false);
            dismiss();
        } catch (error) {
            console.warn("Failed to disable Space notifications", error);
            setStatus("error");
        } finally {
            updating.current = false;
        }
    }, [dismiss]);

    return {
        clearBravePushMessagingError: () => setNeedsBravePushMessaging(false),
        dismiss,
        enable,
        isAvailable,
        isEnabling: status == "enabling",
        isPilotEligible,
        isResolved: status != "loading",
        isSubscribed,
        needsBravePushMessaging,
        needsRecovery,
        permissionDenied,
        shouldShow: status == "ready" || status == "error",
        toggle: isSubscribed === true ? disable : enable,
    };
};
