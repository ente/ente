import { Box } from "@mui/material";
import type React from "react";

export const SpaceVideoError: React.FC<{ message: string }> = ({ message }) => (
    <Box
        role="alert"
        sx={{
            alignItems: "center",
            color: "#D0D0D0",
            display: "flex",
            flexDirection: "column",
            fontFamily: '"Inter Variable", Inter, sans-serif',
            fontSize: 13,
            fontWeight: 500,
            gap: "2px",
            lineHeight: "18px",
            textAlign: "center",
            textWrap: "balance",
            "& > div": {
                bgcolor: "rgba(28, 28, 30, 0.88)",
                borderRadius: "999px",
                boxSizing: "border-box",
                maxWidth: "100%",
                p: "6px 16px",
                width: "fit-content",
            },
        }}
    >
        <Box>{message}</Box>
        <Box>Please contact support.</Box>
    </Box>
);
