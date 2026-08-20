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
            : "var(--photos-auth-fill)",
    cursor: $loading ? "default" : "pointer",
    transition: "background-color 120ms ease",
    "&:hover:not(:disabled)": {
        backgroundColor:
            $variant === "primary"
                ? "var(--photos-auth-primary-hover)"
                : "var(--photos-auth-fill-hover)",
    },
    "&:active:not(:disabled)": {
        backgroundColor:
            $variant === "primary"
                ? "var(--photos-auth-primary-active)"
                : "var(--photos-auth-fill-active)",
    },
    "&:focus-visible": authFocusRing,
    "&:disabled": $loading
        ? { cursor: "default" }
        : {
              color: "var(--photos-auth-text-disabled)",
              backgroundColor: "var(--photos-auth-fill-hover)",
              cursor: "not-allowed",
          },
    "& > .MuiCircularProgress-root": { position: "absolute" },
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
