import {
    MultiplicationSignIcon,
    SmartPhone01Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import React from "react";

const green = "#08C225";

export const SpaceMobileBestToast: React.FC = () => {
    const [open, setOpen] = React.useState(true);

    if (!open) return null;

    return (
        <Box
            role="status"
            aria-live="polite"
            sx={{
                alignItems: "center",
                bgcolor: "#FFFFFF",
                borderRadius: "18px",
                boxShadow: "0 12px 32px rgba(0, 0, 0, 0.18)",
                boxSizing: "border-box",
                color: "#000000",
                display: { xs: "none", sm: "flex" },
                fontFamily: '"Inter Variable", Inter, sans-serif',
                fontSize: 14,
                fontWeight: 650,
                gap: "12px",
                lineHeight: "20px",
                minHeight: 52,
                pl: "12px",
                position: "fixed",
                pr: "6px",
                py: "4px",
                right: "calc(env(safe-area-inset-right) + 24px)",
                top: "calc(env(safe-area-inset-top) + 24px)",
                width: 336,
                zIndex: 20,
            }}
        >
            <Box
                component="span"
                sx={{
                    alignItems: "center",
                    color: green,
                    display: "flex",
                    flexShrink: 0,
                    height: 24,
                    justifyContent: "center",
                    width: 24,
                }}
            >
                <HugeiconsIcon
                    icon={SmartPhone01Icon}
                    size={22}
                    strokeWidth={1.8}
                />
            </Box>
            <Box component="span" sx={{ flex: "1 1 auto", minWidth: 0 }}>
                Space works best on your phone.
            </Box>
            <Box
                component="button"
                type="button"
                aria-label="Close"
                onClick={() => setOpen(false)}
                sx={{
                    alignItems: "center",
                    appearance: "none",
                    bgcolor: "transparent",
                    border: 0,
                    color: "#000000",
                    cursor: "pointer",
                    display: "flex",
                    flexShrink: 0,
                    height: 40,
                    justifyContent: "center",
                    opacity: 0.9,
                    p: 0,
                    width: 40,
                    "&:focus-visible": {
                        outline: "2px solid rgba(0 0 0 / 0.72)",
                        outlineOffset: 2,
                    },
                }}
            >
                <HugeiconsIcon
                    icon={MultiplicationSignIcon}
                    size={16}
                    strokeWidth={2}
                />
            </Box>
        </Box>
    );
};
