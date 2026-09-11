import type { Theme } from "@mui/material";
import { lockerColorSx, lockerShadowFloating } from "./tokens";

export const lockerMenuPaperSx = (theme: Theme) => ({
    width: 180,
    borderRadius: "16px",
    padding: "6px",
    boxShadow: lockerShadowFloating,
    border: "1px solid",
    ...lockerColorSx(theme, {
        backgroundColor: "fillLight",
        borderColor: "strokeFaint",
    }),
});

export const lockerSheetPaperSx = (theme: Theme) => ({
    borderRadius: "24px",
    width: "min(100%, 440px)",
    padding: "20px",
    ...lockerColorSx(theme, { backgroundColor: "backgroundBase" }),
    [theme.breakpoints.down("sm")]: {
        margin: 0,
        width: "100%",
        maxWidth: "100%",
        borderRadius: "20px 20px 0 0",
        paddingBottom: "34px",
    },
});

export const lockerSheetContainerSx = {
    alignItems: { xs: "flex-end", sm: "center" },
};
