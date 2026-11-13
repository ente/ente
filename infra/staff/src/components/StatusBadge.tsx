import { Box } from "@mui/material";
import type { ReactNode } from "react";
import { SUCCESS_COLOR } from "../utils";

type StatusBadgeTone = "success" | "neutral";

interface StatusBadgeProps {
    children: ReactNode;
    highlighted: boolean;
    tone?: StatusBadgeTone;
}

export const StatusBadge = ({
    children,
    highlighted,
    tone = "neutral",
}: StatusBadgeProps) => (
    <Box
        component="span"
        sx={{
            bgcolor: highlighted ? statusBadgeColor(tone) : "transparent",
            borderRadius: "10px",
            color: highlighted ? "white" : "inherit",
            px: 1,
            py: 0.5,
        }}
    >
        {children}
    </Box>
);

const statusBadgeColor = (tone: StatusBadgeTone) =>
    tone === "success" ? SUCCESS_COLOR : "#494949";
