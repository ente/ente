import type { PasteThemeTokens } from "../theme/pasteThemeTokens";

type PasteTextFieldTokens = Pick<
    PasteThemeTokens,
    "accent" | "surface" | "text"
>;

export const pasteTextFieldSx = (
    tokens: PasteTextFieldTokens,
    radius = "16px",
) => ({
    margin: 0,
    "& .MuiFilledInput-root": {
        borderRadius: radius,
        bgcolor: tokens.surface.inputBg,
        border: "1px solid",
        borderColor: tokens.surface.inputBorder,
        alignItems: "flex-start",
        boxSizing: "border-box",
        color: tokens.text.primary,
        padding: "14px",
        transition: "border-color 180ms ease, box-shadow 180ms ease",
        "&:before": { display: "none" },
        "&:after": { display: "none" },
        "&:hover:not(.Mui-disabled, .Mui-error):before": { display: "none" },
        "&:hover": { bgcolor: tokens.surface.inputBg },
        "&.Mui-focused": {
            bgcolor: tokens.surface.inputBg,
            borderColor: tokens.accent.main,
            boxShadow: `0 0 0 2px ${tokens.accent.soft}`,
        },
    },
    "& .MuiInputBase-input": {
        padding: "0 !important",
        color: tokens.text.primary,
        fontSize: "1.02rem",
        lineHeight: 1.55,
    },
    "& .MuiInputBase-multiline > .MuiInputBase-input": {
        padding: "0 !important",
        margin: "0 !important",
    },
    "& .MuiFilledInput-multiline > .MuiFilledInput-input": {
        padding: "0 !important",
        margin: "0 !important",
    },
    "& textarea": {
        padding: "0 !important",
        margin: "0 !important",
        overflowY: "auto",
    },
    "& textarea::placeholder": { color: tokens.text.placeholder, opacity: 1 },
});
