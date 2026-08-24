export const authColorVariables = {
    ":where(:root)": {
        "--auth-app-primary": "#9610d6",
        "--auth-app-accent": "#9610d6",
        "--auth-app-primary-hover": "#8e0fcb",
        "--auth-app-primary-active": "#750ca8",
        "--auth-app-success": "#069d1e",
        "--auth-app-warning": "#f63a3a",
        "--auth-app-caution": "#f08a1e",
        "--auth-app-text": "#000",
        "--auth-app-text-muted": "#666",
        "--auth-app-text-faint": "#969696",
        "--auth-app-text-disabled": "#d6d6d6",
        "--auth-app-field": "#fff",
        "--auth-app-fill": "#eaeaea",
        "--auth-app-fill-hover": "#dedede",
        "--auth-app-fill-active": "#d2d2d2",
        "--auth-app-stroke": "#e0e0e0",
        "--auth-app-button-secondary": "#eaeaea",
        "--auth-app-button-secondary-hover": "#dedede",
        "--auth-app-button-secondary-active": "#d2d2d2",
        "--auth-app-button-secondary-stroke": "transparent",
        "--auth-app-button-secondary-stroke-hover": "transparent",
        "--auth-app-button-secondary-stroke-active": "transparent",
        "--auth-app-button-primary-stroke": "rgba(255, 255, 255, 0.14)",
        "--auth-app-button-primary-stroke-hover": "rgba(255, 255, 255, 0.32)",
        "--auth-app-button-primary-stroke-active": "rgba(255, 255, 255, 0.2)",
    },
    "*:where(.dark)": {
        "--auth-app-accent": "#c76cff",
        "--auth-app-success": "#08c225",
        "--auth-app-text": "#fff",
        "--auth-app-text-muted": "#999",
        "--auth-app-text-disabled": "#808080",
        "--auth-app-field": "#1a1a1a",
        "--auth-app-fill": "#0a0a0a",
        "--auth-app-fill-hover": "#1a1a1a",
        "--auth-app-fill-active": "#292929",
        "--auth-app-stroke": "#3e3e3e",
        "--auth-app-button-secondary": "#1e1e1e",
        "--auth-app-button-secondary-hover": "#1a1a1a",
        "--auth-app-button-secondary-active": "#161616",
        "--auth-app-button-secondary-stroke": "rgba(255, 255, 255, 0.07)",
        "--auth-app-button-secondary-stroke-hover": "rgba(255, 255, 255, 0.18)",
        "--auth-app-button-secondary-stroke-active":
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
    outline: "1px solid var(--auth-app-accent)",
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
