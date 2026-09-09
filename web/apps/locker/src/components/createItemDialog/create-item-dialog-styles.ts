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

export const lockerFieldSx = (
    theme: Theme,
    {
        multiline,
        minHeight,
        activeBorder,
    }: { multiline?: boolean; minHeight?: number; activeBorder?: boolean },
) => ({
    "& .MuiOutlinedInput-root": {
        backgroundColor: theme.vars.palette.background.paper,
        color: theme.vars.palette.text.base,
        borderRadius: "16px",
        fontSize: 14,
        lineHeight: "20px",
        fontWeight: 500,
        ...(multiline
            ? { p: "16px", minHeight, alignItems: "flex-start" }
            : { height: 52, px: "16px" }),
    },
    "& .MuiOutlinedInput-input": multiline
        ? { p: 0 }
        : { p: 0, height: "100%" },
    "& .MuiOutlinedInput-notchedOutline": {
        border: `1px solid ${activeBorder ? theme.vars.palette.stroke.muted : theme.vars.palette.stroke.fainter}`,
    },
    "& .MuiOutlinedInput-root:hover .MuiOutlinedInput-notchedOutline": {
        borderColor: activeBorder
            ? theme.vars.palette.stroke.muted
            : theme.vars.palette.stroke.fainter,
    },
    "& .MuiOutlinedInput-root.Mui-focused .MuiOutlinedInput-notchedOutline": {
        borderWidth: 1,
        borderColor: theme.vars.palette.stroke.muted,
    },
    "& .MuiInputBase-input::placeholder": {
        color: theme.vars.palette.text.faint,
        opacity: 1,
    },
});

export const lockerPrimaryButtonSx = (
    theme: Theme,
    { loading }: { loading: boolean },
) => ({
    minHeight: 52,
    ...(loading
        ? {}
        : {
              "&.Mui-disabled": {
                  backgroundColor: theme.vars.palette.fill.faintHover,
                  color: theme.vars.palette.text.faint,
              },
          }),
});

export const lockerHeaderIconButtonSx = (theme: Theme) => ({
    width: 36,
    height: 36,
    p: 0,
    borderRadius: "50%",
    flexShrink: 0,
    backgroundColor: theme.vars.palette.background.paper,
    color: theme.vars.palette.text.base,
    "&:hover": { backgroundColor: theme.vars.palette.fill.faintHover },
    "&.Mui-disabled": {
        backgroundColor: theme.vars.palette.fill.faintHover,
        color: theme.vars.palette.text.faint,
    },
});
