import { Backdrop } from "@mui/material";
import { Stack100vhCenter } from "ente-base/components/containers";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import { t } from "i18next";
import React from "react";

export const LoadingIndicator: React.FC = () => (
    <Stack100vhCenter>
        <ActivityIndicator />
    </Stack100vhCenter>
);

// Prefer localized activity indicators in new code.
export const TranslucentLoadingOverlay: React.FC = () => (
    <Backdrop
        // A Backdrop mounted already open has no entrance transition.
        open={true}
        slotProps={{
            root: {
                "aria-busy": true,
                "aria-hidden": false,
                "aria-label": t("loading"),
                role: "status",
            },
        }}
        sx={{
            backgroundColor: "var(--mui-palette-backdrop-muted)",
            backdropFilter: "blur(30px) opacity(95%)",
            zIndex: "calc(var(--mui-zIndex-tooltip) + 1)",
        }}
    >
        <ActivityIndicator />
    </Backdrop>
);
