import { Box, Typography } from "@mui/material";
import { memo, useEffect, useState } from "react";

interface GeneratingRiveIndicatorProps {
    size?: number;
    fallbackText?: string;
    isGenerating?: boolean;
    isOutroPhase?: boolean;
}

const DOT_STEP_MS = 420;

const GeneratingRiveIndicator = memo(
    ({
        size = 42,
        fallbackText,
        isGenerating = true,
        isOutroPhase = false,
    }: GeneratingRiveIndicatorProps) => {
        const [dotCount, setDotCount] = useState(1);
        const shouldAnimate = isGenerating || isOutroPhase;

        useEffect(() => {
            if (!shouldAnimate) {
                setDotCount(1);
                return;
            }

            const timer = window.setInterval(() => {
                setDotCount((prev) => (prev === 3 ? 1 : prev + 1));
            }, DOT_STEP_MS);

            return () => {
                window.clearInterval(timer);
            };
        }, [shouldAnimate]);

        if (!shouldAnimate) return null;

        return (
            <Box
                sx={{ display: "flex", alignItems: "center", minHeight: size }}
            >
                <Typography
                    variant="message"
                    aria-label={fallbackText ?? "Generating response"}
                    sx={{
                        color: "text.muted",
                        lineHeight: 1,
                        fontFamily: "monospace",
                        minWidth: "3ch",
                        whiteSpace: "pre",
                    }}
                >
                    {".".repeat(dotCount)}
                </Typography>
            </Box>
        );
    },
);

GeneratingRiveIndicator.displayName = "GeneratingRiveIndicator";

export default GeneratingRiveIndicator;
