import { Box } from "@mui/material";
import React from "react";
import { spaceTileCircleInset, spaceTilePillInset } from "styles/tiles";

interface SpacePostBadgeProps extends React.PropsWithChildren {
    backgroundColor: string;
    color: string;
    placement?: "center" | "top-right";
    variant?: "default" | "unread";
}

export const SpacePostBadge: React.FC<SpacePostBadgeProps> = ({
    backgroundColor,
    children,
    color,
    placement = "top-right",
    variant = "default",
}) => {
    const height = variant == "unread" || placement == "center" ? 24 : 18;
    const inset =
        variant == "unread"
            ? spaceTileCircleInset(height)
            : spaceTilePillInset(height);
    return (
        <Box
            component="span"
            aria-hidden
            sx={{
                alignItems: "center",
                bgcolor: backgroundColor,
                borderRadius: "999px",
                boxSizing: "border-box",
                color,
                display: "inline-flex",
                fontFamily: '"Inter Variable", Inter, sans-serif',
                fontSize: placement == "center" ? 11 : 10,
                fontVariantNumeric: "tabular-nums",
                fontWeight: placement == "center" ? 600 : 700,
                height,
                justifyContent: "center",
                lineHeight: 1,
                maxWidth: "calc(100% - 2 * var(--space-tile-padding))",
                minWidth: height,
                pointerEvents: "none",
                position: "absolute",
                px: placement == "center" ? "10px" : "7px",
                whiteSpace: "nowrap",
                zIndex: 1,
                ...(placement == "center"
                    ? {
                          left: "50%",
                          top: "50%",
                          transform: "translate(-50%, -50%)",
                      }
                    : {
                          right: inset,
                          top: inset,
                          maxWidth: `calc(100% - 2 * (${inset}))`,
                      }),
                ...(variant == "unread" && {
                    border: "1px solid #FFFFFF",
                    fontSize: 12,
                    px: "6px",
                }),
            }}
        >
            <Box
                component="span"
                sx={{ overflow: "hidden", textOverflow: "ellipsis" }}
            >
                {children}
            </Box>
        </Box>
    );
};

export const SpacePostUnreadBadge: React.FC<{ count: number }> = ({
    count,
}) => (
    <SpacePostBadge backgroundColor="#F63A3A" color="#FFFFFF" variant="unread">
        {count}
    </SpacePostBadge>
);
