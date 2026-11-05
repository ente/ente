import type { SxProps, Theme } from "@mui/material";

export const editorControlsSx = ((theme: Theme) => ({
    "--editor-fill": "#eaeaea",
    "--editor-hover": "#dedede",
    "--editor-active": "#d2d2d2",
    "--editor-secondary": "var(--editor-fill)",
    "--editor-secondary-stroke": "transparent",
    "--editor-control-hover": theme.vars.palette.secondary.dark,
    "--editor-disabled": "#d6d6d6",
    "--editor-control": theme.vars.palette.fixed.white,
    "--mui-palette-text-muted": "#666",
    "--mui-palette-divider": "#ebebeb",
    "--mui-palette-accent-main": "#08c225",
    "--mui-palette-accent-dark": "#069d1e",
    "--mui-palette-success-main": "#08c225",
    "--mui-palette-primary-main": "#08c225",
    ...theme.applyStyles("dark", {
        "--editor-fill": theme.vars.palette.secondary.main,
        "--editor-hover": theme.vars.palette.secondary.dark,
        "--editor-active": "#3e3e3e",
        "--editor-secondary-stroke": "rgba(255,255,255,0.07)",
        "--editor-disabled": "#4d4d4d",
        "--editor-control": theme.vars.palette.secondary.main,
        "--mui-palette-text-muted": "#999",
        "--mui-palette-divider": "#2a2a2a",
    }),
    backgroundColor: "background.default",
    fontFamily: theme.typography.fontFamily,
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
    "& .MuiTabs-indicator": { backgroundColor: "accent.main" },
    "& .MuiDivider-root": { ml: 2, opacity: 1 },
    "& .MuiSwitch-switchBase.Mui-checked": { color: "accent.main" },
})) satisfies SxProps<Theme>;

export const editorIconButtonSx = {
    width: 38,
    height: 38,
    p: 0,
    borderRadius: "12px",
    color: "text.base",
    bgcolor: "var(--editor-control)",
    "&:hover": { bgcolor: "var(--editor-control-hover)" },
    "&.Mui-focusVisible": {
        outline: "1px solid var(--mui-palette-accent-main)",
        outlineOffset: 2,
    },
};

export const editorActionSx = (primary: boolean): SxProps<Theme> => ({
    flex: 1,
    minWidth: 0,
    height: 52,
    px: 2,
    borderRadius: "20px",
    fontSize: 14,
    fontWeight: 600,
    color: primary ? "fixed.white" : "text.base",
    bgcolor: primary ? "accent.main" : "var(--editor-secondary)",
    boxShadow: primary
        ? "inset 0 0 0 1px rgba(255,255,255,0.14)"
        : "inset 0 0 0 1px var(--editor-secondary-stroke)",
    transition:
        "background-color 160ms ease, transform 180ms cubic-bezier(0.22, 1, 0.36, 1)",
    "&:hover:not(:disabled)": {
        bgcolor: primary ? "accent.dark" : "var(--editor-hover)",
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
    "&.Mui-focusVisible": {
        outline: "1px solid var(--mui-palette-accent-main)",
        outlineOffset: 2,
    },
    "@media (prefers-reduced-motion: reduce)": {
        transition: "none",
        "&:hover:not(:disabled), &:active:not(:disabled)": {
            transform: "none",
        },
    },
});
