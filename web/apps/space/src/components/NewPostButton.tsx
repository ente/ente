import { Add01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import React from "react";
import { useSpaceAppState } from "state/app-state";

const green = "#08C225";

export const SpaceNewPostButton: React.FC<{
    isDisabled?: boolean;
    onClick: () => void;
}> = ({ isDisabled = false, onClick }) => {
    const { postPublication } = useSpaceAppState();
    const disabled = isDisabled || postPublication?.phase == "posting";

    return (
        <Box
            className="green-bg"
            component="button"
            type="button"
            aria-label="New post"
            disabled={disabled}
            onClick={onClick}
            sx={{
                alignItems: "center",
                alignSelf: "flex-end",
                appearance: "none",
                bgcolor: green,
                border: 0,
                borderRadius: "50%",
                boxShadow: "0 4px 12px rgba(0, 0, 0, 0.32)",
                color: "#FFFFFF",
                cursor: disabled ? "default" : "pointer",
                display: "flex",
                flexShrink: 0,
                height: 64,
                justifyContent: "center",
                ml: "auto",
                opacity: disabled ? 0.6 : 1,
                p: 0,
                width: 64,
                "&:hover:not(:disabled)": { bgcolor: "#07B422" },
                "&:focus-visible": {
                    outline: `2px solid ${green}`,
                    outlineOffset: 3,
                },
            }}
        >
            <HugeiconsIcon icon={Add01Icon} size={32} strokeWidth={2} />
        </Box>
    );
};
