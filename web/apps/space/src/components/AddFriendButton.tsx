import { UserAdd02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import React from "react";
import { spaceEmptyStateButtonSx } from "styles/buttons";
import { spaceSurface } from "styles/colors";

export const SpaceAddFriendButton: React.FC<{ onClick: () => void }> = ({
    onClick,
}) => (
    <Box
        component="button"
        type="button"
        aria-label="Add friend"
        onClick={onClick}
        sx={{
            ...spaceEmptyStateButtonSx,
            bgcolor: "transparent",
            borderRadius: "50%",
            color: "#585860",
            height: 64,
            p: 0,
            width: 64,
            "&:hover:not(:disabled)": { bgcolor: spaceSurface },
        }}
    >
        <HugeiconsIcon icon={UserAdd02Icon} size={24} strokeWidth={1.5} />
    </Box>
);
