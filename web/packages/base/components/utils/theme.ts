import type { Theme, TypographyVariantsOptions } from "@mui/material";
import { createTheme } from "@mui/material";
import type { Components } from "@mui/material/styles";
import type { AppName } from "ente-base/app";

const getTheme = (appName: AppName): Theme => {
    const colors = getColors(appName);
    const cs = getColorSchemes(colors);
    const colorSchemes =
        appName == "cast" ? { ...cs, light: cs.dark } : { ...cs };
    return createTheme({
        cssVariables: { colorSchemeSelector: "class" },
        colorSchemes,
        typography: getTypography(appName),
        components: getComponents(appName),
        shape: { borderRadius: 8 },
        transitions: { duration: { leavingScreen: 300 } },
    });
};

const getColors = (appName: AppName) => ({
    ..._colors,
    fixed: {
        ..._colors.fixed,
        dark: {
            background: _colors.dark.background,
            text: _colors.dark.text,
            divider: _colors.dark.stroke.faint,
        },
    },
    accent:
        appName == "auth"
            ? _colors.accentAuth
            : appName == "share" || appName == "locker"
              ? _colors.accentShare
              : appName == "ensu"
                ? _colors.accentEnsu
                : _colors.accentPhotos,
    accentDark:
        appName == "ensu"
            ? _colors.accentEnsu
            : appName == "auth"
              ? _colors.accentAuth
              : appName == "share" || appName == "locker"
                ? _colors.accentShare
                : _colors.accentPhotos,
    accentContrastText:
        appName == "ensu" ? _colors.fixed.black : _colors.fixed.white,
    light:
        appName == "share" || appName == "locker"
            ? _colors.lightShare
            : appName == "ensu"
              ? _colors.lightEnsu
              : _colors.light,
    dark:
        appName == "share" || appName == "locker"
            ? _colors.darkShare
            : appName == "ensu"
              ? _colors.darkEnsu
              : _colors.dark,
});

const _colors = {
    accentPhotos: { dark: "#00b33c", main: "#1db954", light: "#01de4d" },
    accentAuth: { dark: "#8e0fcb", main: "#9610d6", light: "#8e2de2" },
    accentShare: { dark: "#0056CC", main: "#1071FF", light: "#1071FF" },
    accentEnsu: { dark: "#f5d93a", main: "#f5d93a", light: "#f5d93a" },
    fixed: {
        white: "#fff",
        black: "#000",
        success: "#1db954",
        golden: "#ffc107",
        danger: { dark: "#f53434", main: "#ea3f3f", light: "#ff6565" },
        switchOn: "#2eca45",
    },
    lightShare: {
        background: {
            default: "#FAFAFA",
            paper: "#fff",
            paper2: "#fbfbfb",
            searchInput: "#f3f3f3",
        },
        backdrop: {
            base: "rgba(255 255 255 / 0.92)",
            muted: "rgba(255 255 255 / 0.75)",
            faint: "rgba(255 255 255 / 0.30)",
        },
        text: {
            base: "#000",
            muted: "rgba(0 0 0 / 0.60)",
            faint: "rgba(0 0 0 / 0.50)",
        },
        fill: {
            base: "#000",
            muted: "rgba(0 0 0 / 0.12)",
            faint: "rgba(0 0 0 / 0.04)",
            faintHover: "rgba(0 0 0 / 0.08)",
            fainter: "rgba(0 0 0 / 0.02)",
        },
        secondary: { main: "#f5f5f5", hover: "#e9e9e9" },
        stroke: {
            base: "#000",
            muted: "rgba(0 0 0 / 0.24)",
            faint: "rgba(0 0 0 / 0.12)",
            fainter: "rgba(0 0 0 / 0.06)",
        },
        boxShadow: {
            paper: "0px 0px 10px rgba(0 0 0 / 0.25)",
            menu: "0px 0px 6px rgba(0 0 0 / 0.16), 0px 3px 6px rgba(0 0 0 / 0.12)",
        },
    },
    lightEnsu: {
        background: {
            default: "#F8F5F0",
            paper: "#F8F5F0",
            paper2: "#FFFDF8",
            searchInput: "#F0EBE4",
        },
        backdrop: {
            base: "rgba(248 245 240 / 0.92)",
            muted: "rgba(248 245 240 / 0.75)",
            faint: "rgba(248 245 240 / 0.30)",
        },
        text: {
            base: "#1A1A1A",
            muted: "#8A8680",
            faint: "rgba(138 134 128 / 0.50)",
        },
        fill: {
            base: "#1A1A1A",
            muted: "rgba(26 26 26 / 0.12)",
            faint: "#F0EBE4",
            faintHover: "#E7E1D8",
            fainter: "#F8F5F0",
        },
        secondary: { main: "#F0EBE4", hover: "#E7E1D8" },
        stroke: {
            base: "#1A1A1A",
            muted: "rgba(26 26 26 / 0.24)",
            faint: "#D4D0C8",
            fainter: "rgba(26 26 26 / 0.06)",
        },
        boxShadow: {
            paper: "0px 0px 10px rgba(0 0 0 / 0.18)",
            menu: "0px 0px 6px rgba(0 0 0 / 0.14), 0px 3px 6px rgba(0 0 0 / 0.10)",
        },
    },
    darkShare: {
        background: {
            default: "#161616",
            paper: "#212121",
            paper2: "#252525",
            searchInput: "#212121",
        },
        backdrop: {
            base: "rgba(0 0 0 / 0.90)",
            muted: "rgba(0 0 0 / 0.65)",
            faint: "rgba(0 0 0 / 0.20)",
        },
        text: {
            base: "#fff",
            muted: "rgba(255 255 255 / 0.70)",
            faint: "rgba(255 255 255 / 0.50)",
        },
        fill: {
            base: "#fff",
            muted: "rgba(255 255 255 / 0.16)",
            faint: "rgba(255 255 255 / 0.12)",
            faintHover: "rgba(255 255 255 / 0.16)",
            fainter: "rgba(255 255 255 / 0.05)",
        },
        secondary: { main: "#2b2b2b", hover: "#373737" },
        stroke: {
            base: "#fff",
            muted: "rgba(255 255 255 / 0.24)",
            faint: "rgba(255 255 255 / 0.16)",
            fainter: "rgba(255 255 255 / 0.12)",
        },
        boxShadow: {
            paper: "0px 2px 12px rgba(0 0 0 / 0.75)",
            menu: "0px 0px 6px rgba(0 0 0 / 0.50), 0px 3px 6px rgba(0 0 0 / 0.25)",
        },
    },
    darkEnsu: {
        background: {
            default: "#141414",
            paper: "#1E1E1E",
            paper2: "#1E1E1E",
            searchInput: "#1E1E1E",
        },
        backdrop: {
            base: "rgba(20 20 20 / 0.90)",
            muted: "rgba(20 20 20 / 0.65)",
            faint: "rgba(20 20 20 / 0.20)",
        },
        text: {
            base: "#E8E4DF",
            muted: "#777777",
            faint: "rgba(119 119 119 / 0.50)",
        },
        fill: {
            base: "#E8E4DF",
            muted: "rgba(232 228 223 / 0.16)",
            faint: "#1E1E1E",
            faintHover: "#2A2A2A",
            fainter: "#141414",
        },
        secondary: { main: "#1E1E1E", hover: "#2A2A2A" },
        stroke: {
            base: "#E8E4DF",
            muted: "rgba(232 228 223 / 0.24)",
            faint: "#2A2A2A",
            fainter: "rgba(232 228 223 / 0.12)",
        },
        boxShadow: {
            paper: "0px 2px 12px rgba(0 0 0 / 0.75)",
            menu: "0px 0px 6px rgba(0 0 0 / 0.50), 0px 3px 6px rgba(0 0 0 / 0.25)",
        },
    },
    light: {
        background: {
            default: "#fff",
            paper: "#fff",
            paper2: "#fbfbfb",
            searchInput: "#f3f3f3",
        },
        backdrop: {
            base: "rgba(255 255 255 / 0.92)",
            muted: "rgba(255 255 255 / 0.75)",
            faint: "rgba(255 255 255 / 0.30)",
        },
        text: {
            base: "#000",
            muted: "rgba(0 0 0 / 0.60)",
            faint: "rgba(0 0 0 / 0.50)",
        },
        fill: {
            base: "#000",
            muted: "rgba(0 0 0 / 0.12)",
            faint: "rgba(0 0 0 / 0.04)",
            faintHover: "rgba(0 0 0 / 0.08)",
            fainter: "rgba(0 0 0 / 0.02)",
        },
        secondary: { main: "#f5f5f5", hover: "#e9e9e9" },
        stroke: {
            base: "#000",
            muted: "rgba(0 0 0 / 0.24)",
            faint: "rgba(0 0 0 / 0.12)",
            fainter: "rgba(0 0 0 / 0.06)",
        },
        boxShadow: {
            paper: "0px 0px 10px rgba(0 0 0 / 0.25)",
            menu: "0px 0px 6px rgba(0 0 0 / 0.16), 0px 3px 6px rgba(0 0 0 / 0.12)",
        },
    },
    dark: {
        background: {
            default: "#000",
            paper: "#1b1b1b",
            paper2: "#252525",
            searchInput: "#1b1b1b",
        },
        backdrop: {
            base: "rgba(0 0 0 / 0.90)",
            muted: "rgba(0 0 0 / 0.65)",
            faint: "rgba(0 0 0 / 0.20)",
        },
        text: {
            base: "#fff",
            muted: "rgba(255 255 255 / 0.70)",
            faint: "rgba(255 255 255 / 0.50)",
        },
        fill: {
            base: "#fff",
            muted: "rgba(255 255 255 / 0.16)",
            faint: "rgba(255 255 255 / 0.12)",
            faintHover: "rgba(255 255 255 / 0.16)",
            fainter: "rgba(255 255 255 / 0.05)",
        },
        secondary: { main: "#2b2b2b", hover: "#373737" },
        stroke: {
            base: "#fff",
            muted: "rgba(255 255 255 / 0.24)",
            faint: "rgba(255 255 255 / 0.16)",
            fainter: "rgba(255 255 255 / 0.12)",
        },
        boxShadow: {
            paper: "0px 2px 12px rgba(0 0 0 / 0.75)",
            menu: "0px 0px 6px rgba(0 0 0 / 0.50), 0px 3px 6px rgba(0 0 0 / 0.25)",
        },
    },
};

const getColorSchemes = (colors: ReturnType<typeof getColors>) => ({
    light: {
        palette: {
            background: {
                ...colors.light.background,
                elevatedPaper: colors.light.background.paper2,
            },
            backdrop: colors.light.backdrop,
            // MUI derives color channels only from solid #rrggbb values here.
            primary: {
                main: colors.fixed.black,
                contrastText: colors.fixed.white,
            },
            secondary: {
                main: colors.light.secondary.main,
                dark: colors.light.secondary.hover,
                contrastText: colors.light.text.base,
            },
            success: { main: colors.fixed.success },
            warning: { main: colors.fixed.golden },
            accent: {
                main: colors.accent.main,
                dark: colors.accent.dark,
                light: colors.accent.light,
                contrastText: colors.accentContrastText,
            },
            critical: {
                main: colors.fixed.danger.main,
                dark: colors.fixed.danger.dark,
                light: colors.fixed.danger.light,
                contrastText: colors.fixed.white,
            },
            text: {
                // These aliases are for MUI internals; app code uses the tokens below.
                primary: colors.light.text.base,
                secondary: colors.light.text.muted,
                disabled: colors.light.text.faint,
                base: colors.light.text.base,
                muted: colors.light.text.muted,
                faint: colors.light.text.faint,
            },
            fill: colors.light.fill,
            stroke: colors.light.stroke,
            divider: colors.light.stroke.faint,
            fixed: colors.fixed,
            boxShadow: colors.light.boxShadow,
            action: {
                active: colors.light.stroke.base,
                hover: colors.light.fill.faintHover,
                hoverOpacity: 0.08,
                disabled: colors.light.text.faint,
                disabledBackground: colors.light.fill.faint,
            },
            FilledInput: {
                bg: colors.light.fill.faint,
                hoverBg: colors.light.fill.faintHover,
                disabledBg: colors.light.fill.fainter,
            },
        },
    },
    dark: {
        palette: {
            background: {
                ...colors.dark.background,
                elevatedPaper: colors.dark.background.paper,
            },
            backdrop: colors.dark.backdrop,
            primary: {
                main: colors.fixed.white,
                contrastText: colors.fixed.black,
            },
            secondary: {
                main: colors.dark.secondary.main,
                dark: colors.dark.secondary.hover,
                contrastText: colors.dark.text.base,
            },
            success: { main: colors.fixed.success },
            warning: { main: colors.fixed.golden },
            accent: {
                main: colors.accentDark.main,
                dark: colors.accentDark.dark,
                light: colors.accentDark.light,
                contrastText: colors.accentContrastText,
            },
            critical: {
                main: colors.fixed.danger.main,
                dark: colors.fixed.danger.dark,
                light: colors.fixed.danger.light,
                contrastText: colors.fixed.white,
            },
            text: {
                primary: colors.dark.text.base,
                secondary: colors.dark.text.muted,
                disabled: colors.dark.text.faint,
                base: colors.dark.text.base,
                muted: colors.dark.text.muted,
                faint: colors.dark.text.faint,
            },
            fill: colors.dark.fill,
            stroke: colors.dark.stroke,
            divider: colors.dark.stroke.faint,
            fixed: colors.fixed,
            boxShadow: colors.dark.boxShadow,
            action: {
                active: colors.dark.stroke.base,
                hover: colors.dark.fill.faintHover,
                hoverOpacity: 0.16,
                disabled: colors.dark.text.faint,
                disabledBackground: colors.dark.fill.faint,
            },
            FilledInput: {
                bg: colors.dark.fill.faint,
                hoverBg: colors.dark.fill.faintHover,
                disabledBg: colors.dark.fill.fainter,
            },
        },
    },
});

const baseTypography: TypographyVariantsOptions = {
    fontFamily: '"Inter Variable", sans-serif',
    fontWeightLight: 500,
    fontWeightRegular: 500,
    fontWeightMedium: 600,
    fontWeightBold: 700,
    h1: { fontSize: "48px", lineHeight: "58px", fontWeight: 600 },
    h2: { fontSize: "32px", lineHeight: "39px", fontWeight: 500 },
    h3: { fontSize: "24px", lineHeight: "29px", fontWeight: 600 },
    h4: { fontSize: "22px", lineHeight: "27px", fontWeight: 500 },
    h5: { fontSize: "20px", lineHeight: "25px", fontWeight: 600 },
    h6: { fontSize: "18px", lineHeight: "22px", fontWeight: 600 },
    body: { fontSize: "16px", lineHeight: "20px" },
    small: { fontSize: "14px", lineHeight: "17px" },
    mini: { fontSize: "12px", lineHeight: "15px" },
    tiny: { fontSize: "10px", lineHeight: "12px" },
};

const getTypography = (appName: AppName): TypographyVariantsOptions => {
    if (appName === "ensu") {
        return {
            ...baseTypography,
            fontFamily:
                '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
            message: { fontSize: "15px", lineHeight: "1.7", fontWeight: 400 },
            code: {
                fontSize: "13px",
                lineHeight: "1.45",
                fontWeight: 400,
                fontFamily:
                    'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace',
            },
        } as TypographyVariantsOptions;
    }
    return baseTypography;
};

const typography = baseTypography;

// Theme overrides are bundled into every app; keep heavy customization local.
const components: Components = {
    MuiCssBaseline: { styleOverrides: { body: { letterSpacing: "-0.011em" } } },

    MuiTypography: {
        defaultProps: {
            variant: "body",
            variantMapping: { body: "p", small: "p", mini: "p", tiny: "p" },
        },
    },

    MuiDrawer: {
        styleOverrides: {
            root: {
                ".MuiBackdrop-root": {
                    backgroundColor: "var(--mui-palette-backdrop-muted)",
                },
            },
        },
    },

    MuiDialog: {
        defaultProps: {
            // The explicit value suppresses aria-hidden focus warnings on close.
            closeAfterTransition: false,
        },
        styleOverrides: {
            root: {
                ".MuiBackdrop-root": {
                    backgroundColor: "var(--mui-palette-backdrop-muted)",
                },
                "& .MuiDialogTitle-root": { padding: "16px" },
                "& .MuiDialogContent-root": {
                    padding: "16px",
                    overflowY: "auto",
                },
                "& .MuiDialogActions-root": { padding: "16px" },
                ".MuiDialogTitle-root + .MuiDialogContent-root": {
                    paddingTop: "16px",
                },
            },
        },
    },

    MuiPaper: {
        styleOverrides: {
            root: {
                variants: [
                    {
                        props: { variant: "elevation" },
                        style: {
                            backgroundImage: "none",
                            boxShadow: "var(--mui-palette-boxShadow-paper)",
                        },
                    },
                    { props: { elevation: 0 }, style: { boxShadow: "none" } },
                ],
            },
        },
    },

    MuiLink: {
        defaultProps: { underline: "none" },
        styleOverrides: {
            root: { "&:hover": { color: "var(--mui-palette-accent-main)" } },
        },
    },

    MuiButton: {
        defaultProps: { variant: "contained", disableElevation: true },
        styleOverrides: {
            root: {
                padding: "12px 16px",
                borderRadius: "4px",
                textTransform: "none",
                fontSize: typography.body?.fontSize,
                lineHeight: typography.body?.lineHeight,
                fontWeight: 600,
            },
            startIcon: { marginRight: "12px", "&& >svg": { fontSize: "20px" } },
            endIcon: { marginLeft: "12px", "&& >svg": { fontSize: "20px" } },
        },
    },

    MuiInputBase: {
        styleOverrides: {
            formControl: {
                borderRadius: "8px",
                overflow: "hidden",
                "::before": { borderBottom: "none !important" },
            },
        },
    },

    MuiTextField: {
        defaultProps: {
            variant: "filled",
            // Dense margins are too tight with helper text; override them there.
            margin: "dense",
        },
        styleOverrides: {
            root: { "& .MuiInputAdornment-root": { marginRight: "8px" } },
        },
    },

    MuiCheckbox: {
        defaultProps: { disableRipple: true },
        styleOverrides: {
            root: {
                "&.Mui-focusVisible": {
                    backgroundColor: "var(--mui-palette-fill-faint)",
                    outline: "1px solid var(--mui-palette-stroke-faint)",
                },
            },
        },
    },

    MuiSvgIcon: {
        styleOverrides: {
            root: {
                variants: [
                    {
                        props: { color: "primary" },
                        style: { color: "var(--mui-palette-stroke-base)" },
                    },
                    {
                        props: { color: "secondary" },
                        style: { color: "var(--mui-palette-stroke-muted)" },
                    },
                ],
            },
        },
    },

    MuiIconButton: {
        styleOverrides: {
            root: {
                padding: "12px",
                variants: [
                    {
                        props: { color: "primary" },
                        style: { color: "var(--mui-palette-stroke-base)" },
                    },
                    {
                        props: { color: "secondary" },
                        style: { color: "var(--mui-palette-stroke-muted)" },
                    },
                ],
                "&.Mui-disabled": { color: "var(--mui-palette-stroke-faint)" },
            },
        },
    },

    MuiMenu: {
        styleOverrides: {
            root: {
                ".MuiMenu-paper": {
                    boxShadow: "var(--mui-palette-boxShadow-menu)",
                },
            },
        },
    },

    MuiSnackbar: { styleOverrides: { root: { borderRadius: "8px" } } },

    MuiAlert: { defaultProps: { variant: "outlined" } },
};

const getComponents = (appName: AppName): Components => {
    if (appName !== "ensu" && appName !== "locker") return components;

    const muiButtonStyleOverrides = (components.MuiButton?.styleOverrides ??
        {}) as Record<string, unknown>;
    const muiButtonRootStyleOverrides =
        (muiButtonStyleOverrides.root as Record<string, unknown> | undefined) ??
        {};
    const muiIconButtonStyleOverrides = (components.MuiIconButton
        ?.styleOverrides ?? {}) as Record<string, unknown>;
    const muiIconButtonRootStyleOverrides =
        (muiIconButtonStyleOverrides.root as
            | Record<string, unknown>
            | undefined) ?? {};
    const muiInputBaseStyleOverrides = (components.MuiInputBase
        ?.styleOverrides ?? {}) as Record<string, unknown>;
    const muiInputBaseFormControlStyleOverrides =
        (muiInputBaseStyleOverrides.formControl as
            | Record<string, unknown>
            | undefined) ?? {};
    const muiDialogTitleStyleOverrides = (components.MuiDialogTitle
        ?.styleOverrides ?? {}) as Record<string, unknown>;
    const muiDialogContentStyleOverrides = (components.MuiDialogContent
        ?.styleOverrides ?? {}) as Record<string, unknown>;

    if (appName === "locker") {
        return {
            ...components,
            MuiButton: {
                ...components.MuiButton,
                styleOverrides: {
                    ...muiButtonStyleOverrides,
                    root: {
                        ...muiButtonRootStyleOverrides,
                        borderRadius: "20px",
                    },
                },
            },
            MuiIconButton: {
                ...components.MuiIconButton,
                styleOverrides: {
                    ...muiIconButtonStyleOverrides,
                    root: {
                        ...muiIconButtonRootStyleOverrides,
                        borderRadius: "18px",
                    },
                },
            },
            MuiInputBase: {
                ...components.MuiInputBase,
                styleOverrides: {
                    ...muiInputBaseStyleOverrides,
                    formControl: {
                        ...muiInputBaseFormControlStyleOverrides,
                        borderRadius: "16px",
                    },
                },
            },
            MuiOutlinedInput: {
                ...components.MuiOutlinedInput,
                styleOverrides: {
                    ...components.MuiOutlinedInput?.styleOverrides,
                    root: {
                        ...(components.MuiOutlinedInput?.styleOverrides
                            ?.root as Record<string, unknown> | undefined),
                        borderRadius: "16px",
                    },
                },
            },
            MuiFilledInput: {
                ...components.MuiFilledInput,
                styleOverrides: {
                    ...components.MuiFilledInput?.styleOverrides,
                    root: {
                        ...(components.MuiFilledInput?.styleOverrides?.root as
                            | Record<string, unknown>
                            | undefined),
                        borderRadius: "16px",
                    },
                },
            },
            MuiDialogTitle: {
                ...components.MuiDialogTitle,
                styleOverrides: {
                    ...muiDialogTitleStyleOverrides,
                    root: {
                        ...(muiDialogTitleStyleOverrides.root as
                            | Record<string, unknown>
                            | undefined),
                        paddingBottom: "12px",
                    },
                },
            },
            MuiDialogContent: {
                ...components.MuiDialogContent,
                styleOverrides: {
                    ...muiDialogContentStyleOverrides,
                    root: {
                        ...(muiDialogContentStyleOverrides.root as
                            | Record<string, unknown>
                            | undefined),
                        paddingTop: "8px",
                    },
                },
            },
        };
    }

    return {
        ...components,
        MuiTypography: {
            ...components.MuiTypography,
            defaultProps: {
                ...components.MuiTypography?.defaultProps,
                variantMapping: {
                    ...components.MuiTypography?.defaultProps?.variantMapping,
                    message: "p",
                    code: "code",
                } as Record<string, string>,
            },
        },
        MuiButton: {
            ...components.MuiButton,
            styleOverrides: {
                ...muiButtonStyleOverrides,
                root: { ...muiButtonRootStyleOverrides, borderRadius: "16px" },
            },
        },
    };
};

export const photosTheme = getTheme("photos");

export const authTheme = getTheme("auth");

export const castTheme = getTheme("cast");

export const ensuTheme = getTheme("ensu");

export const shareTheme = getTheme("share");

export const lockerTheme = getTheme("locker");
