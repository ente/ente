import type { SxProps, Theme } from "@mui/material";

export const sidebarBackgroundSx = (theme: Theme) => ({
    backgroundColor: "#f4f4f4",
    ...theme.applyStyles("dark", { backgroundColor: "#161616" }),
});
export const fillDarkSx = (theme: Theme) => ({
    backgroundColor: "#eaeaea",
    ...theme.applyStyles("dark", { backgroundColor: "#0a0a0a" }),
});
export const rowSurfaceSx = (theme: Theme) => ({
    backgroundColor: "#ffffff",
    "&:hover": { backgroundColor: "#eaeaea" },
    "&:active": { backgroundColor: "#dedede" },
    ...theme.applyStyles("dark", {
        backgroundColor: "#212121",
        "&:hover": { backgroundColor: "#292929" },
        "&:active": { backgroundColor: "#141414" },
    }),
});
export const textBaseSx = (theme: Theme) => ({
    color: "#000000",
    ...theme.applyStyles("dark", { color: "#ffffff" }),
});
export const textLightSx = (theme: Theme) => ({
    color: "#666666",
    ...theme.applyStyles("dark", { color: "#999999" }),
});
export const iconColorSx = (theme: Theme) => ({
    color: "rgba(0,0,0,.75)",
    ...theme.applyStyles("dark", { color: "#ffffff" }),
});
export const titlebarActionButtonSx: SxProps<Theme> = [
    rowSurfaceSx,
    iconColorSx,
    { width: 36, height: 36, borderRadius: "12px", p: 0 },
];

export const warningSx = { "&&": { color: "#f63a3a" } };
export const selectedRowSx = (theme: Theme) => ({
    "&&": {
        backgroundColor: "rgba(16,113,255,.12)",
        boxShadow: `inset 0 0 0 1px ${theme.vars.palette.accent.main}`,
    },
    "&&:hover": { backgroundColor: "rgba(16,113,255,.16)" },
    "&&:active": { backgroundColor: "rgba(16,113,255,.18)" },
});
export const display2Sx = {
    fontFamily: "'Outfit Variable', Inter, system-ui, sans-serif",
    fontSize: 24,
    lineHeight: "32px",
    fontWeight: 600,
};
export const h1Sx = { fontSize: 20, lineHeight: "28px", fontWeight: 700 };
export const largeSx = { fontSize: 16, lineHeight: "20px", fontWeight: 600 };
export const bodySx = { fontSize: 14, lineHeight: "20px", fontWeight: 500 };
export const bodyBoldSx = { ...bodySx, fontWeight: 600 };
export const miniSx = { fontSize: 12, lineHeight: "16px", fontWeight: 500 };
export const usageCardSx = {
    borderRadius: "20px",
    p: 2,
    color: "#ffffff",
    background:
        "radial-gradient(circle at 12px 12px, rgba(255,255,255,.03) 0 2px, transparent 2px) 0 0/24px 24px, linear-gradient(0deg,#151515 0%,#2B2B2B 100%)",
};
export const usageMutedSx = { color: "rgba(255,255,255,.7)" };
const whiteOverlay = "rgba(255,255,255,.14)";
export const familyColor = "rgba(255,255,255,.92)";

export const usageBarSx = {
    position: "relative",
    height: 8,
    mt: 2,
    borderRadius: "4px",
    bgcolor: whiteOverlay,
    overflow: "hidden",
    "& > div": { position: "absolute", inset: 0, borderRadius: "4px" },
};
