import MenuIcon from "@mui/icons-material/Menu";
import { Box, IconButton, Tooltip } from "@mui/material";
import { t } from "i18next";
import type { ReactNode } from "react";

interface GalleryLayoutProps {
    children: ReactNode;
    header: ReactNode;
    onSettings: () => void;
}

/** Desktop navigation and content frame; mobile keeps the gallery's own navbar. */
export function GalleryLayout({
    children,
    header,
    onSettings,
}: GalleryLayoutProps) {
    return (
        <Box
            sx={{
                display: "flex",
                flexDirection: "column",
                flex: 1,
                minHeight: 0,
                minWidth: 0,
                "@media (min-width: 720px)": {
                    display: "grid",
                    gridTemplateColumns: "88px minmax(0, 1fr)",
                    gridTemplateRows: "80px minmax(0, 1fr)",
                    bgcolor: "fill.faint",
                    paddingRight: "16px",
                    paddingBottom: "16px",
                },
            }}
        >
            <Box
                component="nav"
                aria-label={t("photos")}
                sx={{
                    display: "none",
                    "@media (min-width: 720px)": { display: "flex" },
                    gridRow: "1 / -1",
                    alignItems: "center",
                    flexDirection: "column",
                    gap: "12px",
                    py: "20px",
                    overflowY: "auto",
                }}
            >
                <Tooltip title={t("settings")} placement="right">
                    <IconButton
                        aria-label={t("settings")}
                        onClick={onSettings}
                        sx={{ width: "44px", height: "44px" }}
                    >
                        <MenuIcon />
                    </IconButton>
                </Tooltip>
            </Box>
            <Box
                component="header"
                sx={{
                    display: "flex",
                    flexDirection: "column",
                    flexShrink: 0,
                    gridColumn: 2,
                    justifyContent: "center",
                    minWidth: 0,
                }}
            >
                {header}
            </Box>
            <Box
                component="main"
                sx={{
                    display: "flex",
                    flexDirection: "column",
                    flex: 1,
                    minHeight: 0,
                    minWidth: 0,
                    "@media (min-width: 720px)": {
                        gridColumn: 2,
                        bgcolor: "background.default",
                        borderRadius: "24px",
                        overflow: "hidden",
                        pt: "12px",
                    },
                }}
            >
                {children}
            </Box>
        </Box>
    );
}
