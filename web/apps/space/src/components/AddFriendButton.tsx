import { Box } from "@mui/material";
import { SpaceButtonSpinner } from "components/ButtonSpinner";
import React from "react";
import { onboardingGreen } from "screens/OnboardingScreen";

export interface SpaceAddFriendButtonProps {
    isAddingFriend: boolean;
    onAddFriend: () => void;
    showAddingFriendSpinner: boolean;
}

export const SpaceAddFriendButton: React.FC<
    SpaceAddFriendButtonProps & {
        green?: boolean;
        label?: string;
        fullWidth?: boolean;
    }
> = ({
    isAddingFriend,
    onAddFriend,
    showAddingFriendSpinner,
    green = false,
    label = "Add Friend",
    fullWidth = false,
}) => (
    <Box
        component="button"
        type="button"
        className={green ? "green-bg" : undefined}
        disabled={isAddingFriend}
        aria-label={isAddingFriend ? "Adding friend" : undefined}
        aria-busy={isAddingFriend ? true : undefined}
        onClick={onAddFriend}
        sx={{
            alignItems: "center",
            appearance: "none",
            bgcolor: green ? onboardingGreen : "white",
            border: 0,
            borderRadius: "24px",
            color: green ? "white" : "black",
            cursor: isAddingFriend ? "default" : "pointer",
            display: "flex",
            fontFamily: '"Inter Variable", Inter, sans-serif',
            fontSize: 16,
            fontWeight: 700,
            justifyContent: "center",
            lineHeight: "24px",
            minHeight: 60,
            overflowWrap: "anywhere",
            p: "18px 24px",
            mx: "auto",
            width: fullWidth ? "100%" : "min(100%, 300px)",
            "&:hover": isAddingFriend
                ? undefined
                : green
                  ? { filter: "brightness(0.94)" }
                  : { bgcolor: "#F4F4F4" },
            "&:focus-visible": {
                outline: `2px solid ${green ? onboardingGreen : "rgba(255 255 255 / 0.88)"}`,
                outlineOffset: 3,
            },
        }}
    >
        {showAddingFriendSpinner ? <SpaceButtonSpinner /> : label}
    </Box>
);
