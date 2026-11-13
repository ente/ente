import { HugeiconsIcon } from "@hugeicons/react";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import { Box, Typography } from "@mui/material";
import React from "react";
import {
    bodyBoldSx,
    bodySx,
    largeSx,
    miniSx,
    rowSurfaceSx,
    selectedRowSx,
    textBaseSx,
    textLightSx,
    warningSx,
} from "./locker-sidebar-styles";

interface LockerSidebarCardButtonProps {
    icon?: React.ComponentProps<typeof HugeiconsIcon>["icon"];
    iconNode?: React.ReactNode;
    label: React.ReactNode;
    onClick: () => void;
    endIcon?: React.ReactNode;
    selected?: boolean;
    color?: "warning";
    subtitle?: string;
    half?: boolean;
    disabled?: boolean;
}

export const LockerSidebarCardButton: React.FC<
    LockerSidebarCardButtonProps
> = ({
    icon,
    iconNode,
    label,
    onClick,
    endIcon,
    selected = false,
    color,
    subtitle,
    half,
    disabled = false,
}) => (
    <Box
        component="button"
        type="button"
        disabled={disabled}
        onClick={onClick}
        sx={[
            rowSurfaceSx,
            {
                width: "100%",
                minHeight: 54,
                p: "9px 12px",
                m: 0,
                border: 0,
                display: "flex",
                alignItems: "center",
                gap: 1.5,
                textAlign: "left",
                cursor: "pointer",
                "&:disabled": { cursor: "default", opacity: 0.5 },
                borderRadius: "20px",
                "&:focus-visible": {
                    outline: "2px solid",
                    outlineColor: "accent.main",
                    outlineOffset: 2,
                },
            },
            ...(half ? [{ flex: 1, minWidth: 0 }] : []),
            ...(selected ? [selectedRowSx] : []),
        ]}
    >
        {(iconNode || icon) && (
            <Box
                sx={[
                    textLightSx,
                    {
                        width: 36,
                        height: 36,
                        flexShrink: 0,
                        display: "grid",
                        placeItems: "center",
                    },
                    ...(color === "warning" ? [warningSx] : []),
                    ...(selected ? [{ "&&": { color: "accent.main" } }] : []),
                ]}
            >
                {iconNode ?? (
                    <HugeiconsIcon
                        icon={icon!}
                        size={18}
                        strokeWidth={1.6}
                        color="currentColor"
                    />
                )}
            </Box>
        )}
        <Box sx={{ flex: 1, minWidth: 0 }}>
            <Typography
                component="div"
                noWrap
                sx={[
                    bodySx,
                    textBaseSx,
                    ...(color === "warning" ? [warningSx] : []),
                    ...(selected
                        ? [{ "&&": { color: "accent.main" }, fontWeight: 600 }]
                        : []),
                ]}
            >
                {label}
            </Typography>
            {subtitle && (
                <Typography
                    sx={[
                        miniSx,
                        textLightSx,
                        {
                            mt: 0.5,
                            display: "-webkit-box",
                            WebkitLineClamp: 2,
                            WebkitBoxOrient: "vertical",
                            overflow: "hidden",
                        },
                    ]}
                >
                    {subtitle}
                </Typography>
            )}
        </Box>
        {!half && endIcon && (
            <Box
                sx={[
                    textLightSx,
                    {
                        width: 36,
                        height: 36,
                        flexShrink: 0,
                        display: "grid",
                        placeItems: "center",
                        "& svg": { fontSize: 24 },
                    },
                    ...(selected ? [{ "&&": { color: "accent.main" } }] : []),
                ]}
            >
                {endIcon}
            </Box>
        )}
    </Box>
);

export const LockerSidebarSectionTitle: React.FC<React.PropsWithChildren> = ({
    children,
}) => (
    <Typography sx={[largeSx, textBaseSx, { p: "6px 0 6px 8px" }]}>
        {children}
    </Typography>
);

export const LockerSidebarLink: React.FC<
    React.PropsWithChildren<{ onClick: () => void }>
> = ({ children, onClick }) => (
    <Box
        component="button"
        type="button"
        onClick={onClick}
        sx={{
            ...bodyBoldSx,
            color: "accent.main",
            p: "12px 8px",
            alignSelf: "flex-start",
            display: "flex",
            alignItems: "center",
            gap: 1,
            border: 0,
            background: "transparent",
            cursor: "pointer",
            "&:focus-visible": { outline: "2px solid", outlineOffset: 2 },
        }}
    >
        {children}
        <ChevronRightIcon sx={{ fontSize: 16 }} />
    </Box>
);
