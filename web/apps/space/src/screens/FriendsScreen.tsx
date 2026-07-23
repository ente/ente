import {
    ArrowLeft02Icon,
    MoreVerticalIcon,
    UserAdd02Icon,
    UserRemove01Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Menu, MenuItem, Skeleton } from "@mui/material";
import { ConfirmationActionSheet } from "components/ConfirmationActionSheet";
import {
    spaceActionDoneDurationMs,
    type SpaceActionPhase,
} from "components/SpaceActionFeedback";
import { SpaceAvatarImage } from "components/SpaceAvatarImage";
import { SpaceInviteFriendsDialog } from "components/SpaceInviteFriendsDialog";
import { SpaceShareInviteButton } from "components/SpaceShareInviteButton";
import type { FriendProfile } from "data/friends";
import React, { useState } from "react";
import { spaceTouchTargetSize } from "styles/touchTargets";

export const friendsBackground = "#FFFFFF";

const green = "#08C225";
const avatarSkeletonBackground = "#E6E6E6";
const textBase = "#000";
const textStrong = "#303030";
const textSoft = "#777777";
const dangerColor = "#F63A3A";
const friendAvatarLoadRootMargin = "800px 0px";

const friendAvatarCacheKey = (friend: FriendProfile) =>
    [
        friend.id,
        friend.avatarKeyVersion ?? "",
        friend.avatarObjectID ?? "",
        friend.avatarUpdatedAt ?? "",
        friend.avatarSize ?? "",
    ].join(":");

interface FriendsScreenProps {
    friends: FriendProfile[];
    onLoadFriendAvatar?: (friend: FriendProfile) => Promise<string | null>;
    onBack?: () => void;
    onOpenFriend?: (friendID: string) => void;
    profileLink?: string;
    onUnfriend?: (friendID: string) => Promise<void> | void;
}

interface FriendRowProps {
    avatarUrl?: string | null;
    friend: FriendProfile;
    onLoadAvatar?: () => Promise<string | null | undefined>;
    onOpenFriend?: (friendID: string) => void;
    onUnfriend?: (friendID: string) => void;
}

const FriendRow: React.FC<FriendRowProps> = ({
    avatarUrl,
    friend,
    onLoadAvatar,
    onOpenFriend,
    onUnfriend,
}) => {
    const [actionsAnchor, setActionsAnchor] = useState<HTMLElement | null>(
        null,
    );
    const isActionsOpen = Boolean(actionsAnchor);
    const actionsMenuID = `friend-actions-menu-${friend.id}`;
    const actionsButtonID = `friend-actions-button-${friend.id}`;
    const displayName = friend.fullName.trim() || friend.username.trim();
    const avatarRef = React.useRef<HTMLDivElement | null>(null);
    const [shouldLoadAvatar, setShouldLoadAvatar] = useState(
        Boolean(avatarUrl || !friend.avatarObjectID),
    );

    const closeActions = () => setActionsAnchor(null);

    const unfriend = () => {
        closeActions();
        onUnfriend?.(friend.id);
    };

    React.useEffect(() => {
        if (avatarUrl) setShouldLoadAvatar(true);
    }, [avatarUrl]);

    React.useEffect(() => {
        if (shouldLoadAvatar || avatarUrl || !friend.avatarObjectID) return;
        const element = avatarRef.current;
        if (!element) return;
        if (
            typeof window == "undefined" ||
            !("IntersectionObserver" in window)
        ) {
            setShouldLoadAvatar(true);
            return;
        }

        const observer = new IntersectionObserver(
            (entries) => {
                if (entries.some((entry) => entry.isIntersecting)) {
                    setShouldLoadAvatar(true);
                    observer.disconnect();
                }
            },
            { rootMargin: friendAvatarLoadRootMargin },
        );
        observer.observe(element);
        return () => observer.disconnect();
    }, [avatarUrl, friend.avatarObjectID, shouldLoadAvatar]);

    React.useEffect(() => {
        if (!shouldLoadAvatar || avatarUrl || !friend.avatarObjectID) return;
        void onLoadAvatar?.().catch((error: unknown) => {
            console.warn("Failed to load friend avatar", error);
        });
    }, [avatarUrl, friend.avatarObjectID, onLoadAvatar, shouldLoadAvatar]);

    return (
        <Box
            component="li"
            sx={{
                alignItems: "center",
                display: "grid",
                gridTemplateColumns: `minmax(0, 1fr) ${spaceTouchTargetSize}px`,
                gap: "12px",
                listStyle: "none",
                minHeight: 72,
                px: "18px",
                py: "12px",
                width: "100%",
            }}
        >
            <Box
                component={onOpenFriend ? "button" : "div"}
                type={onOpenFriend ? "button" : undefined}
                onClick={
                    onOpenFriend ? () => onOpenFriend(friend.id) : undefined
                }
                sx={{
                    alignItems: "center",
                    bgcolor: "transparent",
                    border: 0,
                    borderRadius: "12px",
                    cursor: onOpenFriend ? "pointer" : "default",
                    display: "flex",
                    gap: "12px",
                    maxWidth: "100%",
                    minWidth: 0,
                    p: 0,
                    textAlign: "left",
                    width: "fit-content",
                    "&:focus-visible": {
                        outline: `2px solid ${green}`,
                        outlineOffset: 2,
                    },
                }}
            >
                <Box
                    ref={avatarRef}
                    sx={{
                        alignItems: "center",
                        bgcolor: avatarSkeletonBackground,
                        borderRadius: "50%",
                        display: "flex",
                        flexShrink: 0,
                        height: 48,
                        justifyContent: "center",
                        overflow: "hidden",
                        width: 48,
                    }}
                >
                    {avatarUrl || !friend.avatarObjectID ? (
                        <SpaceAvatarImage src={avatarUrl} />
                    ) : (
                        <Skeleton
                            variant="circular"
                            sx={{
                                bgcolor: avatarSkeletonBackground,
                                height: "100%",
                                transform: "none",
                                width: "100%",
                            }}
                        />
                    )}
                </Box>
                <Box
                    sx={{
                        display: "flex",
                        flex: "0 1 auto",
                        flexDirection: "column",
                        justifyContent: "center",
                        minWidth: 0,
                    }}
                >
                    <Box
                        sx={{
                            color: textStrong,
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 15,
                            fontWeight: 700,
                            lineHeight: "20px",
                            minWidth: 0,
                            overflow: "hidden",
                            textOverflow: "ellipsis",
                            whiteSpace: "nowrap",
                        }}
                    >
                        {displayName}
                    </Box>
                    <Box
                        sx={{
                            color: textSoft,
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 13,
                            fontWeight: 600,
                            lineHeight: "18px",
                            minWidth: 0,
                            overflow: "hidden",
                            textOverflow: "ellipsis",
                            whiteSpace: "nowrap",
                        }}
                    >
                        @{friend.username}
                    </Box>
                </Box>
            </Box>
            <Box
                component="button"
                id={actionsButtonID}
                type="button"
                aria-label={`Actions for ${displayName}`}
                aria-controls={isActionsOpen ? actionsMenuID : undefined}
                aria-expanded={isActionsOpen ? "true" : undefined}
                aria-haspopup="menu"
                onClick={(event) => setActionsAnchor(event.currentTarget)}
                sx={{
                    alignItems: "center",
                    bgcolor: "transparent",
                    border: 0,
                    color: textBase,
                    cursor: "pointer",
                    display: "flex",
                    height: spaceTouchTargetSize,
                    justifyContent: "flex-end",
                    justifySelf: "flex-end",
                    p: 0,
                    width: spaceTouchTargetSize,
                    "&:focus-visible": {
                        outline: `2px solid ${green}`,
                        outlineOffset: 2,
                    },
                }}
            >
                <HugeiconsIcon
                    icon={MoreVerticalIcon}
                    size={20}
                    strokeWidth={1.8}
                />
            </Box>
            <Menu
                id={actionsMenuID}
                anchorEl={actionsAnchor}
                open={isActionsOpen}
                onClose={closeActions}
                anchorOrigin={{ horizontal: "right", vertical: "bottom" }}
                transformOrigin={{ horizontal: "right", vertical: "top" }}
                slotProps={{
                    paper: {
                        sx: {
                            borderRadius: "16px",
                            boxShadow: "0 14px 40px rgba(0, 0, 0, 0.16)",
                            mt: "6px",
                            minWidth: 0,
                            p: "4px",
                            width: "max-content",
                        },
                    },
                    list: { "aria-labelledby": actionsButtonID, sx: { p: 0 } },
                }}
            >
                <MenuItem
                    disableRipple
                    onClick={unfriend}
                    sx={{
                        borderRadius: "10px",
                        color: dangerColor,
                        gap: "8px",
                        minHeight: spaceTouchTargetSize,
                        px: "9px",
                        py: "7px",
                        whiteSpace: "nowrap",
                        "&.Mui-focusVisible": {
                            bgcolor: "rgba(246, 58, 58, 0.06)",
                        },
                        "&:active": { bgcolor: "rgba(246, 58, 58, 0.06)" },
                        "&:hover": { bgcolor: "rgba(246, 58, 58, 0.06)" },
                    }}
                >
                    <HugeiconsIcon
                        icon={UserRemove01Icon}
                        size={18}
                        strokeWidth={1.8}
                    />
                    <Box
                        sx={{
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 13,
                            fontWeight: 650,
                            lineHeight: "18px",
                        }}
                    >
                        Unfriend
                    </Box>
                </MenuItem>
            </Menu>
        </Box>
    );
};

export const FriendsScreen: React.FC<FriendsScreenProps> = ({
    friends,
    onLoadFriendAvatar,
    onBack,
    onOpenFriend,
    profileLink,
    onUnfriend,
}) => {
    const [friendToUnfriend, setFriendToUnfriend] =
        React.useState<FriendProfile | null>(null);
    const [unfriendActionPhase, setUnfriendActionPhase] =
        React.useState<SpaceActionPhase | null>(null);
    const [unfriendErrorMessage, setUnfriendErrorMessage] = React.useState<
        string | null
    >(null);
    const [loadedAvatarURLsByKey, setLoadedAvatarURLsByKey] = React.useState<
        Record<string, string>
    >({});
    const [isInviteDialogOpen, setIsInviteDialogOpen] = React.useState(false);
    const [isInviteSharing, setIsInviteSharing] = React.useState(false);
    const avatarLoadsInFlightRef = React.useRef<
        Map<string, Promise<string | null | undefined>>
    >(new Map());
    const isUnfriendActionRunning = unfriendActionPhase != null;

    const loadedAvatarURLFor = React.useCallback(
        (friend: FriendProfile) =>
            friend.avatarUrl ??
            loadedAvatarURLsByKey[friendAvatarCacheKey(friend)],
        [loadedAvatarURLsByKey],
    );

    const loadFriendAvatar = React.useCallback(
        (friend: FriendProfile) => {
            const loadedAvatarUrl = loadedAvatarURLFor(friend);
            if (loadedAvatarUrl) return Promise.resolve(loadedAvatarUrl);
            if (!friend.avatarObjectID || !onLoadFriendAvatar) {
                return Promise.resolve(undefined);
            }

            const cacheKey = friendAvatarCacheKey(friend);
            const inFlight = avatarLoadsInFlightRef.current.get(cacheKey);
            if (inFlight) return inFlight;

            const load = onLoadFriendAvatar(friend)
                .then((avatarUrl) => {
                    if (avatarUrl) {
                        setLoadedAvatarURLsByKey((currentURLs) =>
                            currentURLs[cacheKey] == avatarUrl
                                ? currentURLs
                                : { ...currentURLs, [cacheKey]: avatarUrl },
                        );
                    }
                    return avatarUrl;
                })
                .catch((error: unknown) => {
                    console.warn("Failed to load friend avatar", error);
                    return undefined;
                })
                .finally(() => {
                    avatarLoadsInFlightRef.current.delete(cacheKey);
                });
            avatarLoadsInFlightRef.current.set(cacheKey, load);
            return load;
        },
        [loadedAvatarURLFor, onLoadFriendAvatar],
    );

    const cancelUnfriend = () => {
        if (isUnfriendActionRunning) return;
        setUnfriendErrorMessage(null);
        setFriendToUnfriend(null);
    };

    const confirmUnfriend = () => {
        if (!friendToUnfriend || isUnfriendActionRunning) return;
        setUnfriendErrorMessage(null);
        setUnfriendActionPhase("busy");
        void (async () => {
            try {
                await Promise.resolve(onUnfriend?.(friendToUnfriend.id));
                setUnfriendActionPhase("done");
            } catch (error) {
                console.error("Failed to unfriend space friend", error);
                setUnfriendActionPhase(null);
                setUnfriendErrorMessage("Couldn't unfriend. Please try again.");
            }
        })();
    };

    React.useEffect(() => {
        if (unfriendActionPhase != "done") return;

        const timeoutID = window.setTimeout(() => {
            setFriendToUnfriend(null);
        }, spaceActionDoneDurationMs);

        return () => window.clearTimeout(timeoutID);
    }, [unfriendActionPhase]);

    const handleUnfriendSheetExited = () => {
        setUnfriendActionPhase(null);
        setUnfriendErrorMessage(null);
    };

    const openInviteDialog = () => setIsInviteDialogOpen(true);

    const closeInviteDialog = () => setIsInviteDialogOpen(false);

    return (
        <Box
            component="main"
            sx={{
                bgcolor: friendsBackground,
                color: textBase,
                display: "grid",
                boxSizing: "border-box",
                minHeight: "100svh",
                overflowX: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
            }}
        >
            <Box
                sx={{
                    bgcolor: friendsBackground,
                    boxSizing: "border-box",
                    minHeight: "100svh",
                    mx: "auto",
                    position: "relative",
                    width: "100%",
                    "@media (min-width: 600px)": { maxWidth: 390 },
                }}
            >
                <Box
                    component="header"
                    sx={{
                        alignItems: "center",
                        display: "grid",
                        gridTemplateColumns: `${spaceTouchTargetSize}px 1fr ${spaceTouchTargetSize}px`,
                        height: 56,
                        px: 2,
                        width: "100%",
                    }}
                >
                    <Box
                        component="button"
                        type="button"
                        aria-label="Back to profile"
                        onClick={onBack}
                        sx={{
                            alignItems: "center",
                            bgcolor: "transparent",
                            border: 0,
                            color: textBase,
                            cursor: onBack ? "pointer" : "default",
                            display: "flex",
                            height: spaceTouchTargetSize,
                            justifyContent: "flex-start",
                            ml: "-2px",
                            p: 0,
                            width: spaceTouchTargetSize,
                            "&:focus-visible": {
                                borderRadius: "50%",
                                outline: `2px solid ${green}`,
                                outlineOffset: 2,
                            },
                        }}
                    >
                        <HugeiconsIcon
                            icon={ArrowLeft02Icon}
                            size={24}
                            strokeWidth={1.8}
                        />
                    </Box>
                    <Box
                        component="h1"
                        sx={{
                            color: textBase,
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 18,
                            fontWeight: 700,
                            justifySelf: "center",
                            lineHeight: "24px",
                            m: 0,
                        }}
                    >
                        Friends
                    </Box>
                    <Box
                        component="button"
                        type="button"
                        aria-label="Invite friends"
                        disabled={!profileLink}
                        onClick={openInviteDialog}
                        sx={{
                            alignItems: "center",
                            bgcolor: "transparent",
                            border: 0,
                            color: textBase,
                            cursor: profileLink ? "pointer" : "default",
                            display: "flex",
                            height: spaceTouchTargetSize,
                            justifyContent: "flex-end",
                            justifySelf: "flex-end",
                            p: 0,
                            width: spaceTouchTargetSize,
                            "&:disabled": { opacity: 0.45 },
                            "&:focus-visible": {
                                outline: `2px solid ${green}`,
                                outlineOffset: 2,
                            },
                        }}
                    >
                        <HugeiconsIcon
                            icon={UserAdd02Icon}
                            size={22}
                            strokeWidth={1.8}
                        />
                    </Box>
                </Box>

                {friends.length > 0 ? (
                    <Box
                        component="ul"
                        sx={{
                            display: "flex",
                            flexDirection: "column",
                            gap: "4px",
                            m: 0,
                            mt: "8px",
                            p: 0,
                            width: "100%",
                        }}
                    >
                        {friends.map((friend) => (
                            <FriendRow
                                key={friend.id}
                                avatarUrl={loadedAvatarURLFor(friend)}
                                friend={friend}
                                onLoadAvatar={() => loadFriendAvatar(friend)}
                                onOpenFriend={onOpenFriend}
                                onUnfriend={() => {
                                    setUnfriendErrorMessage(null);
                                    setFriendToUnfriend(friend);
                                }}
                            />
                        ))}
                    </Box>
                ) : (
                    <Box
                        sx={{
                            alignItems: "center",
                            color: textSoft,
                            display: "flex",
                            flexDirection: "column",
                            inset: 0,
                            justifyContent: "center",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 14,
                            fontWeight: 600,
                            lineHeight: "20px",
                            pointerEvents: "none",
                            position: "absolute",
                            px: "24px",
                            textAlign: "center",
                        }}
                    >
                        No friends yet
                        <SpaceShareInviteButton
                            profileLink={profileLink}
                            sharing={isInviteSharing}
                            onShareError={(error) =>
                                console.error(
                                    "Failed to share space invite",
                                    error,
                                )
                            }
                            onSharingChange={setIsInviteSharing}
                            sx={{
                                alignItems: "center",
                                bgcolor: "#E8E8E8",
                                border: 0,
                                borderRadius: "18px",
                                color: textBase,
                                cursor:
                                    profileLink && !isInviteSharing
                                        ? "pointer"
                                        : "default",
                                display: "inline-flex",
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 13,
                                fontWeight: 600,
                                gap: "6px",
                                height: spaceTouchTargetSize,
                                justifyContent: "center",
                                lineHeight: "18px",
                                mt: "22px",
                                pointerEvents: "auto",
                                px: "14px",
                                whiteSpace: "nowrap",
                                "&:disabled": { opacity: 0.45 },
                                "&:focus-visible": {
                                    outline: `2px solid ${green}`,
                                    outlineOffset: 2,
                                },
                                "&:hover":
                                    profileLink && !isInviteSharing
                                        ? { bgcolor: "#DEDEDE" }
                                        : undefined,
                            }}
                        />
                    </Box>
                )}
            </Box>
            <ConfirmationActionSheet
                open={Boolean(friendToUnfriend)}
                title="Are you sure you want to unfriend?"
                confirmLabel="Yes, unfriend"
                confirmActionPhase={unfriendActionPhase}
                confirmDisabled={isUnfriendActionRunning}
                errorMessage={unfriendErrorMessage}
                cancelDisabled={isUnfriendActionRunning}
                onCancel={cancelUnfriend}
                onConfirm={confirmUnfriend}
                onExited={handleUnfriendSheetExited}
            />
            <SpaceInviteFriendsDialog
                open={isInviteDialogOpen}
                profileLink={profileLink}
                sharing={isInviteSharing}
                onClose={closeInviteDialog}
                onSharingChange={setIsInviteSharing}
            />
        </Box>
    );
};
