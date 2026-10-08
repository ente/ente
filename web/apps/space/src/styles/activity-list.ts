import { spaceSurface, spaceText, spaceTextMuted } from "styles/colors";

export const spaceActivityListSx = {
    boxSizing: "border-box",
    m: 0,
    p: "6px 16px 28px",
} as const;

export const spaceActivityRowSx = {
    alignItems: "center",
    borderRadius: "8px",
    boxSizing: "border-box",
    color: spaceText,
    display: "grid",
    gap: "10px",
    minHeight: 64,
    mx: "-8px",
    p: "8px",
    textAlign: "left",
    transition: "background-color 140ms ease",
    width: "calc(100% + 16px)",
    "&:active": { bgcolor: spaceSurface },
    "&:hover": { bgcolor: spaceSurface },
} as const;

export const spaceActivityPreviewSx = {
    color: spaceTextMuted,
    fontFamily: '"Inter Variable", Inter, sans-serif',
    fontSize: 13,
    fontWeight: 500,
    lineHeight: "18px",
    minWidth: 0,
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
} as const;
