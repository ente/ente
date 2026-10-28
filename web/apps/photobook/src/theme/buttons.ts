import { toolbarColors, uiColors } from "./colors";

export const accentGreen = "#08C225";
export const accentGreenHover = "#07AE22";

export const editorButtonSx = {
    height: 44,
    minWidth: 44,
    borderRadius: "18px",
    px: "14px",
    py: 0,
    fontSize: 14,
    fontWeight: 600,
    lineHeight: "18px",
    whiteSpace: "nowrap",
    boxShadow: "none",
    transition: "background-color 120ms ease",
    "&:focus-visible": {
        outline: `2px solid ${accentGreen}`,
        outlineOffset: 2,
    },
    "& .MuiButton-startIcon": { ml: 0, mr: "6px" },
} as const;

export const headerButtonSx = {
    ...editorButtonSx,
    flexShrink: 0,
    minWidth: { xs: 38, sm: 0 },
    width: "auto",
    height: { xs: 38, sm: 40 },
    px: { xs: "10px", sm: "16px" },
    py: 0,
    borderRadius: { xs: "12px", sm: "14px" },
    lineHeight: "20px",
    gap: { xs: 0, sm: "8px" },
    "& .MuiButton-startIcon": { m: 0 },
    "& .MuiSvgIcon-root": { fontSize: 18 },
} as const;

export const secondaryButtonSx = {
    ...editorButtonSx,
    color: uiColors.text,
    bgcolor: uiColors.control,
    "&:hover": { bgcolor: uiColors.controlHover, boxShadow: "none" },
    "&.Mui-disabled": { color: uiColors.muted, opacity: 0.45 },
} as const;

export const editorToolbarButtonSx = {
    ...editorButtonSx,
    color: toolbarColors.text,
    bgcolor: toolbarColors.control,
    "&:hover": { bgcolor: toolbarColors.hover, boxShadow: "none" },
    "&:active": { bgcolor: toolbarColors.active },
    "&.Mui-disabled": {
        color: toolbarColors.disabled,
        bgcolor: "transparent",
        opacity: 1,
    },
} as const;
