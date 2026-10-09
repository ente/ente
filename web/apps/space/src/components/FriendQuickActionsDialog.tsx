import {
    BubbleChatIcon,
    Cancel01Icon,
    HandPointingRightIcon,
    Tick02Icon,
    UserIcon,
    UserRemove01Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Dialog, useMediaQuery } from "@mui/material";
import {
    spaceActionDoneDurationMs,
    SpaceActionFeedbackIcon,
    type SpaceActionPhase,
} from "components/ActionFeedback";
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
    onMessage?: () => void;
    onPoke?: () => Promise<void>;
    onProfile?: () => void;
    onUnfriend?: () => void;
    requestActions?: {
        onAccept?: () => Promise<boolean>;
        onCancel: () => Promise<void>;
    };
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
    onUnfriend,
    requestActions,
}) => {
    const [open, setOpen] = React.useState(true);
    const [pokePhase, setPokePhase] = React.useState<"busy" | "done" | null>(
        null,
    );
    const [pokeFailed, setPokeFailed] = React.useState(false);
    const [requestAction, setRequestAction] = React.useState<{
        type: "accept" | "cancel";
        phase: SpaceActionPhase;
    } | null>(null);
    const [requestFailed, setRequestFailed] = React.useState(false);
    const paperRef = React.useRef<HTMLDivElement>(null);
    const nameID = React.useId();
    const prefersReducedMotion = useMediaQuery(
        "(prefers-reduced-motion: reduce)",
    );
    const displayName = requestActions
        ? `@${friend.username}`
        : friend.fullName.trim() || friend.username;
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

    React.useEffect(() => {
        if (requestAction?.phase != "done") return;
        const timeout = window.setTimeout(
            () => setOpen(false),
            spaceActionDoneDurationMs,
        );
        return () => window.clearTimeout(timeout);
    }, [requestAction?.phase]);

    const navigate = async (action: () => void) => {
        await clearBrowserBackState("back");
        setOpen(false);
        action();
    };

    const poke = async () => {
        if (!onPoke || pokePhase) return;
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

    const updateRequest = async (
        action: "accept" | "cancel",
        handler: () => Promise<void> | Promise<boolean>,
    ) => {
        if (requestAction) return;
        setRequestAction({ type: action, phase: "busy" });
        setRequestFailed(false);
        try {
            const accepted = await handler();
            if (action == "accept" && accepted)
                setRequestAction({ type: action, phase: "done" });
            else setOpen(false);
        } catch (error) {
            log.error("Failed to update friend request", error);
            setRequestAction(null);
            setRequestFailed(true);
        }
    };

    const actions = [
        {
            label: "Accept request",
            text: "Accept",
            available: Boolean(requestActions?.onAccept),
            icon: Tick02Icon,
            disabled: requestAction !== null,
            busy:
                requestAction?.type == "accept" &&
                requestAction.phase == "busy",
            done:
                requestAction?.type == "accept" &&
                requestAction.phase == "done",
            doneLabel: "Request accepted",
            phase: requestAction?.type == "accept" ? requestAction.phase : null,
            onClick: () =>
                requestActions?.onAccept &&
                void updateRequest("accept", requestActions.onAccept),
        },
        {
            label: "Cancel request",
            text: requestActions?.onAccept ? "Cancel" : "Cancel request",
            busyText: "Canceling…",
            available: Boolean(requestActions),
            icon: Cancel01Icon,
            disabled: requestAction !== null,
            busy: requestAction?.type == "cancel",
            onClick: () =>
                requestActions &&
                void updateRequest("cancel", requestActions.onCancel),
        },
        {
            label: "Poke",
            available: Boolean(onPoke),
            icon: HandPointingRightIcon,
            active: pokePhase !== null,
            done: pokePhase == "done",
            doneLabel: "Poke sent",
            disabled: pokePhase !== null,
            busy: pokePhase == "busy",
            onClick: () => void poke(),
        },
        {
            label: "Message",
            available: Boolean(onMessage),
            icon: BubbleChatIcon,
            onClick: () => onMessage && void navigate(onMessage),
        },
        {
            label: "Profile",
            available: Boolean(onProfile),
            icon: UserIcon,
            onClick: () => onProfile && void navigate(onProfile),
        },
        {
            label: "Unfriend",
            available: Boolean(onUnfriend),
            icon: UserRemove01Icon,
            onClick: () => onUnfriend && void navigate(onUnfriend),
        },
    ].filter((action) => action.available);

    return (
        <Dialog
            open={open}
            onClose={requestAction ? undefined : () => setOpen(false)}
            aria-labelledby={nameID}
            maxWidth={false}
            transitionDuration={prefersReducedMotion ? 0 : 220}
            sx={{ "--space-dialog-backdrop": "rgba(0 0 0 / 0.64)" }}
            slotProps={{
                paper: {
                    ref: paperRef,
                    sx: {
                        bgcolor: spaceSurface,
                        border: "1px solid #383838",
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
                <SpaceAvatarImage
                    src={requestActions ? undefined : avatarUrl}
                />
                <Box
                    aria-hidden
                    sx={{
                        background:
                            "linear-gradient(rgba(0, 0, 0, 0.28), transparent 40%)",
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
                {(pokeFailed || requestFailed) && (
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
                        {requestFailed
                            ? "Couldn’t update the request. Please try again."
                            : "Couldn’t send your poke. Tap Poke to retry."}
                    </Box>
                )}
            </Box>
            <Box
                sx={{
                    display: "grid",
                    gap: "6px",
                    gridTemplateColumns: `repeat(${actions.length}, minmax(0, 1fr))`,
                    p: `${dialogPadding}px`,
                }}
            >
                {actions.map((action, index) => (
                    <Box
                        key={index}
                        className={
                            action.icon == Tick02Icon ? "green-bg" : undefined
                        }
                        component="button"
                        type="button"
                        disabled={action.disabled}
                        aria-busy={action.busy}
                        aria-label={
                            action.done ? action.doneLabel : action.label
                        }
                        title={action.done ? action.doneLabel : action.label}
                        aria-live={
                            action.done !== undefined ? "polite" : undefined
                        }
                        onClick={action.onClick}
                        sx={{
                            alignItems: "center",
                            appearance: "none",
                            bgcolor:
                                action.icon == Tick02Icon
                                    ? "#08C225"
                                    : spaceDialogBackground,
                            border: 0,
                            borderRadius: `${innerRadius}px`,
                            color:
                                action.icon == Tick02Icon
                                    ? "#FFFFFF"
                                    : action.active
                                      ? "color(display-p3 0.0314 0.7608 0.1451)"
                                      : "#D8D8D8",
                            cursor: action.disabled ? "default" : "pointer",
                            display: "grid",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 14,
                            fontWeight: 600,
                            justifyItems: "center",
                            height: actionHeight,
                            minWidth: 0,
                            p: "0 8px",
                            ...(action.label != "Poke" && {
                                transition: "background-color 120ms ease",
                                "&:hover:not(:disabled)": {
                                    bgcolor:
                                        action.icon == Tick02Icon
                                            ? "#07A820"
                                            : spaceSurfaceHover,
                                },
                                "&:active:not(:disabled)": {
                                    bgcolor:
                                        action.icon == Tick02Icon
                                            ? "#078D1C"
                                            : spaceAppBackgroundColor,
                                },
                            }),
                            "&:focus-visible": {
                                outline: `2px solid ${spaceText}`,
                                outlineOffset: 2,
                            },
                        }}
                    >
                        {action.phase ? (
                            <SpaceActionFeedbackIcon phase={action.phase} />
                        ) : action.text ? (
                            action.busy ? (
                                action.busyText
                            ) : (
                                action.text
                            )
                        ) : (
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
                        )}
                    </Box>
                ))}
            </Box>
        </Dialog>
    );
};
