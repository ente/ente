import { Add01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, ButtonBase, Typography } from "@mui/material";
import { t } from "i18next";
import React from "react";

interface CollectionChipRowItem {
    key: string;
    label: string;
    selected: boolean;
    onClick: () => void;
}

export const CollectionChipRow: React.FC<{
    items: CollectionChipRowItem[];
    createOpen: boolean;
    disabled?: boolean;
    onCreateClick?: () => void;
}> = ({ items, createOpen, disabled, onCreateClick }) => {
    return (
        <Box>
            <Typography
                variant="small"
                sx={{
                    fontWeight: 600,
                    lineHeight: "20px",
                    mb: "8px",
                    display: "block",
                }}
            >
                {t("collections")}
            </Typography>
            <Box sx={{ display: "flex", flexWrap: "wrap", gap: "12px 8px" }}>
                {onCreateClick && (
                    <ButtonBase
                        onClick={onCreateClick}
                        disabled={disabled}
                        sx={(theme) => ({
                            minHeight: 42,
                            maxWidth: "100%",
                            minWidth: 0,
                            px: "16px",
                            py: "8px",
                            gap: "6px",
                            borderRadius: "16px",
                            border: `1px dashed ${theme.vars.palette.stroke.muted}`,
                            color: theme.vars.palette.text.muted,
                            backgroundColor: createOpen
                                ? theme.vars.palette.background.paper
                                : "transparent",
                            "&:hover": {
                                backgroundColor:
                                    theme.vars.palette.fill.faintHover,
                            },
                            "&.Mui-disabled": {
                                backgroundColor:
                                    theme.vars.palette.fill.faintHover,
                                color: theme.vars.palette.text.faint,
                            },
                        })}
                    >
                        <Box sx={{ display: "flex", flexShrink: 0 }}>
                            <HugeiconsIcon
                                icon={Add01Icon}
                                size={18}
                                strokeWidth={1.5}
                            />
                        </Box>
                        <Typography
                            variant="small"
                            noWrap
                            sx={{ fontWeight: 500, lineHeight: "20px" }}
                        >
                            {t("collection")}
                        </Typography>
                    </ButtonBase>
                )}
                {items.map((item) => (
                    <ButtonBase
                        key={item.key}
                        title={item.label}
                        onClick={item.onClick}
                        disabled={disabled}
                        sx={(theme) => ({
                            minHeight: 44,
                            maxWidth: "100%",
                            minWidth: 0,
                            px: "20px",
                            py: "12px",
                            borderRadius: "16px",
                            backgroundColor: item.selected
                                ? theme.vars.palette.accent.main
                                : theme.vars.palette.background.paper,
                            color: item.selected
                                ? theme.vars.palette.accent.contrastText
                                : theme.vars.palette.text.muted,
                            transition: "background-color 0.15s",
                            "&:hover": {
                                backgroundColor: item.selected
                                    ? theme.vars.palette.accent.dark
                                    : theme.vars.palette.fill.faintHover,
                            },
                            "&.Mui-disabled": {
                                backgroundColor: item.selected
                                    ? theme.vars.palette.accent.main
                                    : theme.vars.palette.fill.faintHover,
                                color: item.selected
                                    ? theme.vars.palette.accent.contrastText
                                    : theme.vars.palette.text.faint,
                            },
                        })}
                    >
                        <Typography
                            variant="small"
                            noWrap
                            sx={{ fontWeight: 500, lineHeight: "20px" }}
                        >
                            {item.label}
                        </Typography>
                    </ButtonBase>
                ))}
            </Box>
        </Box>
    );
};
