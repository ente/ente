import { pageMenuColors, popupShadow } from "./colors";

export const pageMenuPaperSx = {
    bgcolor: pageMenuColors.background,
    backgroundImage: "none",
    borderRadius: "14px",
    boxShadow: popupShadow,
    mt: "6px",
    minWidth: 0,
    p: "4px",
    width: "max-content",
} as const;

export const pageMenuItemSx = {
    alignItems: "center",
    borderRadius: "10px",
    color: pageMenuColors.text,
    display: "flex",
    gap: "8px",
    minHeight: 36,
    px: "9px",
    py: "4px",
    fontSize: 13,
    fontWeight: 500,
    lineHeight: "18px",
    whiteSpace: "nowrap",
    transition: "background-color 120ms ease, color 120ms ease",
    "& .MuiSvgIcon-root": { color: pageMenuColors.icon },
    "&:hover, &.Mui-focusVisible": {
        bgcolor: pageMenuColors.hover,
        "& .MuiSvgIcon-root": { color: pageMenuColors.text },
    },
    "&:active": { bgcolor: pageMenuColors.active },
} as const;
