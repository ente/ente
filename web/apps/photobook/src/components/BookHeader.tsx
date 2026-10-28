"use client";

import { Box, Typography } from "@mui/material";
import type { ReactNode } from "react";
import BookTitleInput from "./BookTitleInput";
import { EDITOR_HEADER_HEIGHT } from "./editorLayout";

export default function BookHeader({
    children,
    showBookControls = true,
}: {
    children: ReactNode;
    showBookControls?: boolean;
}) {
    return (
        <Box
            component="header"
            sx={{
                display: "grid",
                gridTemplateColumns: {
                    xs: "minmax(0, 1fr) minmax(0, max-content)",
                    md: "minmax(max-content, 1fr) minmax(0, max-content) minmax(max-content, 1fr)",
                },
                alignItems: "center",
                minHeight: showBookControls
                    ? { xs: 104, sm: 116, md: 76 }
                    : EDITOR_HEADER_HEIGHT,
                gap: 1,
                px: 1,
                flexShrink: 0,
            }}
        >
            <Box
                sx={{
                    gridColumn: 1,
                    gridRow: 1,
                    justifySelf: "start",
                    display: "flex",
                    alignItems: "center",
                    gap: 1,
                }}
            >
                <Box
                    component="img"
                    src="/ente-branding.svg"
                    alt="Ente"
                    sx={{
                        display: "block",
                        height: { xs: 16, sm: 20 },
                        width: "auto",
                        filter: "invert(1)",
                        "@media (max-width: 359px)": { height: 13 },
                    }}
                />
                <Typography
                    sx={{
                        fontFamily: '"Gochi Hand", cursive',
                        fontSize: { xs: 24, sm: 32 },
                        lineHeight: 1.2,
                        fontWeight: 400,
                        color: "#F2C14E",
                        transform: "translateY(1px)",
                        whiteSpace: "nowrap",
                        "@media (max-width: 359px)": { fontSize: 21 },
                    }}
                >
                    photobook
                </Typography>
            </Box>
            {showBookControls && <BookTitleInput />}
            <Box
                sx={{
                    gridColumn: { xs: "1 / -1", md: 3 },
                    gridRow: { xs: 2, md: 1 },
                    justifySelf: "end",
                    display: showBookControls ? "flex" : "none",
                    alignItems: "center",
                    gap: 1,
                }}
            >
                {children}
            </Box>
        </Box>
    );
}
