import { Notification02Icon, Tick02Icon } from "@hugeicons/core-free-icons";
import { SpaceNotificationPermissionInstructions } from "components/SpaceNotificationPermissionInstructions";
import {
    SpacePWAInstallInstructions,
    SpacePWAPromptBanner,
} from "components/SpacePWAInstallPrompt";
import { useHideOnScrollDirection } from "hooks/useHideOnScrollDirection";
import {
    isSpaceIOS,
    isSpaceStandalone,
    useSpacePWAInstallPrompt,
} from "hooks/useSpacePWAInstallPrompt";
import React from "react";
import type { PublicSpaceLinkSession } from "services/space";
import {
    isBravePushServiceError,
    isSpaceWebPushSupported,
    reconcilePublicSpaceWebPush,
    subscribeToPublicSpaceWebPush,
    type SpaceWebPushState,
} from "services/spaceWebPush";

type SuccessState = "exiting" | "hidden" | "visible";

const successDisplayDurationMs = 2400;
const toastTransitionDurationMs = 180;

interface SpacePublicProfileNotificationControlProps {
    session: PublicSpaceLinkSession;
}

export const SpacePublicProfileNotificationControl: React.FC<
    SpacePublicProfileNotificationControlProps
> = ({ session }) => {
    const installPrompt = useSpacePWAInstallPrompt();
    const updating = React.useRef(false);
    const successTimer = React.useRef<number | undefined>(undefined);
    const [state, setState] = React.useState<SpaceWebPushState>("unavailable");
    const [busy, setBusy] = React.useState(true);
    const [successState, setSuccessState] =
        React.useState<SuccessState>("hidden");
    const [installInstructionsOpen, setInstallInstructionsOpen] =
        React.useState(false);
    const [permissionInstructionsOpen, setPermissionInstructionsOpen] =
        React.useState(false);
    const [needsBravePushMessaging, setNeedsBravePushMessaging] =
        React.useState(false);
    const route =
        typeof window == "undefined"
            ? ""
            : `${window.location.pathname}${window.location.search}${window.location.hash}`;
    const requiresIOSInstall = isSpaceIOS() && !isSpaceStandalone();
    const isHiddenForScroll = useHideOnScrollDirection();

    React.useEffect(
        () => () => {
            if (successTimer.current !== undefined) {
                window.clearTimeout(successTimer.current);
            }
        },
        [],
    );

    const reconcile = React.useCallback(async () => {
        if (!route || !isSpaceWebPushSupported() || requiresIOSInstall) {
            setState("unavailable");
            setBusy(false);
            return;
        }
        try {
            setState(await reconcilePublicSpaceWebPush(session, route));
        } catch (error) {
            console.warn(
                "Failed to reconcile public Space notifications",
                error,
            );
            setState("recovery");
        } finally {
            setBusy(false);
        }
    }, [requiresIOSInstall, route, session]);

    React.useEffect(() => {
        let running = false;
        const check = () => {
            if (running || updating.current) return;
            running = true;
            void reconcile().finally(() => {
                running = false;
            });
        };
        const checkWhenVisible = () => {
            if (document.visibilityState == "visible") check();
        };

        check();
        window.addEventListener("focus", check);
        document.addEventListener("visibilitychange", checkWhenVisible);
        return () => {
            window.removeEventListener("focus", check);
            document.removeEventListener("visibilitychange", checkWhenVisible);
        };
    }, [reconcile]);

    const canShowNotifications =
        !requiresIOSInstall && isSpaceWebPushSupported();
    const hasNotificationAction =
        canShowNotifications &&
        (updating.current ||
            (!busy && state != "subscribed" && state != "unavailable"));
    const hasInstallPrompt = requiresIOSInstall && installPrompt.canInstall;
    const instructionsOpen =
        installInstructionsOpen || permissionInstructionsOpen;
    const showNotificationAction = hasNotificationAction && !instructionsOpen;
    const showInstallPrompt = hasInstallPrompt && !instructionsOpen;

    const enable = async () => {
        if (Notification.permission == "denied") {
            setNeedsBravePushMessaging(false);
            setPermissionInstructionsOpen(true);
            return;
        }
        if (successTimer.current !== undefined) {
            window.clearTimeout(successTimer.current);
            successTimer.current = undefined;
        }
        setSuccessState("hidden");
        setNeedsBravePushMessaging(false);
        updating.current = true;
        setBusy(true);
        try {
            const permission = await subscribeToPublicSpaceWebPush(
                session,
                route,
            );
            if (permission == "granted") {
                setState("subscribed");
                setSuccessState("visible");
                successTimer.current = window.setTimeout(() => {
                    setSuccessState("exiting");
                    successTimer.current = window.setTimeout(() => {
                        successTimer.current = undefined;
                        setSuccessState("hidden");
                    }, toastTransitionDurationMs);
                }, successDisplayDurationMs);
            } else if (permission == "denied") {
                setState("denied");
                setPermissionInstructionsOpen(true);
            }
        } catch (error) {
            if (await isBravePushServiceError(error)) {
                setNeedsBravePushMessaging(true);
                setPermissionInstructionsOpen(true);
            } else {
                console.warn(
                    "Failed to update public Space notifications",
                    error,
                );
            }
            setState("recovery");
        } finally {
            updating.current = false;
            setBusy(false);
        }
    };

    return (
        <>
            {successState != "hidden" ? (
                <SpacePWAPromptBanner
                    hidden={isHiddenForScroll || successState == "exiting"}
                    icon={Tick02Icon}
                    label="You’ll be notified about new posts"
                    placement="bottom"
                />
            ) : showNotificationAction ? (
                <SpacePWAPromptBanner
                    actionDisabled={busy}
                    actionLabel={busy ? "Enabling…" : "Enable"}
                    hidden={isHiddenForScroll}
                    icon={Notification02Icon}
                    label="Get notified about new posts"
                    onAction={() => void enable()}
                    placement="bottom"
                />
            ) : null}
            {showInstallPrompt && (
                <SpacePWAPromptBanner
                    actionLabel="Enable"
                    hidden={isHiddenForScroll}
                    icon={Notification02Icon}
                    label="Get notified about new posts"
                    onAction={() => setInstallInstructionsOpen(true)}
                    placement="bottom"
                />
            )}
            <SpacePWAInstallInstructions
                mode={installPrompt.mode}
                notificationEntryPoint="banner"
                open={installInstructionsOpen}
                onClose={() => setInstallInstructionsOpen(false)}
                onDismiss={() => setInstallInstructionsOpen(false)}
                purpose="notifications"
            />
            <SpaceNotificationPermissionInstructions
                mode={needsBravePushMessaging ? "brave-push" : "permission"}
                open={permissionInstructionsOpen}
                onClose={() => {
                    setPermissionInstructionsOpen(false);
                    setNeedsBravePushMessaging(false);
                }}
            />
        </>
    );
};
