import {
    AddSquareIcon,
    ArrowDown01Icon,
    Home01Icon,
    MoreHorizontalIcon,
    MoreVerticalIcon,
    MultiplicationSignIcon,
    Notification02Icon,
    ScreenAddToHomeIcon,
    Upload01Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Dialog, useMediaQuery } from "@mui/material";
import { SpaceBottomSheetTransition } from "components/SpaceBottomSheetTransition";
import { SpaceNotificationPermissionInstructions } from "components/SpaceNotificationPermissionInstructions";
import { useSpacePWAInstallPrompt } from "hooks/useSpacePWAInstallPrompt";
import { useSpaceWebPushPrompt } from "hooks/useSpaceWebPushPrompt";
import React from "react";
import { spaceTouchTargetSize } from "styles/touchTargets";

const green = "#08C225";
const textBase = "#000";
const textSoft = "#777777";
const authenticatedSessionSeenKey = "space.prompts.authenticatedSessionSeen";
const automaticPromptClaimedKey = "space.prompts.automaticClaimed";

interface SpacePWAInstallPromptProps {
    enabled: boolean;
}

interface InstallStep {
    icon: React.ReactNode;
    text: string;
}

export const SpacePWAInstallPrompt: React.FC<SpacePWAInstallPromptProps> = ({
    enabled,
}) => {
    const installPrompt = useSpacePWAInstallPrompt();
    const webPushPrompt = useSpaceWebPushPrompt();
    const [instructionsOpen, setInstructionsOpen] = React.useState(false);
    const [automaticAllowed] = React.useState(() => {
        try {
            if (sessionStorage.getItem(automaticPromptClaimedKey)) return false;
            const seen = localStorage.getItem(authenticatedSessionSeenKey);
            localStorage.setItem(authenticatedSessionSeenKey, "1");
            if (seen != "1") {
                sessionStorage.setItem(automaticPromptClaimedKey, "1");
            }
            return seen == "1";
        } catch {
            return false;
        }
    });
    const [claimedPrompt, setClaimedPrompt] = React.useState<
        "install" | "webPush" | null
    >(null);
    const hasCandidate = webPushPrompt.shouldShow || installPrompt.shouldShow;

    React.useEffect(() => {
        if (
            !enabled ||
            !automaticAllowed ||
            claimedPrompt ||
            !webPushPrompt.isResolved ||
            !hasCandidate
        ) {
            return;
        }
        try {
            sessionStorage.setItem(automaticPromptClaimedKey, "1");
        } catch {
            return;
        }
        setClaimedPrompt(
            webPushPrompt.shouldShow
                ? "webPush"
                : installPrompt.shouldShow
                  ? "install"
                  : null,
        );
    }, [
        automaticAllowed,
        claimedPrompt,
        enabled,
        hasCandidate,
        installPrompt.shouldShow,
        webPushPrompt.isResolved,
        webPushPrompt.shouldShow,
    ]);

    const hasWebPushPrompt =
        enabled && claimedPrompt == "webPush" && webPushPrompt.shouldShow;
    const hasInstallPrompt =
        enabled && claimedPrompt == "install" && installPrompt.shouldShow;
    const notificationInstructionsOpen = webPushPrompt.needsBravePushMessaging;
    const showWebPushPrompt =
        hasWebPushPrompt && !instructionsOpen && !notificationInstructionsOpen;
    const showInstallPrompt =
        hasInstallPrompt && !instructionsOpen && !notificationInstructionsOpen;

    React.useEffect(() => {
        if (!hasInstallPrompt) setInstructionsOpen(false);
    }, [hasInstallPrompt]);

    if (
        !showWebPushPrompt &&
        !showInstallPrompt &&
        !instructionsOpen &&
        !notificationInstructionsOpen
    ) {
        return null;
    }

    const addToHomeScreen = () => {
        if (installPrompt.mode == "native") {
            void installPrompt.install();
        } else {
            setInstructionsOpen(true);
        }
    };
    const closeInstructions = () => setInstructionsOpen(false);
    const dismissInstructions = () => {
        setInstructionsOpen(false);
        installPrompt.dismiss();
    };

    return (
        <>
            {showWebPushPrompt ? (
                <SpacePWAPromptBanner
                    actionDisabled={webPushPrompt.isEnabling}
                    actionLabel={
                        webPushPrompt.isEnabling ? "Turning on…" : "Turn on"
                    }
                    dismissLabel="Close notification prompt"
                    icon={Notification02Icon}
                    label={
                        webPushPrompt.needsRecovery
                            ? "Turn notifications back on"
                            : "Turn on notifications"
                    }
                    onAction={() => void webPushPrompt.enable()}
                    onDismiss={webPushPrompt.dismiss}
                />
            ) : showInstallPrompt ? (
                <SpacePWAPromptBanner
                    actionLabel="Add"
                    dismissLabel="Close install prompt"
                    icon={ScreenAddToHomeIcon}
                    label="Add to home screen"
                    onAction={addToHomeScreen}
                    onDismiss={installPrompt.dismiss}
                />
            ) : null}
            <SpacePWAInstallInstructions
                mode={installPrompt.mode}
                open={instructionsOpen}
                onClose={closeInstructions}
                onDismiss={dismissInstructions}
            />
            <SpaceNotificationPermissionInstructions
                mode="brave-push"
                open={notificationInstructionsOpen}
                onClose={webPushPrompt.clearBravePushMessagingError}
            />
        </>
    );
};

interface SpacePWAPromptBannerProps {
    actionDisabled?: boolean;
    actionLabel?: string;
    dismissLabel?: string;
    icon: Parameters<typeof HugeiconsIcon>[0]["icon"];
    hidden?: boolean;
    label: string;
    onAction?: () => void;
    onDismiss?: () => void;
    placement?: "bottom" | "top";
}

export const SpacePWAPromptBanner: React.FC<SpacePWAPromptBannerProps> = ({
    actionDisabled,
    actionLabel,
    dismissLabel,
    icon,
    hidden = false,
    label,
    onAction,
    onDismiss,
    placement = "top",
}) => (
    <Box
        aria-hidden={hidden}
        sx={{
            bottom:
                placement == "bottom"
                    ? "calc(env(safe-area-inset-bottom) + 16px)"
                    : undefined,
            boxSizing: "border-box",
            left: "50%",
            px: "16px",
            pointerEvents: "none",
            position: "fixed",
            top:
                placement == "top"
                    ? "calc(env(safe-area-inset-top) + 10px)"
                    : undefined,
            transform: hidden
                ? placement == "bottom"
                    ? "translate(-50%, calc(100% + env(safe-area-inset-bottom) + 16px))"
                    : "translate(-50%, calc(-100% - env(safe-area-inset-top) - 10px))"
                : "translate(-50%, 0)",
            transition: "transform 180ms ease",
            width: "100%",
            zIndex: 19,
            "@media (min-width: 600px)": { maxWidth: 390 },
            "@media (prefers-reduced-motion: reduce)": { transition: "none" },
        }}
    >
        <Box
            role="status"
            aria-live="polite"
            sx={{
                alignItems: "center",
                bgcolor: "#FFFFFF",
                borderRadius: "18px",
                boxShadow: "0 12px 32px rgba(0, 0, 0, 0.18)",
                color: textBase,
                display: "flex",
                fontFamily: '"Inter Variable", Inter, sans-serif',
                fontSize: 14,
                fontWeight: 650,
                gap: "10px",
                lineHeight: "20px",
                minHeight: 50,
                pointerEvents: hidden ? "none" : "auto",
                pl: "10px",
                pr: "6px",
                py: "3px",
                width: "100%",
            }}
        >
            <Box
                component="span"
                sx={{
                    alignItems: "center",
                    color: green,
                    display: "flex",
                    flexShrink: 0,
                    height: 24,
                    justifyContent: "center",
                    width: 24,
                }}
            >
                <HugeiconsIcon icon={icon} size={24} strokeWidth={1.9} />
            </Box>
            <Box
                sx={{
                    flex: "1 1 auto",
                    minWidth: 0,
                    overflow: "hidden",
                    textAlign: "left",
                    textOverflow: "ellipsis",
                    whiteSpace: "nowrap",
                }}
            >
                {label}
            </Box>
            <Box sx={{ alignItems: "center", display: "flex", flexShrink: 0 }}>
                {onAction && (
                    <Box
                        className="green-bg"
                        component="button"
                        type="button"
                        disabled={actionDisabled}
                        onClick={onAction}
                        sx={{
                            alignItems: "center",
                            bgcolor: green,
                            border: 0,
                            borderRadius: "14px",
                            color: "#FFFFFF",
                            cursor: actionDisabled ? "default" : "pointer",
                            display: "flex",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 13,
                            fontWeight: 700,
                            height: 34,
                            justifyContent: "center",
                            minWidth: 48,
                            opacity: actionDisabled ? 0.7 : 1,
                            px: "17px",
                        }}
                    >
                        {actionLabel}
                    </Box>
                )}
                {onDismiss && (
                    <Box
                        component="button"
                        type="button"
                        aria-label={dismissLabel}
                        onClick={onDismiss}
                        sx={{
                            alignItems: "center",
                            bgcolor: "transparent",
                            border: 0,
                            color: textBase,
                            cursor: "pointer",
                            display: "flex",
                            height: spaceTouchTargetSize,
                            justifyContent: "center",
                            p: 0,
                            width: 36,
                        }}
                    >
                        <HugeiconsIcon
                            icon={MultiplicationSignIcon}
                            size={16}
                            strokeWidth={2}
                        />
                    </Box>
                )}
            </Box>
        </Box>
    </Box>
);

interface SpacePWAInstallInstructionsProps {
    mode: ReturnType<typeof useSpacePWAInstallPrompt>["mode"];
    open: boolean;
    onClose: () => void;
    onDismiss: () => void;
    notificationEntryPoint?: "banner" | "settings";
    purpose?: "install" | "notifications";
}

export const SpacePWAInstallInstructions: React.FC<
    SpacePWAInstallInstructionsProps
> = ({
    mode,
    notificationEntryPoint = "settings",
    open,
    onClose,
    onDismiss,
    purpose = "install",
}) => {
    const titleID = React.useId();
    const descriptionID = React.useId();
    const isBottomSheet = useMediaQuery("(max-width: 599px)");
    const shareStep: InstallStep = {
        icon: <HugeiconsIcon icon={Upload01Icon} size={18} strokeWidth={2} />,
        text: 'Tap "Share"',
    };
    const viewMoreStep: InstallStep = {
        icon: (
            <HugeiconsIcon icon={ArrowDown01Icon} size={18} strokeWidth={2} />
        ),
        text: 'Tap "View More"',
    };
    const addHomeScreenStep: InstallStep = {
        icon: <HugeiconsIcon icon={AddSquareIcon} size={18} strokeWidth={2} />,
        text: 'Tap "Add to Home Screen"',
    };
    const iosSafariSteps: InstallStep[] = [
        {
            icon: (
                <HugeiconsIcon
                    icon={MoreHorizontalIcon}
                    size={18}
                    strokeWidth={3.2}
                />
            ),
            text: "Open your browser menu",
        },
        shareStep,
        viewMoreStep,
        addHomeScreenStep,
    ];
    const iosChromeSteps: InstallStep[] = [
        shareStep,
        viewMoreStep,
        addHomeScreenStep,
    ];
    const iosFallbackSteps: InstallStep[] = [
        {
            icon: (
                <HugeiconsIcon
                    icon={MoreHorizontalIcon}
                    size={18}
                    strokeWidth={3.2}
                />
            ),
            text: "Open your browser menu",
        },
        shareStep,
        addHomeScreenStep,
    ];
    const installSteps: InstallStep[] =
        mode == "ios-chrome"
            ? iosChromeSteps
            : mode == "ios-fallback"
              ? iosFallbackSteps
              : mode == "ios-safari"
                ? iosSafariSteps
                : [
                      {
                          icon: (
                              <HugeiconsIcon
                                  icon={MoreVerticalIcon}
                                  size={18}
                                  strokeWidth={3.2}
                              />
                          ),
                          text: "Open your browser menu",
                      },
                      {
                          icon: (
                              <HugeiconsIcon
                                  icon={MoreHorizontalIcon}
                                  size={18}
                                  strokeWidth={3.2}
                              />
                          ),
                          text: 'Tap "More"',
                      },
                      {
                          icon: (
                              <HugeiconsIcon
                                  icon={ScreenAddToHomeIcon}
                                  size={18}
                                  strokeWidth={2}
                              />
                          ),
                          text: 'Tap "Add to Home screen"',
                      },
                  ];
    const steps =
        purpose == "notifications"
            ? [
                  ...installSteps,
                  {
                      icon: (
                          <HugeiconsIcon
                              icon={Home01Icon}
                              size={18}
                              strokeWidth={2}
                          />
                      ),
                      text: "Open Space from your Home Screen",
                  },
                  {
                      icon: (
                          <HugeiconsIcon
                              icon={Notification02Icon}
                              size={18}
                              strokeWidth={2}
                          />
                      ),
                      text:
                          notificationEntryPoint == "banner"
                              ? 'Tap "Enable" to turn on notifications'
                              : "Turn on notifications in Settings",
                  },
              ]
            : installSteps;

    return (
        <Dialog
            open={open}
            onClose={onClose}
            maxWidth={false}
            aria-labelledby={titleID}
            aria-describedby={
                purpose == "notifications" ? descriptionID : undefined
            }
            sx={{ "--space-dialog-backdrop": "rgba(0 0 0 / 0.56)" }}
            slots={
                isBottomSheet
                    ? { transition: SpaceBottomSheetTransition }
                    : undefined
            }
            slotProps={{
                paper: {
                    sx: {
                        bgcolor: "#FFFFFF",
                        borderRadius: "28px 28px 0 0",
                        bottom: 0,
                        boxShadow: "0 -18px 44px rgba(0, 0, 0, 0.18)",
                        boxSizing: "border-box",
                        left: 0,
                        m: 0,
                        maxWidth: "none",
                        p: "26px 20px calc(24px + env(safe-area-inset-bottom))",
                        position: "fixed",
                        width: "100vw",
                        "@media (min-width: 600px)": {
                            borderRadius: "20px",
                            bottom: "auto",
                            boxShadow: "0 18px 48px rgba(0, 0, 0, 0.18)",
                            left: "50%",
                            maxWidth: 342,
                            p: "24px 20px 20px",
                            top: "50%",
                            transform: "translate(-50%, -50%)",
                            width: 342,
                        },
                    },
                },
            }}
        >
            <Box
                sx={{
                    maxWidth: 320,
                    mx: "auto",
                    width: "100%",
                    "@media (min-width: 600px)": { maxWidth: "none" },
                }}
            >
                <Box
                    component="h2"
                    id={titleID}
                    sx={{
                        color: textBase,
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 15,
                        fontWeight: 600,
                        lineHeight: "20px",
                        m: 0,
                        px: "20px",
                        textAlign: "center",
                    }}
                >
                    {purpose == "notifications"
                        ? "Turn on notifications"
                        : "Add Space to your home screen"}
                </Box>
                {purpose == "notifications" && (
                    <Box
                        component="p"
                        id={descriptionID}
                        sx={{
                            color: textSoft,
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 13,
                            lineHeight: "18px",
                            m: "8px 0 0",
                            px: "12px",
                            textAlign: "center",
                        }}
                    >
                        On iPhone, Space can send notifications only after
                        it&apos;s added to your Home Screen.
                    </Box>
                )}
                <Box sx={{ display: "grid", gap: "12px", mt: "22px" }}>
                    {steps.map((step, index) => (
                        <InstallInstructionStep
                            key={index}
                            icon={step.icon}
                            text={step.text}
                        />
                    ))}
                </Box>
                <Box
                    className="green-bg"
                    component="button"
                    type="button"
                    onClick={onDismiss}
                    sx={{
                        alignItems: "center",
                        bgcolor: green,
                        border: 0,
                        borderRadius: "20px",
                        color: "#FFFFFF",
                        cursor: "pointer",
                        display: "flex",
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 14,
                        fontWeight: 600,
                        height: 48,
                        justifyContent: "center",
                        lineHeight: "20px",
                        mt: "24px",
                        px: "24px",
                        transition: "filter 120ms ease",
                        width: "100%",
                        "&:active": { filter: "brightness(0.96)" },
                        "&:focus-visible": {
                            outline: "2px solid rgba(0 0 0 / 0.72)",
                            outlineOffset: 2,
                        },
                        "&:hover": { filter: "brightness(0.98)" },
                    }}
                >
                    Got it
                </Box>
            </Box>
        </Dialog>
    );
};

const InstallInstructionStep: React.FC<InstallStep> = ({ icon, text }) => (
    <Box
        sx={{
            alignItems: "center",
            bgcolor: "#FAFAFA",
            borderRadius: "18px",
            color: textSoft,
            display: "flex",
            gap: "12px",
            minHeight: 52,
            px: "14px",
            py: "10px",
        }}
    >
        <Box
            sx={{
                alignItems: "center",
                bgcolor: "#E7F6E9",
                borderRadius: "14px",
                color: green,
                display: "flex",
                flexShrink: 0,
                height: 32,
                justifyContent: "center",
                width: 32,
            }}
        >
            {icon}
        </Box>
        <Box
            sx={{
                fontFamily: '"Inter Variable", Inter, sans-serif',
                fontSize: 14,
                fontWeight: 600,
                lineHeight: "20px",
                minWidth: 0,
            }}
        >
            {text}
        </Box>
    </Box>
);
