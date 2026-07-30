import { AddSquareIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import React from "react";
import { spaceTouchTargetSize } from "styles/touchTargets";

const green = "#08C225";

interface SpaceInlinePostButtonProps {
    disabled?: boolean;
    onClick: () => void;
}

export const SpaceInlinePostButton: React.FC<SpaceInlinePostButtonProps> = ({
    disabled = false,
    onClick,
}) => (
    <Box
        className="green-bg"
        component="button"
        type="button"
        disabled={disabled}
        onClick={onClick}
        sx={{
            alignItems: "center",
            appearance: "none",
            bgcolor: green,
            border: 0,
            borderRadius: "20px",
            boxSizing: "border-box",
            color: "#FFFFFF",
            cursor: disabled ? "default" : "pointer",
            display: "inline-flex",
            fontFamily: '"Inter Variable", Inter, sans-serif',
            fontSize: 14,
            fontWeight: 600,
            gap: "8px",
            height: spaceTouchTargetSize,
            justifyContent: "center",
            lineHeight: "20px",
            mt: "24px",
            px: "16px",
            py: 0,
            pointerEvents: "auto",
            whiteSpace: "nowrap",
            "& svg": { display: "block", flexShrink: 0 },
            "&:focus-visible": {
                outline: `2px solid ${green}`,
                outlineOffset: 2,
            },
            "&:hover": disabled ? undefined : { bgcolor: "#07AE22" },
        }}
    >
        <HugeiconsIcon icon={AddSquareIcon} size={20} strokeWidth={1.8} />
        Share a moment
    </Box>
);
