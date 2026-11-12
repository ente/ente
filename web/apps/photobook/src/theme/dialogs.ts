import { accentGreen } from "./buttons";

export const dialogPaperSx = {
    width: 381,
    maxWidth: "calc(100% - 32px)",
    m: 2,
    p: 0,
    borderRadius: "28px",
    border: "1px solid rgba(255,255,255,0.18)",
    bgcolor: "#1b1b1b",
    backgroundImage: "none",
    boxShadow: "none",
    fontFamily: '"Inter Variable", sans-serif',
    letterSpacing: "-0.011em",
    "& .MuiTypography-root, & .MuiButton-root": { fontFamily: "inherit" },
} as const;

export const dialogHeaderSx = {
    width: "100%",
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    gap: "9px",
    textAlign: "center",
    mb: "16px",
} as const;

export const dialogTitleSx = {
    fontSize: 24,
    lineHeight: "28px",
    fontWeight: 600,
    letterSpacing: "-0.48px",
    color: "#FFFFFF",
} as const;
export const dialogDescriptionSx = {
    fontSize: 14,
    lineHeight: "20px",
    fontWeight: 500,
    color: "rgba(255,255,255,0.7)",
    width: "100%",
} as const;

export const dialogCloseButtonSx = {
    position: "absolute",
    top: 11,
    right: 12,
    p: "10px",
    flexShrink: 0,
    color: "#FFFFFF",
    bgcolor: "rgba(255,255,255,0.12)",
    "&:hover": { bgcolor: "rgba(255,255,255,0.16)" },
    "&:focus-visible": {
        outline: `2px solid ${accentGreen}`,
        outlineOffset: 2,
    },
} as const;

export const dialogActionSx = {
    display: "flex",
    p: "20px 16px",
    justifyContent: "center",
    alignItems: "center",
    gap: "8px",
    flex: "1 0 0",
    borderRadius: "20px",
    fontSize: 16,
    fontWeight: 500,
    lineHeight: "20px",
    textTransform: "none",
    boxShadow: "none",
    "&:focus-visible": {
        outline: `2px solid ${accentGreen}`,
        outlineOffset: 2,
    },
} as const;
export const dialogCancelButtonSx = {
    ...dialogActionSx,
    color: "rgba(255,255,255,0.7)",
    bgcolor: "rgba(255,255,255,0.04)",
    border: "none",
    "&:hover": { bgcolor: "rgba(255,255,255,0.08)", border: "none" },
} as const;

export const dialogSelectSx = {
    height: 54,
    bgcolor: "#282828",
    borderRadius: "16px",
    color: "#FFFFFF",
    fontFamily: "inherit",
    fontSize: 14,
    fontWeight: 500,
    "& .MuiSelect-select": { px: "16px" },
    "& .MuiOutlinedInput-notchedOutline": { borderColor: "transparent" },
    "&:hover .MuiOutlinedInput-notchedOutline": {
        borderColor: "rgba(255,255,255,0.12)",
    },
    "&.Mui-focused .MuiOutlinedInput-notchedOutline": {
        borderColor: "rgba(255,255,255,0.18)",
        borderWidth: 1,
    },
} as const;
export const dialogSelectMenuProps = {
    slotProps: {
        paper: {
            sx: {
                bgcolor: "#282828",
                borderRadius: "16px",
                maxHeight: 320,
                fontFamily: '"Inter Variable", sans-serif',
                "& .MuiMenuItem-root": {
                    fontFamily: "inherit",
                    fontSize: 14,
                    "&.Mui-selected": { bgcolor: "transparent" },
                    "&:hover, &.Mui-selected:hover": {
                        bgcolor: "rgba(255,255,255,0.08)",
                    },
                    "&.Mui-focusVisible, &.Mui-selected.Mui-focusVisible": {
                        bgcolor: "rgba(255,255,255,0.08)",
                        outline: "1px solid rgba(255,255,255,0.3)",
                        outlineOffset: -1,
                    },
                },
            },
        },
    },
};
