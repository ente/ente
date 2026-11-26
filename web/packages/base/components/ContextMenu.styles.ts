import type { Theme } from "@mui/material";

export const contextMenuPaperStyles = (theme: Theme) => ({
    backgroundColor: theme.vars.palette.background.elevatedPaper,
    borderRadius: "12px",
    boxShadow: theme.vars.palette.boxShadow.menu,
    marginTop: "6px",
});
