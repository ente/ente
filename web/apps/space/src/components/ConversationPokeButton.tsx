import {
    Cancel01Icon,
    HandPointingRightIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import type { SpaceActionPhase } from "components/ActionFeedback";
import { SpaceActionToast } from "components/ActionToast";
import log from "ente-base/log";
import React from "react";
import {
    spaceDialogBackground,
    spaceSurfaceHover,
    spaceText,
} from "styles/colors";
import { spaceTouchTargetSize } from "styles/touch-targets";

export const SpaceConversationPokeButton = ({
    disabled,
    friendName,
    onPokeFriend,
}: {
    disabled: boolean;
    friendName: string;
    onPokeFriend: (requestID: string) => Promise<void>;
}) => {
    const [phase, setPhase] = React.useState<SpaceActionPhase>();
    const [failed, setFailed] = React.useState(false);
    const requestID = React.useRef<string | undefined>(undefined);

    const poke = async () => {
        if (disabled || phase) return;
        setPhase("busy");
        setFailed(false);
        requestID.current ??= crypto.randomUUID();
        try {
            await onPokeFriend(requestID.current);
            requestID.current = undefined;
            setPhase("done");
        } catch (error) {
            log.error("Failed to send poke", error);
            setFailed(true);
            setPhase(undefined);
        }
    };

    React.useEffect(() => {
        if (phase != "done") return;
        const timeout = window.setTimeout(() => setPhase(undefined), 2100);
        return () => window.clearTimeout(timeout);
    }, [phase]);

    return (
        <>
            <Box
                component="button"
                type="button"
                aria-label={phase == "done" ? "Poked" : `Poke ${friendName}`}
                aria-busy={phase == "busy"}
                aria-live="polite"
                disabled={disabled || phase !== undefined}
                onClick={() => void poke()}
                sx={{
                    alignItems: "center",
                    bgcolor: "transparent",
                    border: 0,
                    borderRadius: "999px",
                    color: phase == "done" ? "#08C225" : spaceText,
                    cursor: disabled || phase ? "default" : "pointer",
                    display: "flex",
                    fontFamily: '"Inter Variable", Inter, sans-serif',
                    fontSize: 13,
                    fontWeight: 600,
                    height: spaceTouchTargetSize,
                    justifyContent: "flex-end",
                    p: 0,
                    pr: "4px",
                    width: "100%",
                    "&:hover:not(:disabled) > span": {
                        bgcolor: spaceSurfaceHover,
                    },
                    "&:focus-visible": {
                        outline: "2px solid #08C225",
                        outlineOffset: 2,
                    },
                }}
            >
                <Box
                    component="span"
                    aria-hidden
                    sx={{
                        alignItems: "center",
                        bgcolor:
                            phase == "done"
                                ? "rgba(8, 194, 37, 0.14)"
                                : spaceDialogBackground,
                        borderRadius: "999px",
                        display: "flex",
                        height: 36,
                        justifyContent: "center",
                        overflow: "hidden",
                        transition:
                            "width 220ms cubic-bezier(0.2, 0.8, 0.2, 1), background-color 160ms ease-out",
                        whiteSpace: "nowrap",
                        width: phase == "done" ? 68 : 36,
                        "& > span": {
                            animation: "spacePokeFeedback 180ms ease-out",
                        },
                        "@keyframes spacePokeFeedback": {
                            from: { opacity: 0, transform: "scale(0.9)" },
                            to: { opacity: 1, transform: "scale(1)" },
                        },
                        "@media (prefers-reduced-motion: reduce)": {
                            transition: "none",
                            "& > span": { animation: "none" },
                        },
                    }}
                >
                    <Box
                        key={phase == "done" ? "done" : "idle"}
                        component="span"
                        sx={{ alignItems: "center", display: "flex" }}
                    >
                        {phase == "done" ? (
                            "Poked"
                        ) : (
                            <HugeiconsIcon
                                icon={HandPointingRightIcon}
                                size={22}
                                strokeWidth={2.2}
                            />
                        )}
                    </Box>
                </Box>
            </Box>
            {failed && (
                <SpaceActionToast
                    animateEntrance
                    closeLabel="Dismiss poke error"
                    icon={<HugeiconsIcon icon={Cancel01Icon} size={20} />}
                    message="Couldn't send poke. Try again."
                    onClose={() => setFailed(false)}
                />
            )}
        </>
    );
};
