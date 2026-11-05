import type { SxProps, Theme } from "@mui/material";

export const editorControlsSx = ((theme: Theme) => ({
    "--editor-island": "#fff",
    "--editor-fill": "#eaeaea",
    "--editor-hover": "#dedede",
    "--editor-active": "#d2d2d2",
    "--editor-secondary": "#eaeaea",
    "--editor-secondary-stroke": "transparent",
    "--editor-control-hover": "#e9e9e9",
    "--editor-disabled": "#d6d6d6",
    "--editor-control": "#fff",
    "--mui-palette-text-muted": "#666",
    "--mui-palette-divider": "#ebebeb",
    "--mui-palette-accent-main": "#08c225",
    "--mui-palette-accent-dark": "#069d1e",
    "--mui-palette-success-main": "#08c225",
    "--mui-palette-primary-main": "#08c225",
    ...theme.applyStyles("dark", {
        "--editor-island": "#212121",
        "--editor-fill": "#2b2b2b",
        "--editor-hover": "#373737",
        "--editor-active": "#3e3e3e",
        "--editor-secondary": "#2b2b2b",
        "--editor-secondary-stroke": "rgba(255,255,255,0.07)",
        "--editor-control-hover": "#373737",
        "--editor-disabled": "#4d4d4d",
        "--editor-control": "#2b2b2b",
        "--mui-palette-text-muted": "#999",
        "--mui-palette-divider": "#2a2a2a",
    }),
    backgroundColor: "var(--editor-island)",
    fontFamily: '"Inter Variable", Inter, sans-serif',
    fontSize: 14,
    fontWeight: 500,
    letterSpacing: 0,
    "& .MuiTypography-root, & .MuiButton-root, & .MuiTab-root": {
        fontFamily: "inherit",
        letterSpacing: 0,
        fontSize: 14,
        lineHeight: "20px",
    },
    "& .MuiTypography-small": { fontSize: 12, lineHeight: "16px" },
    "& .MuiTab-root": { fontWeight: 600, color: "text.muted" },
    "& .MuiTab-root.Mui-selected": { color: "text.base" },
    "& .MuiTabs-indicator": { backgroundColor: "#08c225" },
    "& .MuiDivider-root": { ml: 2, opacity: 1 },
    "& .MuiSwitch-switchBase.Mui-checked": { color: "#08c225" },
})) satisfies SxProps<Theme>;

export const editorIconButtonSx = {
    width: 38,
    height: 38,
    p: 0,
    borderRadius: "12px",
    color: "text.base",
    bgcolor: "var(--editor-control)",
    "&:hover": { bgcolor: "var(--editor-control-hover)" },
    "&.Mui-focusVisible": { outline: "1px solid #08c225", outlineOffset: 2 },
};

export const editorActionSx = (primary: boolean): SxProps<Theme> => ({
    flex: 1,
    minWidth: 0,
    height: 52,
    px: 2,
    borderRadius: "20px",
    fontSize: 14,
    fontWeight: 600,
    color: primary ? "#fff" : "text.base",
    bgcolor: primary ? "#08c225" : "var(--editor-secondary)",
    boxShadow: primary
        ? "inset 0 0 0 1px rgba(255,255,255,0.14)"
        : "inset 0 0 0 1px var(--editor-secondary-stroke)",
    transition:
        "background-color 160ms ease, transform 180ms cubic-bezier(0.22, 1, 0.36, 1)",
    "&:hover:not(:disabled)": {
        bgcolor: primary ? "#069d1e" : "var(--editor-hover)",
        transform: "translateY(-2px)",
    },
    "&:active:not(:disabled)": {
        bgcolor: primary ? "#057c18" : "var(--editor-active)",
        transform: "scale(0.985)",
    },
    "&.Mui-disabled": {
        color: "var(--editor-disabled)",
        bgcolor: "var(--editor-hover)",
        boxShadow: "none",
    },
    "&.Mui-focusVisible": { outline: "1px solid #08c225", outlineOffset: 2 },
    "@media (prefers-reduced-motion: reduce)": {
        transition: "none",
        "&:hover:not(:disabled), &:active:not(:disabled)": {
            transform: "none",
        },
    },
});
