"use client";

import {
    ChevronDownIcon,
    CloseIcon,
    ErrorIcon,
    InfoIcon,
    SuccessIcon,
    WarningIcon,
} from "@/components/icons";
import { createTheme } from "@mui/material/styles";
import { createElement } from "react";

import { accentGreen, accentGreenHover } from "./buttons";
import { uiColors } from "./colors";

const theme = createTheme({
    palette: {
        mode: "dark",
        primary: {
            main: accentGreen,
            dark: accentGreenHover,
            contrastText: "#ffffff",
        },
        secondary: { main: "#1E6D1D" },
        background: { default: uiColors.background, paper: uiColors.surface },
        text: { primary: uiColors.text, secondary: uiColors.muted },
        divider: uiColors.border,
        action: {
            active: uiColors.text,
            hover: "rgba(233,237,239,0.06)",
            selected: "rgba(233,237,239,0.1)",
            disabled: "rgba(233,237,239,0.3)",
            disabledBackground: uiColors.control,
        },
        error: { main: uiColors.danger },
    },
    typography: {
        fontFamily: "var(--font-inter), sans-serif",
        h1: { fontFamily: "var(--font-inter), sans-serif", fontWeight: 800 },
        h2: { fontFamily: "var(--font-inter), sans-serif", fontWeight: 700 },
        h3: { fontFamily: "var(--font-inter), sans-serif", fontWeight: 700 },
        h4: { fontFamily: "var(--font-inter), sans-serif" },
        body1: { fontFamily: "var(--font-inter), sans-serif" },
        body2: { fontFamily: "var(--font-inter), sans-serif" },
        button: {
            fontFamily: "var(--font-inter), sans-serif",
            fontWeight: 700,
            textTransform: "none",
        },
    },
    shape: { borderRadius: 8 },
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
});

export default theme;
