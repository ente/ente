import { Box } from "@mui/material";
import { SpacePageMeta } from "components/SpacePageMeta";
import React from "react";

interface SpaceRouteFallbackProps {
    background: string;
    message?: string;
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
    preview,
}) => (
    <>
        <SpacePageMeta themeColor={background} preview={preview} />
        <Box
            sx={{
                alignItems: "center",
                bgcolor: background,
                display: "grid",
                minHeight: "100svh",
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
                            color: "#111111",
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
                <SpaceLoadingSpinner />
            )}
        </Box>
    </>
);
