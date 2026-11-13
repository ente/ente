import CheckIcon from "@mui/icons-material/Check";
import { Box, Typography } from "@mui/material";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import type { ReactNode } from "react";

interface MenuComponentProps {
    title: string;
    description?: ReactNode;
    selected?: boolean;
    onClick: () => void;
    startIcon?: ReactNode;
    endIcon?: ReactNode;
    disabled?: boolean;
    loading?: boolean;
}

export function MenuComponent({
    title,
    description,
    selected,
    onClick,
    startIcon,
    endIcon,
    disabled = false,
    loading = false,
}: MenuComponentProps) {
    return (
        <FocusVisibleButton
            fullWidth
            onClick={onClick}
            aria-pressed={selected}
            aria-busy={loading}
            disabled={disabled || loading}
            sx={[
                {
                    minHeight: 58,
                    py: "9px",
                    pl: startIcon ? "12px" : "16px",
                    pr: "12px",
                    gap: "12px",
                    borderRadius: "20px",
                    color: "text.base",
                    bgcolor: "transparent",
                    textAlign: "left",
                    "&:hover": { bgcolor: "fill.faintHover" },
                    "&:active": { bgcolor: "fill.muted" },
                    "&.Mui-focusVisible": { outlineOffset: "-2px" },
                    "&.Mui-disabled": { color: "text.muted" },
                },
                (theme) =>
                    theme.applyStyles("dark", {
                        "&:hover": { bgcolor: "#0a0a0a" },
                        "&:active": { bgcolor: "#141414" },
                    }),
            ]}
        >
            {startIcon && (
                <Box
                    sx={{
                        width: 36,
                        height: 36,
                        flexShrink: 0,
                        display: "grid",
                        placeItems: "center",
                        color: "text.muted",
                        "& svg": { fontSize: 20 },
                    }}
                >
                    {startIcon}
                </Box>
            )}
            <Box sx={{ flex: 1, minWidth: 0 }}>
                <Typography
                    sx={{
                        fontSize: 14,
                        lineHeight: "20px",
                        fontWeight: 500,
                        display: "-webkit-box",
                        WebkitBoxOrient: "vertical",
                        WebkitLineClamp: 2,
                        overflow: "hidden",
                    }}
                >
                    {title}
                </Typography>
                {description}
            </Box>
            <Box
                sx={{
                    width: 36,
                    height: 36,
                    flexShrink: 0,
                    display: "grid",
                    placeItems: "center",
                }}
            >
                {loading ? (
                    <ActivityIndicator size="20px" />
                ) : (
                    (endIcon ??
                    (selected ? (
                        <CheckIcon
                            sx={{ fontSize: 20, color: "accent.main" }}
                        />
                    ) : null))
                )}
            </Box>
        </FocusVisibleButton>
    );
}
