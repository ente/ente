import { useMediaQuery } from "@mui/material";

export const uploadSheetMediaQuery = "@media (max-width: 620px)";

export const useIsUploadSheet = () => useMediaQuery(uploadSheetMediaQuery);

export const uploadSheetPaperSx = {
    [uploadSheetMediaQuery]: {
        position: "fixed",
        bottom: 0,
        left: 0,
        m: 0,
        width: "100%",
        maxWidth: "none",
        maxHeight: "calc(100dvh - 72px)",
        borderRadius: "20px 20px 0 0",
        borderBottom: "none",
    },
};
