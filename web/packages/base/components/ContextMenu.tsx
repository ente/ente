import { Menu, MenuItem, styled } from "@mui/material";
import { contextMenuPaperStyles } from "./ContextMenu.styles";

export const ContextMenu = styled(Menu)(({ theme }) => ({
    "& .MuiMenu-paper": { ...contextMenuPaperStyles(theme), minWidth: 220 },
    "& .MuiList-root": { padding: theme.spacing(1) },
}));

export const ContextMenuItem = styled(MenuItem, {
    shouldForwardProp: (prop) => prop !== "destructive",
})<{ destructive?: boolean }>(({ theme, destructive }) => ({
    display: "flex",
    alignItems: "center",
    gap: 12,
    padding: theme.spacing(1.5, 2),
    borderRadius: 10,
    color: theme.vars.palette.text.base,
    fontSize: 15,
    "&:hover, &.Mui-focusVisible, &.Mui-selected:hover, &.Mui-selected.Mui-focusVisible":
        { backgroundColor: theme.vars.palette.fill.faintHover },
    "&.Mui-selected": { backgroundColor: theme.vars.palette.fill.faint },
    "& .MuiListItemIcon-root": { minWidth: 0, color: "inherit" },
    "& .MuiListItemText-root": { margin: 0 },
    "& .MuiListItemText-primary": { color: "inherit", fontSize: "inherit" },
    ...(destructive && {
        color: theme.vars.palette.critical.main,
        "&:hover, &.Mui-focusVisible": {
            backgroundColor: theme.vars.palette.critical.main,
            color: theme.vars.palette.critical.contrastText,
        },
    }),
}));
