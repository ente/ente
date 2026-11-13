import type { CSSProperties } from "react";

declare module "@mui/material/styles" {
    interface TypographyVariants {
        message: CSSProperties;
        code: CSSProperties;
    }

    interface TypographyVariantsOptions {
        message?: CSSProperties;
        code?: CSSProperties;
    }
}

declare module "@mui/material/Typography" {
    interface TypographyPropsVariantOverrides {
        message: true;
        code: true;
    }
}
