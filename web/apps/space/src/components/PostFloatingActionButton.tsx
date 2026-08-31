import { Add01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import React from "react";

const green = "#08C225";
const paleGreen = "#E7F6E9";
const buttonSize = 64;
const iconSize = 34;

interface SpacePostFloatingActionButtonProps {
    disabled?: boolean;
    onClick?: () => void;
}

export const SpacePostFloatingActionButton: React.FC<
    SpacePostFloatingActionButtonProps
> = ({ disabled = false, onClick }) => (
    <Box
        className="green-bg"
        component="button"
        type="button"
        aria-label="Post photo"
        disabled={disabled}
        onClick={onClick}
        sx={{
            alignItems: "center",
            appearance: "none",
            bgcolor: green,
            border: 0,
            borderRadius: "50%",
            bottom: "calc(env(safe-area-inset-bottom) + 20px)",
            boxShadow: "0 10px 24px rgba(0, 0, 0, 0.22)",
            color: "#FFFFFF",
            cursor: disabled ? "default" : "pointer",
            display: "flex",
            fontSize: 0,
            height: buttonSize,
            justifyContent: "center",
            lineHeight: 0,
            opacity: disabled ? 0.72 : 1,
            p: 0,
            position: "fixed",
            right: "max(20px, calc((100vw - 390px) / 2 + 20px))",
            transition:
                "background-color 120ms ease, box-shadow 120ms ease, transform 120ms ease",
            width: buttonSize,
            zIndex: 5,
            "& svg": { display: "block" },
            "&:active": { transform: disabled ? "none" : "translateY(1px)" },
            "&:focus-visible": {
                outline: `3px solid ${paleGreen}`,
                outlineOffset: 3,
            },
            "&:hover": {
                bgcolor: disabled ? green : "#07B422",
                boxShadow: disabled
                    ? "0 10px 24px rgba(0, 0, 0, 0.22)"
                    : "0 12px 28px rgba(0, 0, 0, 0.26)",
            },
        }}
    >
        <HugeiconsIcon icon={Add01Icon} size={iconSize} strokeWidth={2.1} />
    </Box>
);
