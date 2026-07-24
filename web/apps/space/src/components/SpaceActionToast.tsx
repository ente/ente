import { MultiplicationSignIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import { keyframes } from "@mui/material/styles";
import React from "react";
import { spaceTouchTargetSize } from "styles/touchTargets";

const green = "#08C225";
const textBase = "var(--text-color)";
const toastHorizontalPadding = "16px";
const toastEnter = keyframes`
    from {
        opacity: 0;
        transform: translateX(-50%) translateY(-10px);
    }

    to {
        opacity: 1;
        transform: translateX(-50%) translateY(0);
    }
`;

interface SpaceActionToastProps {
    action?: React.ReactNode;
    animateEntrance?: boolean;
    closeLabel: string;
    icon: React.ReactNode;
    message: React.ReactNode;
    onClose?: () => void;
    zIndex?: number;
}

export const SpaceActionToast: React.FC<SpaceActionToastProps> = ({
    action,
    animateEntrance = false,
    closeLabel,
    icon,
    message,
    onClose,
    zIndex = 20,
}) => (
    <Box
        sx={{
            animation: animateEntrance
                ? `${toastEnter} 320ms cubic-bezier(0.22, 1, 0.36, 1) both`
                : undefined,
            boxSizing: "border-box",
            left: "50%",
            px: toastHorizontalPadding,
            pointerEvents: "none",
            position: "fixed",
            top: "calc(env(safe-area-inset-top) + 10px)",
            transform: "translateX(-50%)",
            width: "100%",
            zIndex,
            "@media (min-width: 600px)": { maxWidth: 390 },
            "@media (prefers-reduced-motion: reduce)": {
                animation: animateEntrance ? "none" : undefined,
            },
        }}
    >
        <Box
            role="status"
            aria-live="polite"
            sx={{
                alignItems: "center",
                bgcolor: "var(--feed-card-bg)",
                borderRadius: "18px",
                boxShadow: "0 12px 32px rgba(0, 0, 0, 0.18)",
                boxSizing: "border-box",
                color: "var(--text-color)",
                display: "flex",
                fontFamily: '"Inter Variable", Inter, sans-serif',
                fontSize: 14,
                fontWeight: 650,
                gap: "10px",
                lineHeight: "20px",
                minHeight: 50,
                pointerEvents: "auto",
                pl: "10px",
                pr: "6px",
                py: "3px",
                width: "100%",
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
                {icon}
            </Box>
            <Box
                sx={{
                    flex: "1 1 auto",
                    minWidth: 0,
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                    whiteSpace: "nowrap",
                }}
            >
                {message}
            </Box>
            <Box
                sx={{
                    alignItems: "center",
                    display: "flex",
                    flexShrink: 0,
                    gap: 0,
                }}
            >
                {action}
                <Box
                    component="button"
                    type="button"
                    aria-label={closeLabel}
                    onClick={onClose}
                    sx={{
                        alignItems: "center",
                        appearance: "none",
                        bgcolor: "transparent",
                        border: 0,
                        color: textBase,
                        cursor: onClose ? "pointer" : "default",
                        display: "flex",
                        flexShrink: 0,
                        height: spaceTouchTargetSize,
                        justifyContent: "center",
                        opacity: 0.9,
                        p: 0,
                        width: 36,
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
        </Box>
    </Box>
);
