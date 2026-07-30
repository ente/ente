import { Box, Dialog, useMediaQuery } from "@mui/material";
import { SpaceBottomSheetTransition } from "components/SpaceBottomSheetTransition";
import { isSpaceIOS } from "hooks/useSpacePWAInstallPrompt";
import React from "react";

const green = "#08C225";
const textBase = "#000";
const textSoft = "#777777";

interface SpaceNotificationPermissionInstructionsProps {
    mode?: "brave-push" | "permission";
    onClose: () => void;
    open: boolean;
}

export const SpaceNotificationPermissionInstructions: React.FC<
    SpaceNotificationPermissionInstructionsProps
> = ({ mode = "permission", onClose, open }) => {
    const titleID = React.useId();
    const isBottomSheet = useMediaQuery("(max-width: 599px)");
    const isBravePush = mode == "brave-push";
    const steps = isBravePush
        ? [
              "Open Brave Settings",
              'Open "Privacy and security"',
              'Turn on "Use Google services for push messaging"',
              "Return to Space and try again",
          ]
        : isSpaceIOS()
          ? [
                "Open Settings",
                'Tap "Notifications"',
                'Tap "Ente Space" and turn on "Allow Notifications"',
            ]
          : [
                "Open your browser's site settings for Space",
                'Find "Notifications"',
                'Choose "Allow"',
            ];

    return (
        <Dialog
            open={open}
            onClose={onClose}
            aria-labelledby={titleID}
            maxWidth={false}
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
                    {isBravePush
                        ? "Turn on notifications in Brave"
                        : "Turn on notifications"}
                </Box>
                <Box
                    component="ol"
                    sx={{
                        display: "grid",
                        gap: "12px",
                        listStyle: "none",
                        mb: 0,
                        mt: "22px",
                        p: 0,
                    }}
                >
                    {steps.map((step, index) => (
                        <Box
                            component="li"
                            key={step}
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
                                    fontFamily:
                                        '"Inter Variable", Inter, sans-serif',
                                    fontSize: 13,
                                    fontWeight: 700,
                                    height: 32,
                                    justifyContent: "center",
                                    width: 32,
                                }}
                            >
                                {index + 1}
                            </Box>
                            <Box
                                sx={{
                                    fontFamily:
                                        '"Inter Variable", Inter, sans-serif',
                                    fontSize: 14,
                                    fontWeight: 600,
                                    lineHeight: "20px",
                                    minWidth: 0,
                                }}
                            >
                                {step}
                            </Box>
                        </Box>
                    ))}
                </Box>
                <Box
                    className="green-bg"
                    component="button"
                    type="button"
                    onClick={onClose}
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
