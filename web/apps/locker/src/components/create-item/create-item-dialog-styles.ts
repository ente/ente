import type { Theme } from "@mui/material/styles";

export const lockerScrollAreaSx = (theme: Theme) => ({
    overflowY: "auto",
    marginRight: "-14px",
    paddingRight: "14px",
    scrollbarWidth: "thin",
    scrollbarColor: `${theme.vars.palette.fill.muted} transparent`,
    "&::-webkit-scrollbar": { width: 6 },
    "&::-webkit-scrollbar-track": { background: "transparent" },
    "&::-webkit-scrollbar-thumb": {
        borderRadius: "999px",
        backgroundColor: theme.vars.palette.fill.muted,
    },
    "&::-webkit-scrollbar-thumb:hover": {
        backgroundColor: theme.vars.palette.stroke.muted,
    },
});
