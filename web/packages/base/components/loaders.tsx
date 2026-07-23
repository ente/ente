import { Backdrop } from "@mui/material";
import { Stack100vhCenter } from "ente-base/components/containers";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import { t } from "i18next";
import React from "react";

/**
 * A centered activity indicator shown in a container that fills up the entire
 * width and height of the viewport.
 *
 * This is meant as a root component of a page, e.g., during initial load.
 */
export const LoadingIndicator: React.FC = () => (
    <Stack100vhCenter>
        <ActivityIndicator />
    </Stack100vhCenter>
);

/**
 * An translucent overlay that covers the entire viewport and shows an activity
 * indicator in its center.
 *
 * Used as a overlay during blocking actions. The use of this component is not
 * recommended for new code.
 */
export const TranslucentLoadingOverlay: React.FC = () => (
    <Backdrop
        // Specifying open here causes us to lose animations. This is not
        // optimal, but fine for now since this the use of this is limited to a
        // few interstitial overlays, and if refactoring consider replacing this
        // entirely with a more localized activity indicator.
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
            /* Above the highest possible MUI z-index, that of the MUI tooltip
               See: https://mui.com/material-ui/customization/default-theme/ */
            zIndex: "calc(var(--mui-zIndex-tooltip) + 1)",
        }}
    >
        <ActivityIndicator />
    </Backdrop>
);
