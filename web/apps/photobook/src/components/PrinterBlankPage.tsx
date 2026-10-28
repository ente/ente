"use client";

import { bookPageShadow, thumbnailShadow, uiColors } from "@/theme/colors";

import { Box, Typography } from "@mui/material";

export default function PrinterBlankPage({
    width,
    height,
    showLabel = false,
}: {
    width: number;
    height: number;
    showLabel?: boolean;
}) {
    return (
        <Box title="Blank page (required)" sx={{ width, flexShrink: 0 }}>
            <Box
                aria-label="Blank page (required)"
                sx={{
                    width,
                    height,
                    bgcolor: uiColors.paper,
                    borderRadius: 0.5,
                    boxShadow: showLabel ? bookPageShadow : thumbnailShadow,
                }}
            />
            {showLabel && (
                <Typography
                    sx={{
                        fontSize: { xs: 12, sm: 14 },
                        lineHeight: { xs: "16px", sm: "18px" },
                        color: uiColors.muted,
                        fontWeight: 600,
                        textAlign: "center",
                        mt: 0.5,
                    }}
                >
                    Blank page (required)
                </Typography>
            )}
        </Box>
    );
}
