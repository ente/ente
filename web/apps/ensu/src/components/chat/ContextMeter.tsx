import { Box, Tooltip } from "@mui/material";
import { memo } from "react";

interface ContextMeterProps {
    usedTokens: number;
    totalTokens: number;
    estimated?: boolean;
}

const formatTokenCount = (tokens: number) =>
    tokens >= 1000
        ? `${(tokens / 1000).toFixed(1).replace(/\.0$/, "")}k`
        : tokens.toLocaleString();

export const ContextMeter = memo(function ContextMeter({
    usedTokens,
    totalTokens,
    estimated = false,
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
            title={`${estimated ? "Estimated" : "Calculated"} context: ${formatTokenCount(usedTokens)} / ${formatTokenCount(totalTokens)} (${Math.round(percentage)}%)`}
        >
            <Box
                role="meter"
                tabIndex={0}
                aria-label="Context usage"
                aria-valuemin={0}
                aria-valuemax={totalTokens}
                aria-valuenow={Math.min(totalTokens, Math.max(0, usedTokens))}
                aria-valuetext={
                    usedTokens > totalTokens
                        ? `${estimated ? "Estimated" : "Calculated"}: ${usedTokens.toLocaleString()} of ${totalTokens.toLocaleString()} context positions, ${(usedTokens - totalTokens).toLocaleString()} over the limit`
                        : undefined
                }
                sx={{
                    display: "flex",
                    alignItems: "flex-end",
                    position: "absolute",
                    left: 16,
                    right: 16,
                    bottom: 0,
                    height: 10,
                    pb: "3px",
                    color: meterColor,
                    cursor: "help",
                    "&:hover .context-meter-fill, &:focus-visible .context-meter-fill":
                        { opacity: 1 },
                    "&:focus-visible": {
                        outline: "2px solid",
                        outlineColor: "accent.main",
                        outlineOffset: 2,
                    },
                }}
            >
                <Box
                    aria-hidden="true"
                    sx={{
                        width: "100%",
                        height: 2,
                        bgcolor: "divider",
                        borderRadius: "1px",
                        overflow: "hidden",
                    }}
                >
                    <Box
                        className="context-meter-fill"
                        sx={{
                            width: `${percentage}%`,
                            height: "100%",
                            bgcolor: "currentColor",
                            opacity: percentage >= 70 ? 1 : 0.6,
                        }}
                    />
                </Box>
            </Box>
        </Tooltip>
    );
});
