export const authColorVariables = {
    ":where(:root)": {
        "--photos-auth-primary": "#08c225",
        "--photos-auth-primary-hover": "#069d1e",
        "--photos-auth-primary-active": "#057c18",
        "--photos-auth-success": "#069d1e",
        "--photos-auth-warning": "#f63a3a",
        "--photos-auth-caution": "#f08a1e",
        "--photos-auth-text": "#000",
        "--photos-auth-text-muted": "#666",
        "--photos-auth-text-faint": "#969696",
        "--photos-auth-text-disabled": "#d6d6d6",
        "--photos-auth-field": "#fff",
        "--photos-auth-fill": "#eaeaea",
        "--photos-auth-fill-hover": "#dedede",
        "--photos-auth-fill-active": "#d2d2d2",
        "--photos-auth-stroke": "#e0e0e0",
    },
    "*:where(.dark)": {
        "--photos-auth-success": "#08c225",
        "--photos-auth-text": "#fff",
        "--photos-auth-text-muted": "#999",
        "--photos-auth-text-disabled": "#4d4d4d",
        "--photos-auth-field": "#1a1a1a",
        "--photos-auth-fill": "#0a0a0a",
        "--photos-auth-fill-hover": "#1a1a1a",
        "--photos-auth-fill-active": "#292929",
        "--photos-auth-stroke": "#3e3e3e",
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
    outline: "1px solid var(--photos-auth-primary)",
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
