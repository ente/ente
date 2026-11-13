export interface AuthPresentationConfig {
    primary: string;
    primaryHover: string;
    primaryActive: string;
    focus: string;
    focusDark: string;
    link: string;
    linkDark: string;
    termsLink: string;
    termsLinkDark: string;
    passwordMessage: string;
    passwordMessageDark: string;
    textDisabledDark: string;
    wideGamutPrimary?: string;
    mobileBrandHeight: number;
    illustrationHeights: {
        desktop: number;
        tablet: number;
        mobile: number;
        wide: number;
    };
}

export const createAuthColorVariables = (theme: AuthPresentationConfig) => ({
    ":where(:root)": {
        "--auth-ui-primary": theme.primary,
        "--auth-ui-primary-hover": theme.primaryHover,
        "--auth-ui-primary-active": theme.primaryActive,
        "--auth-ui-focus": theme.focus,
        "--auth-ui-link": theme.link,
        "--auth-ui-terms-link": theme.termsLink,
        "--auth-ui-password-message": theme.passwordMessage,
        "--auth-ui-success": "#069d1e",
        "--auth-ui-warning": "#f63a3a",
        "--auth-ui-caution": "#f08a1e",
        "--auth-ui-text": "#000",
        "--auth-ui-text-muted": "#666",
        "--auth-ui-text-faint": "#969696",
        "--auth-ui-text-disabled": "#d6d6d6",
        "--auth-ui-field": "#fff",
        "--auth-ui-fill": "#eaeaea",
        "--auth-ui-fill-hover": "#dedede",
        "--auth-ui-fill-active": "#d2d2d2",
        "--auth-ui-stroke": "#e0e0e0",
        "--auth-ui-button-secondary": "#eaeaea",
        "--auth-ui-button-secondary-hover": "#dedede",
        "--auth-ui-button-secondary-active": "#d2d2d2",
        "--auth-ui-button-secondary-stroke": "transparent",
        "--auth-ui-button-secondary-stroke-hover": "transparent",
        "--auth-ui-button-secondary-stroke-active": "transparent",
        "--auth-ui-button-primary-stroke": "rgba(255, 255, 255, 0.14)",
        "--auth-ui-button-primary-stroke-hover": "rgba(255, 255, 255, 0.32)",
        "--auth-ui-button-primary-stroke-active": "rgba(255, 255, 255, 0.2)",
    },
    "*:where(.dark)": {
        "--auth-ui-focus": theme.focusDark,
        "--auth-ui-link": theme.linkDark,
        "--auth-ui-terms-link": theme.termsLinkDark,
        "--auth-ui-password-message": theme.passwordMessageDark,
        "--auth-ui-success": "#08c225",
        "--auth-ui-text": "#fff",
        "--auth-ui-text-muted": "#999",
        "--auth-ui-text-disabled": theme.textDisabledDark,
        "--auth-ui-field": "#1a1a1a",
        "--auth-ui-fill": "#0a0a0a",
        "--auth-ui-fill-hover": "#1a1a1a",
        "--auth-ui-fill-active": "#292929",
        "--auth-ui-stroke": "#3e3e3e",
        "--auth-ui-button-secondary": "#1e1e1e",
        "--auth-ui-button-secondary-hover": "#1a1a1a",
        "--auth-ui-button-secondary-active": "#161616",
        "--auth-ui-button-secondary-stroke": "rgba(255, 255, 255, 0.07)",
        "--auth-ui-button-secondary-stroke-hover": "rgba(255, 255, 255, 0.18)",
        "--auth-ui-button-secondary-stroke-active": "rgba(255, 255, 255, 0.12)",
    },
});

const authMobileCutoffPx = 640;
export const authMobileMediaQuery = `@media (max-width: ${authMobileCutoffPx - 0.05}px)`;
export const authAboveMobileMediaQuery = `@media (min-width: ${authMobileCutoffPx}px)`;

export const authTransientProps = {
    shouldForwardProp: (prop: string) => !prop.startsWith("$"),
};

export const authDisplayFontFamily = '"Outfit Variable", sans-serif';

export const authFocusRing = {
    outline: "1px solid var(--auth-ui-focus)",
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
