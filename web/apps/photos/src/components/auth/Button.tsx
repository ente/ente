import { CircularProgress, styled } from "@mui/material";
import type React from "react";
import {
    authBodyTypography,
    authFocusRing,
    authTransientProps,
} from "./styles";

export type ButtonVariant = "primary" | "secondary";

export interface ButtonProps extends Omit<
    React.ButtonHTMLAttributes<HTMLButtonElement>,
    "color" | "children"
> {
    variant?: ButtonVariant;
    fullWidth?: boolean;
    loading?: boolean;
    loadingMessage?: React.ReactNode;
    children: React.ReactNode;
}

export function Button({
    variant = "primary",
    fullWidth = false,
    loading = false,
    loadingMessage,
    disabled,
    type = "button",
    children,
    ...buttonProps
}: ButtonProps): React.JSX.Element {
    return (
        <ButtonRoot
            type={type}
            disabled={disabled || loading}
            aria-busy={loading || undefined}
            $variant={variant}
            $fullWidth={fullWidth}
            $loading={loading}
            {...buttonProps}
        >
            {loading && loadingMessage ? (
                <LoadingContent>
                    <CircularProgress size={20} color="inherit" />
                    <span>{loadingMessage}</span>
                </LoadingContent>
            ) : (
                <>
                    <ButtonLabel $loading={loading}>{children}</ButtonLabel>
                    {loading && <CircularProgress size={20} color="inherit" />}
                </>
            )}
        </ButtonRoot>
    );
}

interface ButtonRootProps {
    $variant: ButtonVariant;
    $fullWidth: boolean;
    $loading: boolean;
}

const ButtonRoot = styled(
    "button",
    authTransientProps,
)<ButtonRootProps>(({ $variant, $fullWidth, $loading }) => ({
    ...authBodyTypography,
    width: $fullWidth ? "100%" : "auto",
    height: "52px",
    padding: "14px 24px",
    border: 0,
    borderRadius: "20px",
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    position: "relative",
    boxSizing: "border-box",
    fontFamily: "inherit",
    color: $variant === "primary" ? "#fff" : "var(--photos-auth-text)",
    backgroundColor:
        $variant === "primary"
            ? "var(--photos-auth-primary)"
            : "var(--photos-auth-button-secondary)",
    boxShadow:
        $variant === "primary"
            ? "inset 0 0 0 1px var(--photos-auth-button-primary-stroke)"
            : "inset 0 0 0 1px var(--photos-auth-button-secondary-stroke)",
    cursor: $loading ? "default" : "pointer",
    transition:
        "background-color 160ms ease, box-shadow 160ms ease, transform 180ms cubic-bezier(0.22, 1, 0.36, 1)",
    "&:hover:not(:disabled)": {
        backgroundColor:
            $variant === "primary"
                ? "var(--photos-auth-primary-hover)"
                : "var(--photos-auth-button-secondary-hover)",
        boxShadow:
            $variant === "primary"
                ? "inset 0 0 0 1px var(--photos-auth-button-primary-stroke-hover)"
                : "inset 0 0 0 1px var(--photos-auth-button-secondary-stroke-hover)",
        transform: "translateY(-2px)",
    },
    "&:active:not(:disabled)": {
        backgroundColor:
            $variant === "primary"
                ? "var(--photos-auth-primary-active)"
                : "var(--photos-auth-button-secondary-active)",
        boxShadow:
            $variant === "primary"
                ? "inset 0 0 0 1px var(--photos-auth-button-primary-stroke-active)"
                : "inset 0 0 0 1px var(--photos-auth-button-secondary-stroke-active)",
        transform: "translateY(0) scale(0.985)",
    },
    "&:focus-visible": authFocusRing,
    "&:disabled": $loading
        ? { cursor: "default" }
        : {
              color: "var(--photos-auth-text-disabled)",
              backgroundColor: "var(--photos-auth-fill-hover)",
              boxShadow: "none",
              cursor: "not-allowed",
          },
    "& > .MuiCircularProgress-root": { position: "absolute" },
    "@media (prefers-reduced-motion: reduce)": {
        transition: "background-color 120ms ease",
        "&:hover:not(:disabled), &:active:not(:disabled)": {
            transform: "none",
        },
    },
}));

const ButtonLabel = styled(
    "span",
    authTransientProps,
)<{ $loading: boolean }>(({ $loading }) => ({ opacity: $loading ? 0 : 1 }));

const LoadingContent = styled("span")({
    minWidth: 0,
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    gap: "8px",
    whiteSpace: "nowrap",
    "& > .MuiCircularProgress-root": { flexShrink: 0 },
});
