import { Loading03Icon, Tick02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import { keyframes } from "@mui/material/styles";
import React from "react";

export const spaceActionDoneDurationMs = 1300;
export const spaceActionTransition = "220ms cubic-bezier(0.4, 0, 0.2, 1)";

export type SpaceActionPhase = "busy" | "done";

const spaceActionSpin = keyframes`
    from {
        transform: rotate(0deg);
    }

    to {
        transform: rotate(360deg);
    }
`;

interface SpaceActionFeedbackIconProps {
    idleIcon?: React.ReactNode;
    phase: SpaceActionPhase | null;
    size?: number;
}

export const SpaceActionFeedbackIcon: React.FC<
    SpaceActionFeedbackIconProps
> = ({ idleIcon, phase, size = 18 }) => {
    const statusIconSize = size == 18 ? 22 : size;

    return (
        <Box
            component="span"
            sx={{
                display: "grid",
                height: size,
                lineHeight: 0,
                placeItems: "center",
                width: size,
            }}
        >
            {idleIcon && (
                <Box
                    component="span"
                    sx={{
                        display: "flex",
                        gridArea: "1 / 1",
                        lineHeight: 0,
                        opacity: phase == null ? 1 : 0,
                        transform: phase == null ? "scale(1)" : "scale(0.82)",
                        transition:
                            phase == "busy"
                                ? "none"
                                : `opacity ${spaceActionTransition}, transform ${spaceActionTransition}`,
                    }}
                >
                    {idleIcon}
                </Box>
            )}
            <Box
                component="span"
                sx={{
                    display: "flex",
                    gridArea: "1 / 1",
                    lineHeight: 0,
                    opacity: phase == "busy" ? 1 : 0,
                    transform: phase == "busy" ? "scale(1)" : "scale(0.82)",
                    transition:
                        phase == "busy"
                            ? "none"
                            : `opacity ${spaceActionTransition}, transform ${spaceActionTransition}`,
                }}
            >
                <Box
                    component="span"
                    sx={{
                        animation: `${spaceActionSpin} 2.4s linear infinite`,
                        display: "flex",
                        lineHeight: 0,
                    }}
                >
                    <HugeiconsIcon
                        icon={Loading03Icon}
                        size={statusIconSize}
                        strokeWidth={1.8}
                    />
                </Box>
            </Box>
            <Box
                component="span"
                sx={{
                    display: "flex",
                    gridArea: "1 / 1",
                    lineHeight: 0,
                    opacity: phase == "done" ? 1 : 0,
                    transform: phase == "done" ? "scale(1)" : "scale(0.82)",
                    transition: `opacity ${spaceActionTransition}, transform ${spaceActionTransition}`,
                }}
            >
                <HugeiconsIcon
                    icon={Tick02Icon}
                    size={statusIconSize}
                    strokeWidth={1.8}
                />
            </Box>
        </Box>
    );
};
