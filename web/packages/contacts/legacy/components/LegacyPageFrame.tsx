import ArrowBackOutlinedIcon from "@mui/icons-material/ArrowBackOutlined";
import { IconButton, Stack, Typography } from "@mui/material";
import React from "react";

interface LegacyPageFrameProps {
    title: string;
    caption?: React.ReactNode;
    description?: React.ReactNode;
    onBack: () => void;
    children: React.ReactNode;
}

export const LegacyPageFrame: React.FC<LegacyPageFrameProps> = ({
    title,
    caption,
    description,
    onBack,
    children,
}) => (
    <Stack sx={{ px: 2, pt: 2, pb: 2, gap: 3 }}>
        <Stack direction="row" sx={{ alignItems: "center" }}>
            <IconButton onClick={onBack} color="primary" sx={{ ml: -0.5 }}>
                <ArrowBackOutlinedIcon />
            </IconButton>
        </Stack>
        <Stack sx={{ gap: 0.5 }}>
            <Typography variant="h3">{title}</Typography>
            {caption && (
                <Typography
                    variant="small"
                    sx={{ color: "text.muted", wordBreak: "break-word" }}
                >
                    {caption}
                </Typography>
            )}
        </Stack>
        {description && (
            <Typography
                variant="body"
                sx={{ color: "text.muted", lineHeight: 1.5 }}
            >
                {description}
            </Typography>
        )}
        {children}
    </Stack>
);
