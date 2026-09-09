import { UserAdd02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import React from "react";
import { spaceEmptyStateButtonSx } from "styles/buttons";
import {
    spaceSurface,
    spaceSurfaceHover,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import { spacePostTileRadius, spaceTileCornerStyles } from "styles/tiles";
import type {
    AddFriendTileVariant,
    HomeTilePlacement,
} from "utils/home-tile-layout";

interface SpaceAddFriendTileProps {
    onClick: () => void;
    placement: HomeTilePlacement;
    variant: AddFriendTileVariant;
}

export const SpaceAddFriendTile: React.FC<SpaceAddFriendTileProps> = ({
    onClick,
    placement,
    variant,
}) => {
    return (
        <Box
            component="li"
            sx={{
                ...spaceTileCornerStyles(
                    Math.min(
                        spacePostTileRadius,
                        Math.min(placement.width, placement.height) * 0.2,
                    ),
                ),
                height: placement.height,
                left: placement.x,
                listStyle: "none",
                position: "absolute",
                top: placement.y,
                width: placement.width,
            }}
        >
            {variant == "empty" ? (
                <Box
                    sx={{
                        alignItems: "center",
                        bgcolor: spaceSurface,
                        borderRadius: "inherit",
                        boxSizing: "border-box",
                        color: spaceText,
                        display: "flex",
                        flexDirection: "column",
                        height: "100%",
                        justifyContent: "center",
                        px: "24px",
                        py: "32px",
                        textAlign: "center",
                    }}
                >
                    <HugeiconsIcon
                        icon={UserAdd02Icon}
                        size={32}
                        strokeWidth={1.7}
                        color={spaceTextMuted}
                        style={{ flexShrink: 0, marginBottom: 16 }}
                    />
                    <Box
                        component="h2"
                        sx={{
                            fontFamily: '"Nunito", sans-serif',
                            fontSize: 22,
                            fontWeight: 800,
                            lineHeight: "28px",
                            m: 0,
                            mb: "8px",
                            textWrap: "balance",
                        }}
                    >
                        Invite your close friends and family
                    </Box>
                    <Box
                        component="p"
                        sx={{
                            color: spaceTextMuted,
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 13,
                            lineHeight: "20px",
                            m: 0,
                            maxWidth: 240,
                        }}
                    >
                        Each person gets a little spot of their own in your
                        Space.
                    </Box>
                    <Box sx={{ mt: "24px" }}>
                        <Box
                            className="green-bg"
                            component="button"
                            type="button"
                            onClick={onClick}
                            sx={spaceEmptyStateButtonSx}
                        >
                            <HugeiconsIcon
                                icon={UserAdd02Icon}
                                size={18}
                                strokeWidth={1.8}
                            />
                            Add a friend
                        </Box>
                    </Box>
                </Box>
            ) : (
                <Box
                    component="button"
                    type="button"
                    aria-label="Add friend"
                    onClick={onClick}
                    sx={{
                        alignItems: "center",
                        appearance: "none",
                        bgcolor: spaceSurface,
                        border: 0,
                        borderRadius: "inherit",
                        color: "#65656D",
                        cursor: "pointer",
                        display: "flex",
                        height: "100%",
                        justifyContent: "center",
                        p: "var(--space-tile-padding)",
                        width: "100%",
                        transition:
                            "background-color 160ms ease, box-shadow 160ms ease",
                        "&:hover": {
                            bgcolor: spaceSurfaceHover,
                            boxShadow:
                                "inset 0 0 0 1px rgba(255, 255, 255, 0.08)",
                        },
                        "&:active": { bgcolor: spaceSurface },
                        "&:focus-visible": {
                            outline: "2px solid #08C225",
                            outlineOffset: -4,
                        },
                    }}
                >
                    <HugeiconsIcon
                        icon={UserAdd02Icon}
                        size={28}
                        strokeWidth={1.7}
                    />
                </Box>
            )}
        </Box>
    );
};
