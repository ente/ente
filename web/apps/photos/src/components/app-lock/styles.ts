import type { Theme } from "@mui/material/styles";

export const LOGOUT_MODAL_WIDTH = 368;

export const titleTextSx = (theme: Theme) => ({
    fontWeight: 600,
    fontSize: 24,
    lineHeight: "28px",
    letterSpacing: "-0.48px",
    color: "#000",
    textAlign: "center" as const,
    ...theme.applyStyles("dark", { color: "#fff" }),
});

export const subtitleTextSx = (theme: Theme) => ({
    fontWeight: 500,
    fontSize: 14,
    lineHeight: "20px",
    color: "#666",
    textAlign: "center" as const,
    maxWidth: 295,
    ...theme.applyStyles("dark", { color: "rgba(255, 255, 255, 0.64)" }),
});
