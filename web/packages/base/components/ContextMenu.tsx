import { Menu, MenuItem, styled } from "@mui/material";

export const ContextMenu = styled(Menu)(({ theme }) => ({
    "& .MuiPaper-root": {
        backgroundColor: theme.vars.palette.background.elevatedPaper,
        minWidth: 220,
        borderRadius: 12,
        boxShadow: theme.vars.palette.boxShadow.menu,
        marginTop: 6,
    },
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
    "&:hover": { backgroundColor: theme.vars.palette.fill.faintHover },
    "& .MuiListItemIcon-root": { minWidth: 0, color: "inherit" },
    "& .MuiListItemText-root": { margin: 0 },
    "& .MuiListItemText-primary": { color: "inherit", fontSize: "inherit" },
    ...(destructive && {
        color: theme.vars.palette.critical.main,
        "&:hover": {
            backgroundColor: theme.vars.palette.critical.main,
            color: theme.vars.palette.critical.contrastText,
        },
    }),
}));
