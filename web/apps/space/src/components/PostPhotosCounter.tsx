import { Box } from "@mui/material";

export const SpacePostPhotosCounter = ({
    index,
    count,
    compact = false,
}: {
    index: number;
    count: number;
    compact?: boolean;
}) =>
    count > 1 ? (
        <Box
            component="span"
            aria-live="polite"
            aria-label={`Item ${index + 1} of ${count}`}
            sx={{
                alignItems: "center",
                bgcolor: compact
                    ? "rgba(32, 32, 32, 0.55)"
                    : "rgba(32, 32, 32, 0.85)",
                borderRadius: "999px",
                boxSizing: "border-box",
                color: "#E6E6E6",
                display: "inline-flex",
                fontFamily: '"Inter Variable", Inter, sans-serif',
                fontSize: compact ? 11 : 12,
                fontVariantNumeric: "tabular-nums",
                fontWeight: 700,
                height: compact ? 20 : 24,
                justifyContent: "center",
                lineHeight: "16px",
                minWidth: compact ? 40 : 48,
                px: compact ? "8px" : "10px",
                whiteSpace: "nowrap",
            }}
        >
            {index + 1} / {count}
        </Box>
    ) : null;
