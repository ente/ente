import { Cancel01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import React from "react";
import {
    spaceControlBackgroundHover,
    spaceSurface,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import { spaceTouchTargetSize } from "styles/touch-targets";

const green = "#08C225";

export const ReplyComposerPreview: React.FC<{
    name: string;
    text: string;
    tone?: "accent" | "neutral";
    cancelLabel?: string;
    onCancel: () => void;
}> = ({
    name,
    text,
    tone = "accent",
    cancelLabel = "Cancel reply",
    onCancel,
}) => {
    const neutral = tone == "neutral";
    const lines = text.split("\n");
    const firstLine = lines[0] ?? text;
    const preview =
        firstLine.length > 100
            ? `${firstLine.slice(0, 100)}...`
            : lines.length > 1
              ? `${firstLine}...`
              : firstLine;
    return (
        <Box
            sx={{
                bgcolor: neutral ? spaceControlBackgroundHover : spaceSurface,
                borderLeft: `3px solid ${neutral ? "#686868" : green}`,
                borderRadius: "12px",
                boxSizing: "border-box",
                display: "grid",
                gridTemplateColumns: "minmax(0, 1fr)",
                maxWidth: "100%",
                overflow: "hidden",
                p: "9px 40px 9px 12px",
                position: "relative",
                width: "100%",
            }}
        >
            <Box sx={{ maxWidth: "100%", minWidth: 0, overflow: "hidden" }}>
                <Box
                    sx={{
                        color: neutral ? spaceText : spaceTextMuted,
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 12,
                        fontWeight: 650,
                        lineHeight: "16px",
                        overflow: "hidden",
                        textOverflow: "ellipsis",
                        whiteSpace: "nowrap",
                    }}
                >
                    {name}
                </Box>
                <Box
                    sx={{
                        color: neutral ? spaceTextMuted : spaceText,
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 13,
                        fontWeight: neutral ? 400 : 600,
                        lineHeight: "18px",
                        maxWidth: "100%",
                        overflow: "hidden",
                        overflowWrap: "anywhere",
                        textOverflow: "ellipsis",
                        whiteSpace: "nowrap",
                    }}
                >
                    {preview}
                </Box>
            </Box>
            <Box
                component="button"
                type="button"
                aria-label={cancelLabel}
                onClick={onCancel}
                sx={{
                    alignItems: "center",
                    bgcolor: "transparent",
                    border: 0,
                    borderRadius: "50%",
                    color: spaceTextMuted,
                    cursor: "pointer",
                    display: "flex",
                    height: spaceTouchTargetSize,
                    justifyContent: "center",
                    p: 0,
                    position: "absolute",
                    right: 0,
                    top: 0,
                    width: spaceTouchTargetSize,
                    "&:focus-visible": {
                        outline: `2px solid ${green}`,
                        outlineOffset: 2,
                    },
                    "&:hover": { color: spaceText },
                    "& svg": { position: "absolute", right: 8, top: 8 },
                }}
            >
                <HugeiconsIcon
                    icon={Cancel01Icon}
                    size={16}
                    strokeWidth={1.8}
                />
            </Box>
        </Box>
    );
};
