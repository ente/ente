import type { SxProps, Theme } from "@mui/material";

const FullScreenBreakpoint = 491;

export const collectionDialogCornerRadius = 32;

export const collectionDialogFullScreenQuery = `(width < ${FullScreenBreakpoint}px)`;

export const collectionDialogSurfaceStroke = "#e0e0e0";
export const collectionDialogSurfaceStrokeDark = "rgba(255 255 255 / 0.12)";

export const collectionDialogPaperSx: SxProps<Theme> = (theme) => ({
    position: "relative",
    width: "min(500px, calc(100svw - 32px))",
    maxWidth: "500px",
    boxSizing: "content-box",
    borderRadius: "20px",
    border: `1px solid ${collectionDialogSurfaceStroke}`,
    backgroundColor: "#f4f4f4",
    backgroundImage: "none",
    boxShadow: "none",
    color: "text.base",
    [`@media (width >= ${FullScreenBreakpoint}px)`]: { height: "100%" },
    [`@media (width < ${FullScreenBreakpoint}px)`]: {
        width: "100%",
        maxWidth: "100%",
        height: "100%",
        boxSizing: "border-box",
        borderRadius: 0,
        border: "none",
    },
    ...theme.applyStyles("dark", {
        borderColor: collectionDialogSurfaceStrokeDark,
        backgroundColor: "#1b1b1b",
    }),
});

export const collectionDialogHeaderSx = { p: "20px", gap: "16px" };
export const collectionDialogHeaderRowSx = {
    alignItems: "flex-start",
    justifyContent: "space-between",
    gap: "12px",
};
export const collectionDialogHeaderActionsSx = {
    alignItems: "center",
    gap: 1,
    flexShrink: 0,
};
export const collectionDialogTitleSx = {
    fontSize: 24,
    lineHeight: "32px",
    fontWeight: 600,
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
};
export const collectionDialogBodyMutedSx = {
    fontSize: 14,
    lineHeight: "20px",
    fontWeight: 500,
    color: "text.muted",
};
export const collectionDialogIconButtonSx = (theme: Theme) => ({
    width: 38,
    height: 38,
    p: 0,
    color: "text.base",
    backgroundColor: "background.paper",
    "&:hover": { backgroundColor: "fill.faintHover" },
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255 255 255 / 0.12)",
    }),
});
export const collectionDialogDividerSx = (theme: Theme) => ({
    height: "1px",
    backgroundColor: "rgba(0 0 0 / 0.06)",
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255 255 255 / 0.08)",
    }),
});
export const collectionDialogNoResultsSx = {
    flex: 1,
    display: "flex",
    justifyContent: "center",
    alignItems: "center",
    minHeight: 154,
};
