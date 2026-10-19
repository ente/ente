import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import { Box, Stack, Typography } from "@mui/material";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import React from "react";

interface RowCardProps {
    variant?: "default" | "parent";
    title: React.ReactNode;
    subtitle?: string;
    onClick?: () => void;
    endIcon?: React.ReactNode;
}

export const RowCard: React.FC<RowCardProps> = ({
    variant = "default",
    title,
    subtitle,
    onClick,
    endIcon = <ChevronRightIcon className="ente-chevron-right" />,
}) => (
    <Box
        component={onClick ? FocusVisibleButton : "div"}
        onClick={onClick}
        sx={[
            {
                display: "flex",
                width: "100%",
                p: "14px 8px 14px 0.5rem",
                gap: 1,
                justifyContent: "space-between",
                alignItems: "center",
                textAlign: "left",
                borderRadius: "10px",
                color: "text.base",
                bgcolor: "transparent",
                "&:hover": { bgcolor: onClick ? "fill.faintHover" : undefined },
                "& .MuiSvgIcon-root": { fontSize: "20px", color: "text.muted" },
            },
            variant == "parent" && {
                px: 2,
                m: 0.5,
                width: "calc(100% - 8px)",
                borderRadius: 2,
            },
            (theme) =>
                theme.applyStyles("dark", {
                    "&:hover": {
                        bgcolor: onClick
                            ? variant == "parent"
                                ? "fill.faintHover"
                                : "backdrop.muted"
                            : undefined,
                    },
                }),
        ]}
    >
        <Stack sx={{ minWidth: 0 }}>
            <Typography noWrap sx={{ fontWeight: "medium" }}>
                {title}
            </Typography>
            {subtitle && (
                <Typography
                    noWrap
                    variant="small"
                    sx={{
                        color: "text.muted",
                        lineHeight: "20px",
                        fontWeight: 400,
                    }}
                >
                    {subtitle}
                </Typography>
            )}
        </Stack>
        {endIcon}
    </Box>
);
