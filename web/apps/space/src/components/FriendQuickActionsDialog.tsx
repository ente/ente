import {
    BubbleChatIcon,
    HandPointingRightIcon,
    UserIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Dialog, useMediaQuery } from "@mui/material";
import { SpaceAvatarImage } from "components/AvatarImage";
import type { FriendProfile } from "data/friends";
import log from "ente-base/log";
import { useBrowserBackClose } from "hooks/use-browser-back-close";
import React from "react";
import {
    spaceAppBackgroundColor,
    spaceDialogBackground,
    spaceSurface,
    spaceSurfaceHover,
    spaceText,
} from "styles/colors";

const actionHeight = 40;
const dialogPadding = 12;
const innerRadius = actionHeight / 2;
const dialogRadius = innerRadius + dialogPadding;

interface FriendQuickActionsDialogProps {
    anchorRect: DOMRect;
    avatarUrl?: string | null;
    friend: FriendProfile;
    onClose: () => void;
    onMessage: () => void;
    onPoke: () => Promise<void>;
    onProfile: () => void;
}

export const FriendQuickActionsDialog: React.FC<
    FriendQuickActionsDialogProps
> = ({
    anchorRect,
    avatarUrl,
    friend,
    onClose,
    onMessage,
    onPoke,
    onProfile,
}) => {
    const [open, setOpen] = React.useState(true);
    const [pokePhase, setPokePhase] = React.useState<"busy" | "done" | null>(
        null,
    );
    const [pokeFailed, setPokeFailed] = React.useState(false);
    const paperRef = React.useRef<HTMLDivElement>(null);
    const nameID = React.useId();
    const prefersReducedMotion = useMediaQuery(
        "(prefers-reduced-motion: reduce)",
    );
    const displayName = friend.fullName.trim() || friend.username;
    const { clearBrowserBackState } = useBrowserBackClose({
        open,
        onClose: () => setOpen(false),
        stateKey: "space-friend-quick-actions",
    });

    React.useEffect(() => {
        if (pokePhase != "done") return;
        const timeout = window.setTimeout(() => setPokePhase(null), 2100);
        return () => window.clearTimeout(timeout);
    }, [pokePhase]);

    const navigate = async (action: () => void) => {
        await clearBrowserBackState("back");
        setOpen(false);
        action();
    };

    const poke = async () => {
        if (pokePhase) return;
        setPokePhase("busy");
        setPokeFailed(false);
        try {
            await onPoke();
            setPokePhase("done");
        } catch (error) {
            log.error("Failed to send poke", error);
            setPokePhase(null);
            setPokeFailed(true);
        }
    };

    const actions = [
        {
            label: "Poke",
            icon: HandPointingRightIcon,
            active: pokePhase !== null,
            done: pokePhase == "done",
            disabled: pokePhase !== null,
            busy: pokePhase == "busy",
            onClick: () => void poke(),
        },
        {
            label: "Message",
            icon: BubbleChatIcon,
            onClick: () => void navigate(onMessage),
        },
        {
            label: "Profile",
            icon: UserIcon,
            onClick: () => void navigate(onProfile),
        },
    ];

    return (
        <Dialog
            open={open}
            onClose={() => setOpen(false)}
            aria-labelledby={nameID}
            maxWidth={false}
            transitionDuration={prefersReducedMotion ? 0 : 220}
            sx={{ "--space-dialog-backdrop": "rgba(0 0 0 / 0.64)" }}
            slotProps={{
                paper: {
                    ref: paperRef,
                    sx: {
                        bgcolor: spaceSurface,
                        boxShadow: "0 24px 64px rgba(0, 0, 0, 0.48)",
                        borderRadius: `${dialogRadius}px`,
                        boxSizing: "border-box",
                        display: "flex",
                        flexDirection: "column",
                        m: "16px",
                        maxHeight: "calc(100% - 32px)",
                        maxWidth: "calc(100vw - 32px)",
                        overflow: "hidden",
                        position: "relative",
                        pt: `${dialogPadding}px`,
                        top: -155,
                        width: "288px",
                        "@media (max-height: 720px)": { top: 0 },
                    },
                },
                transition: {
                    onEnter: () => {
                        const paper = paperRef.current;
                        if (!paper || prefersReducedMotion) return;
                        const rect = paper.getBoundingClientRect();
                        const x =
                            anchorRect.x +
                            anchorRect.width / 2 -
                            (rect.x + rect.width / 2);
                        const y =
                            anchorRect.y +
                            anchorRect.height / 2 -
                            (rect.y + rect.height / 2);
                        paper.animate(
                            [
                                {
                                    transform: `translate(${x}px, ${y}px) scale(${anchorRect.width / rect.width})`,
                                    borderRadius: "50%",
                                },
                                {
                                    transform: "none",
                                    borderRadius: `${dialogRadius}px`,
                                },
                            ],
                            {
                                duration: 220,
                                easing: "cubic-bezier(0.2, 0.8, 0.2, 1)",
                            },
                        );
                    },
                    onExited: onClose,
                },
            }}
        >
            <Box
                sx={{
                    alignSelf: "center",
                    aspectRatio: "1",
                    bgcolor: spaceAppBackgroundColor,
                    borderRadius: `${innerRadius}px`,
                    flexShrink: 0,
                    overflow: "hidden",
                    position: "relative",
                    width: `min(calc(100% - ${dialogPadding * 2}px), calc(100svh - ${dialogPadding * 3 + actionHeight + 32}px))`,
                }}
            >
                <SpaceAvatarImage src={avatarUrl} />
                <Box
                    aria-hidden
                    sx={{
                        background:
                            "linear-gradient(rgba(0, 0, 0, 0.52), transparent 55%)",
                        inset: 0,
                        pointerEvents: "none",
                        position: "absolute",
                    }}
                />
                <Box
                    component="h2"
                    id={nameID}
                    sx={{
                        color: "#FFFFFF",
                        display: "-webkit-box",
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 16,
                        fontWeight: 700,
                        left: 24,
                        lineHeight: "22px",
                        m: 0,
                        overflow: "hidden",
                        overflowWrap: "anywhere",
                        position: "absolute",
                        right: 24,
                        textShadow: "0 1px 6px rgba(0, 0, 0, 0.35)",
                        top: 24,
                        WebkitBoxOrient: "vertical",
                        WebkitLineClamp: 2,
                    }}
                >
                    {displayName}
                </Box>
                {pokeFailed && (
                    <Box
                        role="alert"
                        sx={{
                            bgcolor: "rgba(0, 0, 0, 0.7)",
                            borderRadius: "12px",
                            bottom: dialogPadding,
                            color: "#FFFFFF",
                            fontSize: 12,
                            left: dialogPadding,
                            lineHeight: "16px",
                            p: "8px 12px",
                            position: "absolute",
                            right: dialogPadding,
                            textAlign: "center",
                        }}
                    >
                        Couldn’t send your poke. Tap Poke to retry.
                    </Box>
                )}
            </Box>
            <Box
                sx={{
                    display: "grid",
                    gap: "6px",
                    gridTemplateColumns: "repeat(3, minmax(0, 1fr))",
                    p: `${dialogPadding}px`,
                }}
            >
                {actions.map((action, index) => (
                    <Box
                        key={index}
                        component="button"
                        type="button"
                        disabled={action.disabled}
                        aria-busy={action.busy}
                        aria-label={action.done ? "Poke sent" : action.label}
                        aria-live={
                            action.done !== undefined ? "polite" : undefined
                        }
                        onClick={action.onClick}
                        sx={{
                            alignItems: "center",
                            appearance: "none",
                            bgcolor: spaceDialogBackground,
                            border: 0,
                            borderRadius: `${innerRadius}px`,
                            color: action.active
                                ? "color(display-p3 0.0314 0.7608 0.1451)"
                                : spaceText,
                            cursor: action.disabled ? "default" : "pointer",
                            display: "grid",
                            justifyItems: "center",
                            height: actionHeight,
                            minWidth: 0,
                            p: "0 8px",
                            ...(action.label != "Poke" && {
                                transition: "background-color 120ms ease",
                                "&:hover:not(:disabled)": {
                                    bgcolor: spaceSurfaceHover,
                                },
                                "&:active:not(:disabled)": {
                                    bgcolor: spaceAppBackgroundColor,
                                },
                            }),
                            "&:focus-visible": {
                                outline: `2px solid ${spaceText}`,
                                outlineOffset: 2,
                            },
                        }}
                    >
                        <Box
                            component="span"
                            aria-hidden
                            sx={{
                                alignItems: "center",
                                display: "flex",
                                height: 24,
                                justifyContent: "center",
                                width: 24,
                                animation: action.active
                                    ? "spacePokeJab 2000ms ease-in-out"
                                    : "none",
                                "@keyframes spacePokeJab": {
                                    "0%, 100%": {
                                        transform:
                                            "translate(0, 0) rotate(0deg) scale(1)",
                                    },
                                    "27.5%, 52%, 73.75%": {
                                        transform:
                                            "translate(20px, -80px) rotate(-40deg) scale(3)",
                                    },
                                    "41%, 63%": {
                                        transform:
                                            "translate(36px, -94px) rotate(-40deg) scale(3)",
                                    },
                                },
                                "@media (prefers-reduced-motion: reduce)": {
                                    animation: "none",
                                },
                                ...(action.icon == BubbleChatIcon && {
                                    "& svg path:last-of-type": {
                                        display: "none",
                                    },
                                }),
                            }}
                        >
                            <HugeiconsIcon
                                icon={action.icon}
                                size={24}
                                strokeWidth={2.2}
                            />
                        </Box>
                    </Box>
                ))}
            </Box>
        </Dialog>
    );
};
