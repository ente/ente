import type { SxProps, Theme } from "@mui/material";

const surfaceStroke = "#e0e0e0";
const surfaceStrokeDark = "rgba(255 255 255 / 0.12)";

export const v2PaperSx: SxProps<Theme> = (theme) => ({
    width: "min(444px, calc(100svw - 32px))",
    maxWidth: "444px",
    boxSizing: "content-box",
    m: 2,
    borderRadius: "20px",
    border: `1px solid ${surfaceStroke}`,
    backgroundColor: "#f4f4f4",
    backgroundImage: "none",
    boxShadow: "none",
    color: "text.base",
    ...theme.applyStyles("dark", {
        borderColor: surfaceStrokeDark,
        backgroundColor: "#1b1b1b",
    }),
});
export const v2HeaderRowSx = {
    alignItems: "center",
    justifyContent: "space-between",
    gap: "12px",
};
export const v2TitleSx = { fontSize: 24, lineHeight: "32px", fontWeight: 600 };
export const v2CloseButtonSx = (theme: Theme) => ({
    width: 38,
    height: 38,
    p: 0,
    flexShrink: 0,
    color: "text.base",
    backgroundColor: "background.paper",
    "&:hover": { backgroundColor: "fill.faintHover" },
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255 255 255 / 0.12)",
    }),
});

const greenAccent = "#08c225";
const greenAccentHover = "#07ad21";
const errorColor = "#fa1336";

export const v2LabelSx = {
    fontSize: 14,
    lineHeight: "20px",
    fontWeight: 500,
    color: "text.muted",
};
export const v2InputSx: SxProps<Theme> = (theme) => ({
    height: 52,
    boxSizing: "content-box",
    display: "flex",
    alignItems: "center",
    borderRadius: "16px",
    border: "1px solid transparent",
    backgroundColor: "background.paper",
    px: "16px",
    fontSize: 14,
    fontWeight: 500,
    color: "text.base",
    "&.Mui-focused": { borderColor: "rgba(0 0 0 / 0.08)" },
    "& input": { padding: 0, height: "auto" },
    "& input::placeholder": { color: "text.muted", opacity: 1 },
    ...theme.applyStyles("dark", {
        backgroundColor: "#282828",
        "&.Mui-focused": { borderColor: "rgba(255 255 255 / 0.18)" },
    }),
    "&.Mui-error": { borderColor: errorColor },
});
export const v2HelperSx = (isError: boolean) => (theme: Theme) => ({
    fontSize: 12,
    lineHeight: "16px",
    fontWeight: 500,
    color: isError ? errorColor : "rgba(0 0 0 / 0.45)",
    ...(isError
        ? {}
        : theme.applyStyles("dark", { color: "rgba(255 255 255 / 0.45)" })),
});
const v2BaseActionSx = {
    flex: 1,
    height: 52,
    borderRadius: "20px",
    fontSize: 14,
    lineHeight: "20px",
    fontWeight: 500,
    fontFamily: "inherit",
    "&.Mui-disabled": { opacity: 0.7 },
};
export const v2CancelButtonSx = (theme: Theme) => ({
    ...v2BaseActionSx,
    color: "text.base",
    backgroundColor: "#eaeaea",
    "&:hover": { backgroundColor: "#dedede" },
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255 255 255 / 0.12)",
        "&:hover": { backgroundColor: "rgba(255 255 255 / 0.18)" },
    }),
});
export const v2SubmitButtonSx = {
    ...v2BaseActionSx,
    color: "#fff",
    backgroundColor: greenAccent,
    "&:hover": { backgroundColor: greenAccentHover },
    "&.Mui-disabled": {
        color: "#fff",
        backgroundColor: greenAccent,
        opacity: 0.7,
    },
};

export const peopleActionFocusSx = {
    "&.Mui-focusVisible": {
        outline: "1px solid",
        outlineColor: "stroke.base",
        outlineOffset: "2px",
    },
};
