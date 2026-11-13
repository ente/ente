import type { PaletteColor } from "@mui/material";
import React from "react";

import type {} from "@mui/material/themeCssVarsAugmentation";

declare module "@mui/material/styles" {
    interface TypeBackground {
        paper2: string;
        // First paper color elevated above default in either color scheme.
        elevatedPaper: string;
        searchInput: string;
    }

    // App code uses these instead of MUI's primary, secondary, and disabled.
    interface TypeText {
        base: string;
        muted: string;
        faint: string;
    }

    interface Palette {
        accent: PaletteColor;
        critical: PaletteColor;
        stroke: { base: string; muted: string; faint: string; fainter: string };
        fill: {
            base: string;
            muted: string;
            faint: string;
            faintHover: string;
            fainter: string;
        };
        backdrop: { base: string; muted: string; faint: string };
        fixed: {
            switchOn: string;
            dark: {
                background: Omit<TypeBackground, "elevatedPaper">;
                text: Omit<TypeText, "primary" | "secondary" | "disabled">;
                divider: string;
            };
        };
        boxShadow: { paper: string; menu: string };
    }

    interface PaletteOptions {
        accent?: Palette["accent"];
        critical?: Palette["critical"];
        stroke?: Palette["stroke"];
        fill?: Palette["fill"];
        backdrop?: Palette["backdrop"];
        fixed?: Palette["fixed"];
        boxShadow?: Palette["boxShadow"];
    }
}

declare module "@mui/material/Button" {
    interface ButtonPropsColorOverrides {
        error: false;
        success: false;
        info: false;
        warning: false;
        accent: true;
        critical: true;
    }
}

declare module "@mui/material/IconButton" {
    interface IconButtonPropsColorOverrides {
        error: false;
        success: false;
        info: false;
        warning: false;
    }
}

declare module "@mui/material/Checkbox" {
    interface CheckboxPropsColorOverrides {
        accent: true;
    }
}

declare module "@mui/material/Switch" {
    interface SwitchPropsColorOverrides {
        accent: true;
    }
}

declare module "@mui/material/SvgIcon" {
    interface SvgIconPropsColorOverrides {
        accent: true;
    }
}

declare module "@mui/material/CircularProgress" {
    interface CircularProgressPropsColorOverrides {
        accent: true;
    }
}

declare module "@mui/material/styles" {
    interface TypographyVariants {
        body: React.CSSProperties;
        small: React.CSSProperties;
        mini: React.CSSProperties;
        tiny: React.CSSProperties;
    }

    interface TypographyVariantsOptions {
        body?: React.CSSProperties;
        small?: React.CSSProperties;
        mini?: React.CSSProperties;
        tiny?: React.CSSProperties;
    }
}

declare module "@mui/material/Typography" {
    interface TypographyPropsVariantOverrides {
        subtitle1: false;
        subtitle2: false;
        body1: false;
        body2: false;
        caption: false;
        button: false;
        overline: false;
        body: true;
        small: true;
        mini: true;
        tiny: true;
    }
}
