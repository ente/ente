import type { ButtonProps } from "@mui/material";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { isSxArray } from "ente-base/components/utils/sx";
import React from "react";

export type ActionButtonType =
    | "primary"
    | "secondary"
    | "critical"
    | "tertiaryCritical"
    | "link";

interface ActionButtonProps extends Omit<ButtonProps, "color" | "variant"> {
    buttonType: ActionButtonType;
    loading?: boolean;
}

const pillSx = {
    minHeight: 52,
    borderRadius: "999px",
    px: 3,
    py: 1.5,
    fontWeight: 600,
    textTransform: "none",
    boxShadow: "none",
};

const typeSx = {
    primary: {
        ...pillSx,
        backgroundColor: "accent.main",
        color: "accent.contrastText",
        "&:hover": {
            backgroundColor: "accent.main",
            opacity: 0.92,
            boxShadow: "none",
        },
        "&.Mui-disabled": {
            backgroundColor: "fill.faint",
            color: "text.muted",
        },
    },
    secondary: {
        ...pillSx,
        backgroundColor: "fill.faint",
        color: "text.base",
        "&:hover": { backgroundColor: "fill.faintHover", boxShadow: "none" },
        "&.Mui-disabled": {
            backgroundColor: "fill.faint",
            color: "text.muted",
        },
    },
    critical: {
        ...pillSx,
        backgroundColor: "critical.main",
        color: "critical.contrastText",
        "&:hover": {
            backgroundColor: "critical.main",
            opacity: 0.92,
            boxShadow: "none",
        },
        "&.Mui-disabled": {
            backgroundColor: "fill.faint",
            color: "text.muted",
        },
    },
    tertiaryCritical: {
        minHeight: 0,
        px: 0,
        py: 0,
        borderRadius: 0,
        fontWeight: 600,
        textTransform: "none",
        color: "critical.main",
        "&:hover": { backgroundColor: "transparent", color: "critical.main" },
        "&.Mui-disabled": { color: "text.muted" },
    },
    link: {
        minHeight: 0,
        px: 0,
        py: 0,
        borderRadius: 0,
        fontWeight: 600,
        textTransform: "none",
        color: "accent.main",
        textDecoration: "underline",
        textDecorationColor: "accent.main",
        "&:hover": {
            backgroundColor: "transparent",
            color: "accent.main",
            textDecorationColor: "accent.main",
        },
        "&.Mui-disabled": {
            color: "text.muted",
            textDecorationColor: "text.muted",
        },
    },
} satisfies Record<ActionButtonType, ButtonProps["sx"]>;

const muiVariant = (buttonType: ActionButtonType): ButtonProps["variant"] =>
    buttonType === "link" || buttonType === "tertiaryCritical"
        ? "text"
        : "contained";

export const ActionButton: React.FC<ActionButtonProps> = ({
    buttonType,
    loading,
    sx,
    disableElevation = true,
    ...props
}) => (
    <LoadingButton
        {...props}
        loading={loading}
        disableElevation={disableElevation}
        variant={muiVariant(buttonType)}
        sx={[typeSx[buttonType], ...(sx ? (isSxArray(sx) ? sx : [sx]) : [])]}
    />
);
