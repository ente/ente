import { Box, Tooltip } from "@mui/material";
import { memo } from "react";

interface ContextMeterProps {
    usedTokens: number;
    totalTokens: number;
}

const formatTokenCount = (tokens: number) =>
    tokens >= 1000
        ? `${(tokens / 1000).toFixed(1).replace(/\.0$/, "")}k`
        : tokens.toLocaleString();

export const ContextMeter = memo(function ContextMeter({
    usedTokens,
    totalTokens,
}: ContextMeterProps) {
    const percentage =
        totalTokens > 0
            ? Math.min(100, Math.max(0, (usedTokens / totalTokens) * 100))
            : 0;
    const meterColor =
        percentage >= 90
            ? "critical.main"
            : percentage >= 70
              ? "warning.main"
              : "text.muted";

    return (
        <Tooltip
            arrow
            placement="top"
            title={`${formatTokenCount(usedTokens)} / ${formatTokenCount(totalTokens)} context positions — ${Math.round(percentage)}% used by the latest generation. Includes retained history, system instructions and processed output. Older messages may be left out as it fills up.`}
        >
            <Box
                role="meter"
                tabIndex={0}
                aria-label="Context usage"
                aria-valuemin={0}
                aria-valuemax={totalTokens}
                aria-valuenow={usedTokens}
                sx={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    position: "absolute",
                    left: "50%",
                    bottom: 0,
                    transform: "translateX(-50%)",
                    gap: "3px",
                    width: 76,
                    height: 12,
                    borderRadius: 1,
                    color: meterColor,
                    cursor: "help",
                    "&:hover": { bgcolor: "fill.faint" },
                    "&:focus-visible": {
                        outline: "2px solid",
                        outlineColor: "accent.main",
                        outlineOffset: 2,
                    },
                }}
            >
                {Array.from({ length: 10 }, (_, index) => (
                    <Box
                        key={index}
                        aria-hidden="true"
                        sx={{
                            width: 3,
                            height: 3,
                            borderRadius: "1px",
                            bgcolor:
                                percentage > index * 10
                                    ? "currentColor"
                                    : "divider",
                        }}
                    />
                ))}
            </Box>
        </Tooltip>
    );
});
