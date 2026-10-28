"use client";

import { editorToolbarButtonSx } from "@/theme/buttons";
import { Box, IconButton, Tooltip } from "@mui/material";
import type { ReactNode } from "react";

export default function EditorIconButton({
    label,
    onClick,
    disabled = false,
    children,
}: {
    label: string;
    onClick: () => void;
    disabled?: boolean;
    children: ReactNode;
}) {
    return (
        <Tooltip title={label} enterDelay={400}>
            <Box component="span" sx={{ display: "inline-flex" }}>
                <IconButton
                    aria-label={label}
                    onClick={onClick}
                    disabled={disabled}
                    sx={{
                        ...editorToolbarButtonSx,
                        width: 44,
                        p: 0,
                        "& .MuiSvgIcon-root": { fontSize: 20 },
                    }}
                >
                    {children}
                </IconButton>
            </Box>
        </Tooltip>
    );
}
