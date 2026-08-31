export const authColorVariables = {
    ":where(:root)": {
        "--locker-auth-primary": "#1071ff",
        "--locker-auth-primary-hover": "#0056cc",
        "--locker-auth-primary-active": "#004db8",
        "--locker-auth-success": "#069d1e",
        "--locker-auth-warning": "#f63a3a",
        "--locker-auth-caution": "#f08a1e",
        "--locker-auth-text": "#000",
        "--locker-auth-text-muted": "#666",
        "--locker-auth-text-faint": "#969696",
        "--locker-auth-text-disabled": "#d6d6d6",
        "--locker-auth-field": "#fff",
        "--locker-auth-fill": "#eaeaea",
        "--locker-auth-fill-hover": "#dedede",
        "--locker-auth-fill-active": "#d2d2d2",
        "--locker-auth-stroke": "#e0e0e0",
        "--locker-auth-button-secondary": "#eaeaea",
        "--locker-auth-button-secondary-hover": "#dedede",
        "--locker-auth-button-secondary-active": "#d2d2d2",
        "--locker-auth-button-secondary-stroke": "transparent",
        "--locker-auth-button-secondary-stroke-hover": "transparent",
        "--locker-auth-button-secondary-stroke-active": "transparent",
        "--locker-auth-button-primary-stroke": "rgba(255, 255, 255, 0.14)",
        "--locker-auth-button-primary-stroke-hover":
            "rgba(255, 255, 255, 0.32)",
        "--locker-auth-button-primary-stroke-active":
            "rgba(255, 255, 255, 0.2)",
    },
    "*:where(.dark)": {
        "--locker-auth-success": "#08c225",
        "--locker-auth-text": "#fff",
        "--locker-auth-text-muted": "#999",
        "--locker-auth-text-disabled": "#4d4d4d",
        "--locker-auth-field": "#1a1a1a",
        "--locker-auth-fill": "#0a0a0a",
        "--locker-auth-fill-hover": "#1a1a1a",
        "--locker-auth-fill-active": "#292929",
        "--locker-auth-stroke": "#3e3e3e",
        "--locker-auth-button-secondary": "#1e1e1e",
        "--locker-auth-button-secondary-hover": "#1a1a1a",
        "--locker-auth-button-secondary-active": "#161616",
        "--locker-auth-button-secondary-stroke": "rgba(255, 255, 255, 0.07)",
        "--locker-auth-button-secondary-stroke-hover":
            "rgba(255, 255, 255, 0.18)",
        "--locker-auth-button-secondary-stroke-active":
            "rgba(255, 255, 255, 0.12)",
    },
};

const authMobileCutoffPx = 640;
export const authMobileMediaQuery = `@media (max-width: ${authMobileCutoffPx - 0.05}px)`;
export const authAboveMobileMediaQuery = `@media (min-width: ${authMobileCutoffPx}px)`;

export const authTransientProps = {
    shouldForwardProp: (prop: string) => !prop.startsWith("$"),
};

export const authDisplayFontFamily = '"Outfit Variable", sans-serif';

export const authFocusRing = {
    outline: "1px solid var(--locker-auth-primary)",
    outlineOffset: "2px",
};

export const authBodyTypography = {
    fontSize: "14px",
    fontWeight: 500,
    lineHeight: "20px",
};

export const authMiniTypography = {
    fontSize: "12px",
    fontWeight: 500,
    lineHeight: "16px",
};

export const authDialogContentLayout = {
    display: "flex",
    flexDirection: "column",
    gap: "24px",
    [authMobileMediaQuery]: { gap: "20px" },
} as const;
