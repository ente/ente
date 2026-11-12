import type { SxProps, Theme } from "@mui/material";

export const editorControlsSx = ((theme: Theme) => ({
    backgroundColor: "background.paper",
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
    bgcolor: "secondary.main",
    "&:hover": { bgcolor: "secondary.dark" },
    "&.Mui-focusVisible": {
        outline: "1px solid var(--mui-palette-accent-main)",
        outlineOffset: 2,
    },
};

export const editorActionSx = (primary: boolean): SxProps<Theme> => ({
    width: "100%",
    height: 52,
    px: 1,
    borderRadius: "20px",
    fontSize: 14,
    fontWeight: 600,
    color: primary ? "common.white" : "text.base",
    bgcolor: primary ? "accent.main" : "secondary.main",
    boxShadow: "none",
    transition:
        "background-color 160ms ease, transform 180ms cubic-bezier(0.22, 1, 0.36, 1)",
    "&:hover:not(:disabled)": {
        bgcolor: primary ? "accent.dark" : "secondary.dark",
        transform: "translateY(-2px)",
    },
    "&:active:not(:disabled)": {
        bgcolor: primary ? "accent.dark" : "secondary.dark",
        transform: "scale(0.985)",
    },
    "&.Mui-disabled": {
        color: "action.disabled",
        bgcolor: "action.disabledBackground",
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
