import { ArrowLeft02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import { SpacePageMeta } from "components/PageMeta";
import React from "react";
import { spaceAppBackground, spaceText } from "styles/colors";
import { spaceTouchTargetSize } from "styles/touch-targets";

interface SpaceRouteFallbackProps {
    background: string;
    message?: string;
    onBack?: () => void;
    preview?: "home" | "invite";
}

interface SpaceLoadingSpinnerProps {
    ariaLabel?: string;
    color?: string;
    size?: number;
    trackColor?: string;
}

export const SpaceLoadingSpinner: React.FC<SpaceLoadingSpinnerProps> = ({
    ariaLabel = "Loading",
    color = "#08C225",
    size = 26,
    trackColor = "rgba(8, 194, 37, 0.18)",
}) => (
    <Box
        component="span"
        role="status"
        aria-label={ariaLabel}
        sx={{
            animation: "spaceRouteFallbackSpin 800ms linear infinite",
            border: `2px solid ${trackColor}`,
            borderRadius: "50%",
            borderTopColor: color,
            height: size,
            width: size,
            "@keyframes spaceRouteFallbackSpin": {
                to: { transform: "rotate(360deg)" },
            },
        }}
    />
);

export const SpaceRouteFallback: React.FC<SpaceRouteFallbackProps> = ({
    background,
    message,
    onBack,
    preview,
}) => (
    <>
        <SpacePageMeta themeColor={background} preview={preview} />
        {onBack && (
            <Box
                component="button"
                type="button"
                aria-label="Back"
                onClick={onBack}
                sx={{
                    alignItems: "center",
                    bgcolor: "transparent",
                    border: 0,
                    color: spaceText,
                    cursor: "pointer",
                    display: "flex",
                    height: spaceTouchTargetSize,
                    justifyContent: "flex-start",
                    left: "max(16px, var(--space-ios-safe-area-left, 0px))",
                    p: 0,
                    position: "fixed",
                    top: "calc(12px + var(--space-ios-safe-area-top, 0px))",
                    width: spaceTouchTargetSize,
                    zIndex: 1,
                    "&:focus-visible": {
                        borderRadius: "50%",
                        outline: "2px solid #08C225",
                        outlineOffset: 2,
                    },
                }}
            >
                <HugeiconsIcon
                    icon={ArrowLeft02Icon}
                    size={24}
                    strokeWidth={1.8}
                />
            </Box>
        )}
        <Box
            sx={{
                alignItems: "center",
                background: spaceAppBackground,
                display: "grid",
                minHeight: "var(--space-page-height, 100svh)",
                placeItems: "center",
                px: 3,
                textAlign: "center",
            }}
        >
            {message ? (
                <Box sx={{ maxWidth: 300 }}>
                    <Box
                        role="alert"
                        sx={{
                            color: spaceText,
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 14,
                            fontWeight: 600,
                            lineHeight: "20px",
                        }}
                    >
                        {message}
                    </Box>
                </Box>
            ) : (
                <Box
                    sx={{
                        display: "grid",
                        inset: 0,
                        placeItems: "center",
                        pointerEvents: "none",
                        position: "fixed",
                    }}
                >
                    <SpaceLoadingSpinner />
                </Box>
            )}
        </Box>
    </>
);
