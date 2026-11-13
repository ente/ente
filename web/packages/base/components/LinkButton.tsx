import { Link, type ButtonProps } from "@mui/material";
import React from "react";

export const LinkButton: React.FC<
    React.PropsWithChildren<Pick<ButtonProps, "onClick">>
> = ({ onClick, children }) => (
    <Link
        component="button"
        sx={(theme) => ({
            color: "text.base",
            textDecoration: "underline",
            // Palette shorthand does not resolve for textDecorationColor.
            textDecorationColor: theme.vars.palette.text.faint,
            "&:hover": {
                color: "accent.main",
                textDecoration: "underline",
                textDecorationColor: "accent.main",
            },
        })}
        {...{ onClick }}
    >
        {children}
    </Link>
);

export const LinkButtonUndecorated: React.FC<
    React.PropsWithChildren<Pick<ButtonProps, "onClick">>
> = ({ onClick, children }) => (
    <Link
        component="button"
        sx={{
            textDecoration: "none",
            color: "text.muted",
            fontWeight: "medium",
            "&:hover": { color: "accent.main" },
        }}
        {...{ onClick }}
    >
        {children}
    </Link>
);
