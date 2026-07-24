import {
    AddSquareIcon,
    ArrowDown01Icon,
    MoreHorizontalIcon,
    MoreVerticalIcon,
    ScreenAddToHomeIcon,
    Upload01Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Dialog, useMediaQuery } from "@mui/material";
import { SpaceActionToast } from "components/SpaceActionToast";
import { SpaceBottomSheetTransition } from "components/SpaceBottomSheetTransition";
import { useSpacePWAInstallPrompt } from "hooks/useSpacePWAInstallPrompt";
import React from "react";

const green = "#08C225";
const textBase = "#000";
const textSoft = "#777777";

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
    const { dismiss, mode, shouldShow } = useSpacePWAInstallPrompt();
    const [instructionsOpen, setInstructionsOpen] = React.useState(false);
    const showPrompt = enabled && shouldShow;

    React.useEffect(() => {
        if (!showPrompt) setInstructionsOpen(false);
    }, [showPrompt]);

    if (!showPrompt) return null;

    const openInstructions = () => setInstructionsOpen(true);
    const closeInstructions = () => setInstructionsOpen(false);
    const dismissInstructions = () => {
        setInstructionsOpen(false);
        dismiss();
    };

    return (
        <>
            <SpaceActionToast
                action={
                    <Box
                        component="button"
                        type="button"
                        onClick={openInstructions}
                        sx={{
                            alignItems: "center",
                            bgcolor: green,
                            border: 0,
                            borderRadius: "14px",
                            color: "#FFFFFF",
                            cursor: "pointer",
                            display: "flex",
                            flexShrink: 0,
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 13,
                            fontWeight: 700,
                            height: 34,
                            justifyContent: "center",
                            lineHeight: "18px",
                            minWidth: 48,
                            px: "17px",
                            transition: "filter 120ms ease",
                            "&:active": { filter: "brightness(0.96)" },
                            "&:focus-visible": {
                                outline: "2px solid rgba(0 0 0 / 0.72)",
                                outlineOffset: 2,
                            },
                            "&:hover": { filter: "brightness(0.98)" },
                        }}
                    >
                        Add
                    </Box>
                }
                closeLabel="Close install prompt"
                icon={
                    <HugeiconsIcon
                        icon={ScreenAddToHomeIcon}
                        size={24}
                        strokeWidth={1.9}
                    />
                }
                message="Add to home screen"
                onClose={dismiss}
                zIndex={19}
            />
            <SpacePWAInstallInstructions
                mode={mode}
                open={instructionsOpen}
                onClose={closeInstructions}
                onDismiss={dismissInstructions}
            />
        </>
    );
};

interface SpacePWAInstallInstructionsProps {
    mode: ReturnType<typeof useSpacePWAInstallPrompt>["mode"];
    open: boolean;
    onClose: () => void;
    onDismiss: () => void;
}

const SpacePWAInstallInstructions: React.FC<
    SpacePWAInstallInstructionsProps
> = ({ mode, open, onClose, onDismiss }) => {
    const titleID = React.useId();
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
    const steps: InstallStep[] =
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

    return (
        <Dialog
            open={open}
            onClose={onClose}
            maxWidth={false}
            aria-labelledby={titleID}
            slots={
                isBottomSheet
                    ? { transition: SpaceBottomSheetTransition }
                    : undefined
            }
            slotProps={{
                backdrop: { sx: { backgroundColor: "rgba(0, 0, 0, 0.56)" } },
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
                    Add Space to your home screen
                </Box>
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
