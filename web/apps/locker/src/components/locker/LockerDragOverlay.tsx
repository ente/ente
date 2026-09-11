import CloudUploadOutlinedIcon from "@mui/icons-material/CloudUploadOutlined";
import { Box, Typography } from "@mui/material";
import { t } from "i18next";
import React from "react";

export const LockerDragOverlay: React.FC = () => (
    <Box
        sx={(theme) => ({
            position: "fixed",
            inset: 0,
            zIndex: 1600,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            pointerEvents: "none",
            backgroundColor: "rgba(8, 9, 10, 0.58)",
            backdropFilter: "blur(8px)",
            ...theme.applyStyles("light", {
                backgroundColor: "rgba(241, 245, 249, 0.78)",
            }),
        })}
    >
        <Box
            sx={(theme) => ({
                width: "min(520px, calc(100vw - 48px))",
                px: 4,
                py: 5,
                borderRadius: "24px",
                border: "2px dashed rgba(127, 179, 255, 0.48)",
                background:
                    "linear-gradient(180deg, rgba(16, 113, 255, 0.16) 0%, rgba(16, 113, 255, 0.08) 100%)",
                boxShadow: "0 20px 48px rgba(0, 0, 0, 0.26)",
                textAlign: "center",
                ...theme.applyStyles("light", {
                    background:
                        "linear-gradient(180deg, rgba(16, 113, 255, 0.10) 0%, rgba(16, 113, 255, 0.06) 100%)",
                    boxShadow: "0 18px 40px rgba(15, 23, 42, 0.12)",
                }),
            })}
        >
            <CloudUploadOutlinedIcon
                sx={{ fontSize: 44, color: "primary.main", mb: 1.5 }}
            />
            <Typography variant="h4" sx={{ mb: 0.75 }}>
                {t("saveDocumentTitle")}
            </Typography>
            <Typography variant="body" sx={{ color: "text.muted" }}>
                {t("clickHereToUpload")}
            </Typography>
        </Box>
    </Box>
);
