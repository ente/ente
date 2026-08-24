import { styled } from "@mui/material";
import type React from "react";
import {
    authBodyTypography,
    authFocusRing,
    authTransientProps,
} from "./styles";

export interface TextLinkProps extends Omit<
    React.ButtonHTMLAttributes<HTMLButtonElement>,
    "color" | "children"
> {
    regular?: boolean;
    children: React.ReactNode;
}

export function TextLink({
    regular = false,
    type = "button",
    children,
    ...buttonProps
}: TextLinkProps): React.JSX.Element {
    return (
        <TextLinkRoot type={type} $regular={regular} {...buttonProps}>
            {children}
        </TextLinkRoot>
    );
}

const TextLinkRoot = styled(
    "button",
    authTransientProps,
)<{ $regular: boolean }>(({ $regular }) => ({
    ...authBodyTypography,
    display: "inline-flex",
    alignItems: "center",
    gap: "4px",
    padding: 0,
    border: 0,
    background: "transparent",
    fontFamily: "inherit",
    fontWeight: $regular ? 500 : 600,
    color: "var(--auth-app-text)",
    textDecoration: "none",
    cursor: "pointer",
    "&:hover:not(:disabled)": {
        textDecoration: "underline",
        textUnderlineOffset: "3px",
    },
    "&:focus-visible": { ...authFocusRing, borderRadius: "4px" },
    "&:disabled": {
        color: "var(--auth-app-text-disabled)",
        cursor: "not-allowed",
    },
}));
