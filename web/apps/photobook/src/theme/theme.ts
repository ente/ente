import {
    ChevronDownIcon,
    CloseIcon,
    ErrorIcon,
    InfoIcon,
    SuccessIcon,
    WarningIcon,
} from "@/components/icons";
import { createTheme, type ThemeOptions } from "@mui/material/styles";
import { shareTheme } from "ente-base/components/utils/theme";
import { createElement } from "react";

import { accentGreen, accentGreenHover } from "./buttons";
import { uiColors } from "./colors";

const darkPalette = shareTheme.colorSchemes.dark!.palette;

const overrides: ThemeOptions = {
    palette: {
        mode: "dark",
        primary: {
            main: accentGreen,
            dark: accentGreenHover,
            contrastText: "#ffffff",
        },
        secondary: { main: "#1E6D1D" },
        background: {
            ...darkPalette.background,
            default: uiColors.background,
            paper: uiColors.surface,
        },
        text: {
            ...darkPalette.text,
            primary: uiColors.text,
            secondary: uiColors.muted,
            base: uiColors.text,
            muted: uiColors.muted,
        },
        divider: uiColors.border,
        action: {
            ...darkPalette.action,
            active: uiColors.text,
            hover: "rgba(233,237,239,0.06)",
            selected: "rgba(233,237,239,0.1)",
            disabled: "rgba(233,237,239,0.3)",
            disabledBackground: uiColors.control,
        },
        error: { main: uiColors.danger },
    },
    components: {
        MuiPaper: { styleOverrides: { root: { backgroundImage: "none" } } },
        MuiSelect: { defaultProps: { IconComponent: ChevronDownIcon } },
        MuiAlert: {
            defaultProps: {
                iconMapping: {
                    success: createElement(SuccessIcon, {
                        fontSize: "inherit",
                    }),
                    info: createElement(InfoIcon, { fontSize: "inherit" }),
                    warning: createElement(WarningIcon, {
                        fontSize: "inherit",
                    }),
                    error: createElement(ErrorIcon, { fontSize: "inherit" }),
                },
                slots: { closeIcon: CloseIcon },
            },
        },
        MuiButton: {
            styleOverrides: {
                root: { borderRadius: 999, padding: "10px 24px" },
            },
            variants: [
                {
                    props: { variant: "contained", color: "primary" },
                    style: {
                        backgroundColor: accentGreen,
                        backgroundImage: "none",
                        boxShadow: "none",
                        "&.Mui-disabled": {
                            backgroundColor: accentGreen,
                            color: "#FFFFFF",
                            opacity: 0.45,
                        },
                        "&:hover": {
                            backgroundColor: accentGreenHover,
                            boxShadow: "none",
                        },
                    },
                },
            ],
        },
    },
};

const theme = createTheme(
    {
        cssVariables: { colorSchemeSelector: "class" },
        defaultColorScheme: "dark",
        colorSchemes: {
            light: false,
            dark: { palette: { ...darkPalette, ...overrides.palette } },
        },
        typography: shareTheme.typography,
        shape: shareTheme.shape,
        transitions: shareTheme.transitions,
        components: shareTheme.components,
    },
    { components: overrides.components },
);

export default theme;
