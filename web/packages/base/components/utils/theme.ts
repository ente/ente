import type { Theme, TypographyVariantsOptions } from "@mui/material";
import { createTheme } from "@mui/material";
import type { Components } from "@mui/material/styles";
import type { AppName } from "ente-base/app";

const getTheme = (appName: AppName): Theme => {
    const colors = getColors(appName);
    const cs = getColorSchemes(colors);
    // Cast app should always be shown in dark.
    const colorSchemes =
        appName == "cast" ? { ...cs, light: cs.dark } : { ...cs };
    return createTheme({
        cssVariables: { colorSchemeSelector: "class" },
        colorSchemes,
        typography: getTypography(appName),
        components: getComponents(appName),
        shape: {
            // Increase the default border radius multiplier from 4 to 8.
            borderRadius: 8,
        },
        transitions: {
            // Increase the default transition out duration from 195 to 300.
            duration: { leavingScreen: 300 },
        },
    });
};

/**
 * [Note: Colors]
 *
 * The word "color" in MUI stands for different things. In particular, the color
 * prop for (e.g.) a Button is not the same as the color passed in the sx prop.
 *
 * There are three layers (only the first is necessary, rest are semantic):
 *
 * 1. Consider some color, say a shade of red. This will be represented by its
 *    exact CSS color value, say "#ee0000".
 *
 * 2. These can be groups of color values that have roughly the same hue, but
 *    different levels of saturation. Such hue groups are arranged together into
 *    a "Colors" exported by "@mui/material":
 *
 *        export interface Color {
 *            50: string;
 *            100: string;
 *            ...
 *            800: string;
 *            900: string;
 *            A100: string;
 *            ...
 *            A700: string;
 *        }
 *
 *  3. Finally, there are "PaletteColors" (the naming of props, and
 *     documentation within MUI (as of v6), omits the palette qualifier).
 *
 *         export interface PaletteColor {
 *             light: string;
 *             main: string;
 *             dark: string;
 *             contrastText: string;
 *         }
 *
 * The PaletteColors are what we use in the MUI component props (e.g. Button).
 * The PaletteColors are defined by providing color values for the four "tokens"
 * that make them up, either directly ("#aa000") or via Colors ("red[500]").
 *
 * Within the sx prop we need to specify a color value, which can come from the
 * palette. The "palette", as defined by the palette property we provide when
 * creating the theme, can consist of arbitrary (and nestable) key value pairs.
 *
 * Within sx prop, the "color" and "backgroundColor" props can refer to paths
 * inside this palette object. That is,
 *
 *         sx={{ color: "foo.bar" }}
 *
 * resolves to theme.vars.palette.foo.bar.
 *
 * [Note: Color names]
 *
 * When defining color names, there is some attempt at trying to use MUI v6,
 * which uses MD (Material Design) v2, nomenclature when feasible (just to keep
 * the number of concepts low), but as such, our color names should not be
 * thought of as following Material Design, and should be treated as arbitrary
 * tokens reflecting our own design system.
 *
 * Some callouts:
 *
 * - Our "primary" and "secondary" are neutral grays instead of the two-tone
 *   primary and secondary in MD. Our "accent" is corresponds to the MD primary.
 *
 * - Our "critical" is similar to and the alternative for the MD error (which is
 *   not used).
 *
 * - Two of the other default MD PaletteColors - warning, success - are used
 *   rarely, while info is not used at all.
 *
 * [Note: Theme and palette custom variables]
 *
 * Custom variables can be added to both the top level theme object, and to the
 * palette object within the theme. One would imagine that within the palette
 * there would only be colors that follow PaletteColor, but that's not something
 * MUI itself follows.
 *
 * So there is no particular reason to place custom color related variables in
 * theme vs in the palette. As a convention:
 *
 * - Custom colors (even if they're not PaletteColors) go within the palette.
 *
 * - Non-color tokens that depend on the color scheme (e.g. box shadows) also go
 *   within the palette so that they can be made color scheme specific.
 *
 * - All other custom variables remain within the top level theme.
 */
const getColors = (appName: AppName) => ({
    ..._colors,
    ...{
        fixed: {
            ..._colors.fixed,
            dark: {
                background: _colors.dark.background,
                text: _colors.dark.text,
                divider: _colors.dark.stroke.faint,
            },
        },
    },
    ...{
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
                ? _colors.accentEnsuDark
                : appName == "auth"
                  ? _colors.accentAuth
                  : appName == "share" || appName == "locker"
                    ? _colors.accentShare
                    : _colors.accentPhotos,
    },
    ...{
        accentContrastText:
            appName == "ensu" ? _colors.fixed.black : _colors.fixed.white,
    },
    ...{
        light:
            appName == "share" || appName == "locker"
                ? _colors.lightShare
                : appName == "ensu"
                  ? _colors.lightEnsu
                  : _colors.light,
    },
    ...{
        dark:
            appName == "share" || appName == "locker"
                ? _colors.darkShare
                : appName == "ensu"
                  ? _colors.darkEnsu
                  : _colors.dark,
    },
});

/**
 * The color values.
 *
 * Use this arbitrarily shaped object to define the palette. This avoid
 * duplication across color schemes, and also helps see if there are any
 * reusable colors.
 */
const _colors = {
    accentPhotos: { dark: "#00b33c", main: "#1db954", light: "#01de4d" },
    accentAuth: { dark: "#8e0fcb", main: "#9610d6", light: "#8e2de2" },
    accentShare: { dark: "#0056CC", main: "#1071FF", light: "#1071FF" },
    accentEnsu: { dark: "#f5d93a", main: "#f5d93a", light: "#f5d93a" },
    accentEnsuDark: { dark: "#f5d93a", main: "#f5d93a", light: "#f5d93a" },
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
            button: "0px 4px 4px rgba(0 0 0 / 0.25)",
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
            button: "0px 4px 4px rgba(0 0 0 / 0.18)",
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
            button: "0px 4px 4px rgba(0 0 0 / 0.75)",
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
            button: "0px 4px 4px rgba(0 0 0 / 0.75)",
        },
    },
    light: {
        // Keep these solid.
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
        // MUI (as of v6.4) doesn't like it if we specify a non-solid color for
        // primary.main or secondary.main, or don't specify it using the #nnnnnn
        // notation; it seems to mess with the derivation of the color channels.
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
            button: "0px 4px 4px rgba(0 0 0 / 0.25)",
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
            button: "0px 4px 4px rgba(0 0 0 / 0.75)",
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
                // Alias the tokens used by MUI to the ones that we use. This way,
                // we don't need to change the default ("primary"), or update the
                // MUI internal styling that refers to these tokens.
                //
                // Our own code should not use these.
                primary: colors.light.text.base,
                secondary: colors.light.text.muted,
                disabled: colors.light.text.faint,
                // Our color tokens.
                base: colors.light.text.base,
                muted: colors.light.text.muted,
                faint: colors.light.text.faint,
            },
            fill: colors.light.fill,
            stroke: colors.light.stroke,
            divider: colors.light.stroke.faint,
            fixed: colors.fixed,
            boxShadow: colors.light.boxShadow,
            // Override some MUI defaults for styling action elements like
            // buttons and menu items.
            //
            // Nb: There are more where these came from, currently those don't
            // affect us, but in the future they might.
            //
            // https://github.com/mui/material-ui/blob/v6.4.0/packages/mui-material/src/styles/createPalette.js#L68
            action: {
                // The color of an active action like an icon button.
                active: colors.light.stroke.base,
                // The color of an hovered action.
                hover: colors.light.fill.faintHover,
                // For an icon button, the hover background color is derived
                // from the active color above and this opacity. Use a value
                // that results in the same result as faintHover.
                hoverOpacity: 0.08,
                // The color of a disabled action.
                disabled: colors.light.text.faint,
                // The background color of a disabled action.
                disabledBackground: colors.light.fill.faint,
            },
            // Override some internal MUI defaults that impact the components
            // which we use.
            //
            // https://github.com/mui/material-ui/blob/v6.4.0/packages/mui-material/src/styles/createThemeWithVars.js#L271
            FilledInput: {
                bg: colors.light.fill.faint,
                hoverBg: colors.light.fill.faintHover,
                // While we don't specifically have disabled inputs, TextInputs
                // do get disabled when the form is submitting, and this value
                // comes into play then.
                disabledBg: colors.light.fill.fainter,
            },
        },
    },
    // -- See the light mode section for comments
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
            // -- See the light mode section for comments
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

/**
 * [Note: Font weights]
 *
 * We only use three font weights:
 *
 * - 500 (sx "regular")
 * - 600 (sx "medium")
 * - 700 (sx "bold", CSS "bold")
 *
 * While the sx prop allows us to use keywords "regular", "medium" and "bold",
 * which we do elsewhere in the code, within this file those keywords cannot be
 * used in all contexts because they instead map to the CSS keywords. To avoid
 * any confusion, within this file we only use the numeric values.
 *
 * ---
 *
 * MUI (as of v6) uses the following font weights by default:
 *
 * - fontWeightLight 300
 * - fontWeightRegular 400
 * - fontWeightMedium 500
 * - fontWeightBold 700
 *
 * The browser default (CSS keyword "normal"), is also 400.
 *
 * However for Inter, the font that we use, 400 is too light, and to improve
 * legibility we change fontWeightRegular to 500.
 *
 * Correspondingly, we shift fontWeightMedium to 600. fontWeightBold then ends
 * up mapping back to 700, which also nicely coincides with the CSS keyword
 * "bold".
 *
 * MUI uses fontWeightLight only as the default font weight for the h1 and h2
 * variants, but we override their font weight in our theme. Thus we don't need
 * to bother with the light variant (though for consistency of specifying every
 * value, we alias it the same weight as regular, 500).
 */
const baseTypography: TypographyVariantsOptions = {
    fontFamily: '"Inter Variable", sans-serif',
    fontWeightLight: 500,
    fontWeightRegular: 500 /* CSS baseline reset sets this as the default */,
    fontWeightMedium: 600,
    fontWeightBold: 700,
    h1: { fontSize: "48px", lineHeight: "58px", fontWeight: 600 /* Medium */ },
    h2: {
        fontSize: "32px",
        lineHeight: "39px",
        fontWeight: 500 /* Reset to regular to override MUI's default theme */,
    },
    h3: { fontSize: "24px", lineHeight: "29px", fontWeight: 600 /* Medium */ },
    h4: {
        fontSize: "22px",
        lineHeight: "27px",
        fontWeight: 500 /* Reset to regular to override MUI's default theme */,
    },
    h5: { fontSize: "20px", lineHeight: "25px", fontWeight: 600 /* Medium */ },
    // h6 is the default variant used by MUI's DialogTitle.
    h6: {
        // The font size and line height below is the same as large.
        fontSize: "18px",
        lineHeight: "22px",
        fontWeight: 600 /* Medium */,
    },
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
            // Ensu-specific variants (type-augmented in web/apps/ensu/src/types).
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

// Use the base typography for component style overrides (Button sizing, etc.).
const typography = baseTypography;

/**
 * > [!NOTE]
 * >
 * > The theme isn't tree-shakeable, prefer creating new components for heavy
 * > customization.
 * >
 * > https://mui.com/material-ui/customization/theme-components/
 */
const components: Components = {
    MuiCssBaseline: {
        styleOverrides: {
            body: {
                // MUI has different letter spacing for each variant, but those
                // are values arrived at for the default Material font, and
                // don't work for the font that we're using.
                //
                // So we reset the letter spacing for _all_ variants to a
                // reasonable value that works for our font.
                letterSpacing: "-0.011em",
            },
        },
    },

    MuiTypography: {
        defaultProps: {
            // MUI has body1 as the default variant for Typography, but our
            // variant scheme is different, instead of body1/2, we have
            // large/body/small etc. So reset the default to our equivalent of
            // body1, which is "body".
            variant: "body",
            // Map all our custom variants to <p>.
            variantMapping: { body: "p", small: "p", mini: "p", tiny: "p" },
        },
    },

    MuiModal: {
        styleOverrides: {
            root: {
                // A workaround to prevent stuck modals from blocking clicks.
                // https://github.com/mui/material-ui/issues/32286#issuecomment-1287951109
                '&:has(> div[style*="opacity: 0"])': { pointerEvents: "none" },
            },
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
            // [Note: Workarounds for unactionable ARIA warnings]
            //
            // This is required to prevent console warnings about aria-hiding a
            // focused button when the dialog is closed. e.g. Select a file,
            // delete it. On closing the confirmation dialog, the error appears.
            //
            // The default is supposed to already be false, but setting this
            // again seems to help. But sometimes we need to set this to `true`
            // to prevent the warning. And sometimes neither helps, and we need
            // to add random setTimeouts.
            //
            // Angular, Bootstrap, MUI, shadcn: all seem to be emitting these
            // warning (just search the web). I'm don't know if this is just
            // someone at Chrome deciding to emit spurious warnings without
            // understanding the flow, or if none of these libraries have
            // managed to implement the ARIA spec properly yet (which says more
            // about the spec than about the libraries).
            //
            // - https://issues.chromium.org/issues/392121909
            // - https://github.com/mui/material-ui/issues/43106#issuecomment-2314809028
            closeAfterTransition: false,
        },
        styleOverrides: {
            root: {
                ".MuiBackdrop-root": {
                    backgroundColor: "var(--mui-palette-backdrop-muted)",
                },
                // Reset the MUI default paddings to 16px everywhere.
                //
                // This is not a great choice either, usually most dialogs, for
                // one reason or the other, will need to customize this padding
                // anyway. But not resetting it to 16px leaves it at the MUI
                // defaults, which just doesn't work well with our designs.
                "& .MuiDialogTitle-root": {
                    // MUI default is '16px 24px'.
                    padding: "16px",
                },
                "& .MuiDialogContent-root": {
                    // MUI default is '20px 24px'.
                    padding: "16px",
                    // If the contents of the dialog's contents exceed the
                    // available height, show a scrollbar just for the contents
                    // instead of the entire dialog.
                    overflowY: "auto",
                },
                "& .MuiDialogActions-root": {
                    // MUI default is way off for us since they cluster the
                    // buttons to the right, while our designs usually want the
                    // buttons to align with the heading / content.
                    padding: "16px",
                },
                ".MuiDialogTitle-root + .MuiDialogContent-root": {
                    // MUI resets this to 0 when the content doesn't use
                    // dividers (none of ours do). I feel that is a better
                    // default, since unlike margins, padding doesn't collapse,
                    // but changing this now would break existing layouts.
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
                        // Use our "paper" shadow for elevated Paper.
                        props: { variant: "elevation" },
                        style: {
                            // MUI applies a semi-transparent background image
                            // for elevation in dark mode. Remove it to match
                            // background for our designs.
                            backgroundImage: "none",
                            // Use our paper shadow.
                            boxShadow: "var(--mui-palette-boxShadow-paper)",
                        },
                    },
                    {
                        // Undo the effects of variant "elevation" case above
                        // case when elevation is 0.
                        props: { elevation: 0 },
                        style: { boxShadow: "none" },
                    },
                ],
            },
        },
    },

    // The default link "color" prop is "primary", which maps to "fill.base"
    // (and equivalently, to "text.base"). In our current designs, the <Link>
    // MUI component is only used in places where the surrounding text uses
    // "text.muted", so this default already provides it a highlight compared to
    // the text it in embedded in.
    //
    // We additionally disable the underline, and add a hover indication by
    // switching its color to the main accent.
    MuiLink: {
        defaultProps: { underline: "none" },
        styleOverrides: {
            root: { "&:hover": { color: "var(--mui-palette-accent-main)" } },
        },
    },

    MuiButton: {
        defaultProps: {
            // Change the default button variant from "text" to "contained".
            variant: "contained",
            // Disable shadows.
            disableElevation: true,
        },
        styleOverrides: {
            // We don't use the size prop for the MUI button, or rather it
            // cannot be used, since we have fixed the paddings and font sizes
            // unconditionally here (which is all that the size prop changes).
            root: {
                padding: "12px 16px",
                borderRadius: "4px",
                textTransform: "none",
                // Body, but medium.
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
                // Give a symmetric border to the input field, by default the
                // border radius is only applied to the top for the "filled"
                // variant of input used inside TextFields.
                borderRadius: "8px",
                // Clip the bottom border so that there is no gap between the
                // filled area and the (full width) border.
                overflow: "hidden",
                // Hide the bottom border that always appears for the "filled"
                // variant of input used inside TextFields.
                "::before": { borderBottom: "none !important" },
            },
        },
    },

    MuiTextField: {
        defaultProps: {
            // The MUI default variant is "outlined", override it to use the
            // "filled" one by default.
            variant: "filled",
            // Reduce the vertical margins that MUI adds to the TextField.
            //
            // Note that this causes things to be too tight when the helper text
            // is shown, so this is not recommended for new code that we write.
            margin: "dense",
        },
        styleOverrides: {
            root: { "& .MuiInputAdornment-root": { marginRight: "8px" } },
        },
    },

    MuiCheckbox: {
        defaultProps: {
            // Disable the ripple effect for all checkboxes.
            disableRipple: true,
        },
        styleOverrides: {
            // Since we've disabled the ripple, add other affordances to it (a
            // background and outline) to clearly indicate whenever it gains
            // keyboard focus.
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

    MuiSnackbar: {
        styleOverrides: {
            root: {
                // Set a default border radius for all snackbar's (e.g.
                // notification popups).
                borderRadius: "8px",
            },
        },
    },

    MuiAlert: {
        defaultProps: {
            // Use the outlined variant by default (instead of "standard").
            variant: "outlined",
        },
    },
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

// Exports ---

/**
 * The MUI {@link Theme} to use for the photos app.
 *
 * This is also the "default" theme, in that it is used for the accounts app
 * which serves both photos and auth.
 */
export const photosTheme = getTheme("photos");

/**
 * The MUI {@link Theme} to use for the auth app.
 */
export const authTheme = getTheme("auth");

/**
 * The MUI {@link Theme} to use for the cast app.
 *
 * This is the same as the dark theme for the photos app.
 */
export const castTheme = getTheme("cast");

/**
 * The MUI {@link Theme} to use for the Ensu app.
 */
export const ensuTheme = getTheme("ensu");

/**
 * The MUI {@link Theme} to use for the locker public app.
 */
export const shareTheme = getTheme("share");

/** Theme for the locker app (blue accent, matching mobile Locker app). */
export const lockerTheme = getTheme("locker");
