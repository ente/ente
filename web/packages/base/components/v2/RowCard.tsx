import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import { Box, Stack, Typography } from "@mui/material";
import { EnteSwitch } from "ente-base/components/EnteSwitch";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import React from "react";

type RowCardProps = {
    variant?: "default" | "parent";
    title: React.ReactNode;
    subtitle?: string;
} & (
    | { onClick?: () => void; endIcon?: React.ReactNode; toggle?: never }
    | {
          onClick?: never;
          endIcon?: never;
          toggle: { checked: boolean; onChange: () => void };
      }
);

export const RowCard: React.FC<RowCardProps> = ({
    variant = "default",
    title,
    subtitle,
    onClick,
    toggle,
    endIcon = <ChevronRightIcon className="ente-chevron-right" />,
}) => (
    <Box
        component={toggle ? "label" : onClick ? FocusVisibleButton : "div"}
        onClick={onClick}
        sx={[
            {
                display: "flex",
                width: "100%",
                p: "14px 8px",
                gap: 1,
                justifyContent: "space-between",
                alignItems: "center",
                textAlign: "left",
                borderRadius: "10px",
                color: "text.base",
                bgcolor: "transparent",
                cursor: onClick || toggle ? "pointer" : undefined,
                "&:hover": {
                    bgcolor: onClick || toggle ? "fill.faintHover" : undefined,
                },
                "& .MuiSvgIcon-root": { fontSize: "20px", color: "text.muted" },
            },
            variant == "parent" && {
                px: 2,
                m: 0.5,
                width: "calc(100% - 8px)",
                borderRadius: 2,
            },
            !!toggle &&
                ((theme) => ({
                    "&:has(:focus-visible)": {
                        outline: `1px solid ${theme.vars.palette.stroke.base}`,
                        outlineOffset: "2px",
                    },
                })),
            (theme) =>
                theme.applyStyles("dark", {
                    "&:hover": {
                        bgcolor:
                            onClick || toggle
                                ? variant == "parent"
                                    ? "fill.faintHover"
                                    : "backdrop.muted"
                                : undefined,
                    },
                }),
        ]}
    >
        <Stack component="span" sx={{ minWidth: 0 }}>
            <Typography component="span" noWrap sx={{ fontWeight: "medium" }}>
                {title}
            </Typography>
            {subtitle && (
                <Typography
                    component="span"
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
        {toggle ? <EnteSwitch {...toggle} sx={{ flexShrink: 0 }} /> : endIcon}
    </Box>
);
