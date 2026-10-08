import type { CSSObject, Theme } from "@mui/material/styles";

const inter =
    '"Inter Variable", Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';

const sidebarHeadingFont = '"Outfit Variable", Outfit, sans-serif';

// Keep the settings palette local, including drawers and portalled menus.
export const sidebarTheme = (theme: Theme): Theme => {
    const colors: CSSObject = {
        "--mui-palette-background-default": "#F4F4F4",
        "--mui-palette-background-paper": "#FFFFFF",
        "--mui-palette-background-paper2": "#FFFFFF",
        "--mui-palette-text-muted": "#666666",
        "--mui-palette-text-secondary": "#666666",
        "--mui-palette-text-faint": "#969696",
        "--mui-palette-fill-faint": "#F4F4F4",
        "--mui-palette-fill-fainter": "#F4F4F4",
        "--mui-palette-fill-muted": "#D2D2D2",
        "--mui-palette-fill-faintHover": "#F4F4F4",
        "--mui-palette-stroke-muted": "#E0E0E0",
        "--mui-palette-stroke-faint": "#EBEBEB",
        "--mui-palette-divider": "#EBEBEB",
        "--mui-palette-secondary-main": "#F4F4F4",
        "--mui-palette-secondary-dark": "#EAEAEA",
        "--mui-palette-primary-main": "#08C225",
        "--mui-palette-primary-mainChannel": "8 194 37",
        "--mui-palette-primary-dark": "#069D1E",
        "--mui-palette-primary-contrastText": "#FFFFFF",
        "--mui-palette-accent-main": "#08C225",
        "--mui-palette-accent-mainChannel": "8 194 37",
        "--mui-palette-accent-dark": "#069D1E",
        "--mui-palette-critical-main": "#F63A3A",
        "--mui-palette-critical-mainChannel": "246 58 58",
        "--mui-palette-critical-dark": "#DD3434",
        "--mui-palette-error-main": "#F63A3A",
        "--mui-palette-FilledInput-bg": "var(--mui-palette-background-default)",
        "--mui-palette-FilledInput-hoverBg":
            "var(--mui-palette-background-default)",
        "--mui-palette-backdrop-muted": "rgba(0, 0, 0, 0.4)",
        ...theme.applyStyles("dark", {
            "--mui-palette-background-default": "#161616",
            "--mui-palette-background-paper": "#212121",
            "--mui-palette-background-paper2": "#212121",
            "--mui-palette-text-muted": "#999999",
            "--mui-palette-text-secondary": "#999999",
            "--mui-palette-fill-faint": "#161616",
            "--mui-palette-fill-fainter": "#161616",
            "--mui-palette-fill-muted": "#292929",
            "--mui-palette-fill-faintHover": "#161616",
            "--mui-palette-stroke-muted": "#3E3E3E",
            "--mui-palette-stroke-faint": "#2A2A2A",
            "--mui-palette-divider": "#2A2A2A",
            "--mui-palette-secondary-main": "#161616",
            "--mui-palette-secondary-dark": "#0A0A0A",
        }),
        fontFamily: inter,
        "& .MuiTypography-h3:not([data-sidebar-subscription] *)": {
            fontSize: "18px",
            lineHeight: "24px",
        },
        "& .MuiTypography-small.MuiTypography-noWrap": { lineHeight: "16px" },
        "& .MuiTypography-h3 + .MuiTypography-small": {
            fontSize: "13px",
            lineHeight: "18px",
        },
        "& .MuiButton-root": { fontSize: "14px", fontWeight: 600 },
        "& .MuiButton-root:has(> .MuiStack-root):hover": {
            backgroundColor: "var(--mui-palette-background-default)",
        },
        "& .MuiInputBase-root": { fontSize: "14px" },
        "& .MuiInputBase-input::placeholder": { color: "#969696", opacity: 1 },
        "& .MuiIconButton-root:hover": {
            backgroundColor:
                "color-mix(in srgb, var(--mui-palette-text-base) 8%, var(--mui-palette-background-paper))",
        },
        "& .MuiSwitch-root": {
            "--mui-palette-primary-main":
                theme.colorSchemes.light?.palette.primary.main,
            "--mui-palette-fill-muted":
                theme.colorSchemes.light?.palette.fill.muted,
            "--mui-palette-stroke-muted":
                theme.colorSchemes.light?.palette.stroke.muted,
            "--mui-palette-stroke-faint":
                theme.colorSchemes.light?.palette.stroke.faint,
            ...theme.applyStyles("dark", {
                "--mui-palette-primary-main":
                    theme.colorSchemes.dark?.palette.primary.main,
                "--mui-palette-fill-muted":
                    theme.colorSchemes.dark?.palette.fill.muted,
                "--mui-palette-stroke-muted":
                    theme.colorSchemes.dark?.palette.stroke.muted,
                "--mui-palette-stroke-faint":
                    theme.colorSchemes.dark?.palette.stroke.faint,
            }),
        },
        "& .ente-chevron-right:not([data-sidebar-subscription] *)": {
            color: "#969696",
        },
    };

    return {
        ...theme,
        typography: {
            ...theme.typography,
            fontFamily: inter,
            fontWeightRegular: 400,
            fontWeightMedium: 500,
            h2: {
                ...theme.typography.h2,
                fontFamily: sidebarHeadingFont,
                fontSize: "24px",
                lineHeight: "32px",
                fontWeight: 600,
            },
            h3: { ...theme.typography.h3, fontFamily: inter },
            h5: {
                ...theme.typography.h5,
                fontSize: "18px",
                lineHeight: "24px",
            },
            body: {
                ...theme.typography.body,
                fontFamily: inter,
                fontSize: "14px",
                fontWeight: 400,
            },
            small: {
                ...theme.typography.small,
                fontSize: "12px",
                lineHeight: "16px",
                fontWeight: 400,
            },
            mini: {
                ...theme.typography.mini,
                lineHeight: "16px",
                fontWeight: 400,
            },
        },
        components: {
            ...theme.components,
            MuiDialog: {
                ...theme.components?.MuiDialog,
                styleOverrides: {
                    ...theme.components?.MuiDialog?.styleOverrides,
                    root: [
                        theme.components?.MuiDialog?.styleOverrides?.root,
                        colors,
                    ],
                },
            },
            MuiDrawer: {
                ...theme.components?.MuiDrawer,
                styleOverrides: {
                    ...theme.components?.MuiDrawer?.styleOverrides,
                    root: [
                        theme.components?.MuiDrawer?.styleOverrides?.root,
                        colors,
                    ],
                },
            },
            MuiPopover: {
                ...theme.components?.MuiPopover,
                styleOverrides: {
                    ...theme.components?.MuiPopover?.styleOverrides,
                    root: [
                        theme.components?.MuiPopover?.styleOverrides?.root,
                        colors,
                    ],
                },
            },
        },
    };
};
