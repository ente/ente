import {
    Add01Icon,
    ArrowLeft02Icon,
    UserAdd02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Skeleton } from "@mui/material";
import {
    spaceActionDoneDurationMs,
    type SpaceActionPhase,
} from "components/ActionFeedback";
import { SpaceAddFriendDialog } from "components/AddFriendDialog";
import { SpaceAvatarImage } from "components/AvatarImage";
import { ConfirmationActionSheet } from "components/ConfirmationActionSheet";
import { FriendOrbit } from "components/FriendOrbit";
import { FriendQuickActionsDialog } from "components/FriendQuickActionsDialog";
import { FriendStarField } from "components/FriendStarField";
import { SpaceLoadingSpinner } from "components/RouteFallback";
import { SpaceSkipLink } from "components/SkipLink";
import type { FriendProfile } from "data/friends";
import log from "ente-base/log";
import React, { useState } from "react";
import type { SpaceFriendRequest } from "services/space";
import {
    spaceAppBackground,
    spaceSurface,
    spaceSurfaceHover,
    spaceText,
} from "styles/colors";
import { spaceTouchTargetSize } from "styles/touch-targets";

const green = "#08C225";
const avatarSkeletonBackground = spaceSurface;
const textBase = spaceText;
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
    friendRequests: SpaceFriendRequest[];
    friends: FriendProfile[];
    isLoading: boolean;
    onBack: () => void;
    onAcceptFriendRequest: (requestID: number) => Promise<boolean>;
    onDeleteFriendRequest: (requestID: number) => Promise<void>;
    onLoadFriendAvatar?: (friend: FriendProfile) => Promise<string | null>;
    onAddFriend: (username: string) => Promise<"friend" | "requested">;
    onMessage?: (friendID: string) => void;
    onPoke?: (friendID: string, requestID: string) => Promise<void>;
    onOpenFriend?: (friendID: string) => void;
    profileLink?: string;
    username: string;
    onUnfriend?: (friendID: string) => Promise<void> | void;
}

interface FriendIdentityProps {
    avatarUrl?: string | null;
    friend: FriendProfile;
    onLoadAvatar?: () => Promise<string | null | undefined>;
    onOpen?: (event: React.MouseEvent<HTMLButtonElement>) => void;
}

const FriendIdentity: React.FC<FriendIdentityProps> = ({
    avatarUrl,
    friend,
    onLoadAvatar,
    onOpen,
}) => {
    const displayName = friend.fullName.trim() || friend.username.trim();
    const avatarRef = React.useRef<HTMLDivElement | null>(null);
    const [shouldLoadAvatar, setShouldLoadAvatar] = useState(
        Boolean(avatarUrl || !friend.avatarObjectID),
    );

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
            log.warn("Failed to load friend avatar", error);
        });
    }, [avatarUrl, friend.avatarObjectID, onLoadAvatar, shouldLoadAvatar]);

    return (
        <Box
            component="button"
            type="button"
            onClick={onOpen}
            aria-label={`Actions for ${displayName}`}
            aria-haspopup="dialog"
            sx={{
                alignItems: "center",
                bgcolor: "transparent",
                border: 0,
                borderRadius: "50%",
                cursor: "pointer",
                display: "flex",
                flexDirection: "column",
                maxWidth: "100%",
                minWidth: 0,
                p: 0,
                textAlign: "center",
                width: "100%",
                position: "relative",
                transition: "scale 180ms ease",
                "&:hover": { scale: "1.06" },
                "@media (prefers-reduced-motion: reduce)": {
                    transition: "none",
                },
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
                    border: "1px solid #454545",
                    borderRadius: "50%",
                    display: "flex",
                    flexShrink: 0,
                    height: "auto",
                    aspectRatio: "1",
                    justifyContent: "center",
                    overflow: "hidden",
                    width: "100%",
                    boxShadow: "0 8px 28px rgba(0, 0, 0, 0.2)",
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
        </Box>
    );
};

const orbitCircleSx = {
    alignItems: "center",
    bgcolor: spaceSurface,
    border: "1px solid #454545",
    borderRadius: "50%",
    boxSizing: "border-box",
    boxShadow: "0 8px 28px rgba(0, 0, 0, 0.2)",
    color: textBase,
    display: "flex",
    flexDirection: "column",
    fontFamily: '"Inter Variable", Inter, sans-serif',
    gap: "6px",
    height: "100%",
    justifyContent: "center",
    p: "12px",
    textAlign: "center",
    width: "100%",
    "&:focus-visible": { outline: `2px solid ${green}`, outlineOffset: 4 },
} as const;

interface FriendRequestCircleProps {
    onOpen: (event: React.MouseEvent<HTMLButtonElement>) => void;
    request: SpaceFriendRequest;
}

const FriendRequestCircle: React.FC<FriendRequestCircleProps> = ({
    onOpen,
    request,
}) => (
    <Box
        className={request.direction == "received" ? "green-bg" : undefined}
        component="button"
        type="button"
        aria-label={`${request.direction == "received" ? "Friend request from" : "Pending friend request to"} @${request.friend.username}`}
        aria-haspopup="dialog"
        onClick={onOpen}
        sx={{
            ...orbitCircleSx,
            bgcolor: request.direction == "received" ? green : "#444444",
            borderColor:
                request.direction == "received"
                    ? "color(display-p3 0.32 0.88 0.4)"
                    : "#737373",
            boxShadow:
                request.direction == "received"
                    ? "0 0 18px rgba(8, 194, 37, 0.18)"
                    : orbitCircleSx.boxShadow,
            transition: "scale 180ms ease",
            "&:hover": { scale: "1.06" },
            "@media (prefers-reduced-motion: reduce)": { transition: "none" },
        }}
    >
        <Box
            component="span"
            title={`@${request.friend.username}`}
            sx={{
                fontSize: 14,
                fontWeight: 600,
                lineHeight: "18px",
                maxWidth: "100%",
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
            }}
        >
            @{request.friend.username}
        </Box>
    </Box>
);

export const FriendsScreen: React.FC<FriendsScreenProps> = ({
    friendRequests,
    friends,
    isLoading,
    onAcceptFriendRequest,
    onAddFriend,
    onBack,
    onDeleteFriendRequest,
    onLoadFriendAvatar,
    onMessage,
    onPoke,
    onOpenFriend,
    profileLink,
    username,
    onUnfriend,
}) => {
    const [isAddFriendOpen, setIsAddFriendOpen] = React.useState(false);
    const [selectedFriend, setSelectedFriend] = React.useState<{
        friend: FriendProfile;
        anchorRect: DOMRect;
    } | null>(null);
    const [selectedRequest, setSelectedRequest] = React.useState<{
        request: SpaceFriendRequest;
        anchorRect: DOMRect;
    } | null>(null);
    const pokeRequestIDs = React.useRef(new Map<string, string>());
    const [friendToUnfriend, setFriendToUnfriend] =
        React.useState<FriendProfile | null>(null);
    const [isUnfriendOpen, setIsUnfriendOpen] = React.useState(false);
    const [unfriendActionPhase, setUnfriendActionPhase] =
        React.useState<SpaceActionPhase | null>(null);
    const [unfriendErrorMessage, setUnfriendErrorMessage] = React.useState<
        string | null
    >(null);
    const [loadedAvatarURLsByKey, setLoadedAvatarURLsByKey] = React.useState<
        Record<string, string>
    >({});
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
                    log.warn("Failed to load friend avatar", error);
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
        setIsUnfriendOpen(false);
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
                log.error("Failed to unfriend space friend", error);
                setUnfriendActionPhase(null);
                setUnfriendErrorMessage("Couldn't unfriend. Please try again.");
            }
        })();
    };

    React.useEffect(() => {
        if (unfriendActionPhase != "done") return;

        const timeoutID = window.setTimeout(() => {
            setIsUnfriendOpen(false);
        }, spaceActionDoneDurationMs);

        return () => window.clearTimeout(timeoutID);
    }, [unfriendActionPhase]);

    const handleUnfriendSheetExited = () => {
        setFriendToUnfriend(null);
        setUnfriendActionPhase(null);
        setUnfriendErrorMessage(null);
    };

    return (
        <Box
            component="main"
            sx={{
                background: spaceAppBackground,
                color: textBase,
                display: "grid",
                boxSizing: "border-box",
                isolation: "isolate",
                minHeight: "var(--space-page-height, 100svh)",
                overflowX: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
                position: "relative",
            }}
        >
            <FriendStarField />
            <SpaceSkipLink />
            <Box
                sx={{
                    bgcolor: "transparent",
                    boxSizing: "border-box",
                    minHeight: "var(--space-page-height, 100svh)",
                    mx: "auto",
                    position: "relative",
                    width: "100%",
                }}
            >
                <Box
                    component="header"
                    sx={{
                        alignItems: "center",
                        display: "grid",
                        gridTemplateColumns: `${spaceTouchTargetSize}px 1fr ${spaceTouchTargetSize}px`,
                        height: 56,
                        maxWidth: 390,
                        mx: "auto",
                        px: 2,
                        width: "100%",
                    }}
                >
                    <Box
                        component="button"
                        type="button"
                        aria-label="Back"
                        onClick={onBack}
                        sx={{
                            alignItems: "center",
                            bgcolor: "transparent",
                            border: 0,
                            color: textBase,
                            cursor: "pointer",
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
                            bgcolor: spaceAppBackground,
                            color: textBase,
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 18,
                            fontWeight: 700,
                            justifySelf: "center",
                            lineHeight: "24px",
                            m: 0,
                            px: "4px",
                        }}
                    >
                        Friends
                    </Box>
                    <Box
                        component="button"
                        type="button"
                        aria-expanded={isAddFriendOpen}
                        aria-label="Add friend"
                        disabled={isLoading}
                        onClick={() => setIsAddFriendOpen(true)}
                        sx={{
                            alignItems: "center",
                            bgcolor: "transparent",
                            border: 0,
                            color: textBase,
                            cursor: isLoading ? "default" : "pointer",
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

                <SpaceAddFriendDialog
                    friendRequests={friendRequests}
                    friends={friends}
                    onAddFriend={onAddFriend}
                    onClose={() => setIsAddFriendOpen(false)}
                    open={isAddFriendOpen}
                    profileLink={profileLink}
                    username={username}
                />

                <Box
                    component="section"
                    id="space-main-content"
                    aria-label="Friends"
                    tabIndex={-1}
                >
                    {isLoading ? (
                        <Box
                            sx={{
                                display: "grid",
                                inset: 0,
                                placeItems: "center",
                                position: "absolute",
                                pointerEvents: "none",
                            }}
                        >
                            <SpaceLoadingSpinner ariaLabel="Loading friends" />
                        </Box>
                    ) : (
                        <FriendOrbit
                            initialOuterID="add-friend"
                            items={[
                                ...friends.map((friend) => ({
                                    id: friend.id,
                                    content: (
                                        <FriendIdentity
                                            avatarUrl={loadedAvatarURLFor(
                                                friend,
                                            )}
                                            friend={friend}
                                            onLoadAvatar={() =>
                                                loadFriendAvatar(friend)
                                            }
                                            onOpen={(event) =>
                                                setSelectedFriend({
                                                    friend,
                                                    anchorRect:
                                                        event.currentTarget.getBoundingClientRect(),
                                                })
                                            }
                                        />
                                    ),
                                })),
                                ...friendRequests.map((request) => ({
                                    id: request.friend.id,
                                    fixedSize: 120,
                                    content: (
                                        <FriendRequestCircle
                                            request={request}
                                            onOpen={(event) =>
                                                setSelectedRequest({
                                                    request,
                                                    anchorRect:
                                                        event.currentTarget.getBoundingClientRect(),
                                                })
                                            }
                                        />
                                    ),
                                })),
                                {
                                    id: "add-friend",
                                    fixedSize: 64,
                                    content: (
                                        <Box
                                            component="button"
                                            type="button"
                                            aria-label="Add friend"
                                            aria-haspopup="dialog"
                                            aria-expanded={isAddFriendOpen}
                                            onClick={() =>
                                                setIsAddFriendOpen(true)
                                            }
                                            sx={{
                                                ...orbitCircleSx,
                                                transition: "scale 180ms ease",
                                                "&:hover": {
                                                    bgcolor: spaceSurfaceHover,
                                                    scale: "1.06",
                                                },
                                                "@media (prefers-reduced-motion: reduce)":
                                                    { transition: "none" },
                                            }}
                                        >
                                            <HugeiconsIcon
                                                icon={Add01Icon}
                                                size={28}
                                                strokeWidth={1.8}
                                            />
                                        </Box>
                                    ),
                                },
                            ]}
                        />
                    )}
                </Box>
            </Box>
            {selectedRequest && (
                <FriendQuickActionsDialog
                    anchorRect={selectedRequest.anchorRect}
                    friend={selectedRequest.request.friend}
                    onClose={() => setSelectedRequest(null)}
                    requestActions={{
                        onAccept:
                            selectedRequest.request.direction == "received"
                                ? () =>
                                      onAcceptFriendRequest(
                                          selectedRequest.request.requestId,
                                      )
                                : undefined,
                        onCancel: () =>
                            onDeleteFriendRequest(
                                selectedRequest.request.requestId,
                            ),
                    }}
                />
            )}
            {selectedFriend && (
                <FriendQuickActionsDialog
                    anchorRect={selectedFriend.anchorRect}
                    avatarUrl={loadedAvatarURLFor(selectedFriend.friend)}
                    friend={selectedFriend.friend}
                    onClose={() => setSelectedFriend(null)}
                    onMessage={
                        onMessage
                            ? () => onMessage(selectedFriend.friend.id)
                            : undefined
                    }
                    onPoke={
                        onPoke
                            ? async () => {
                                  const friendID = selectedFriend.friend.id;
                                  const requestID =
                                      pokeRequestIDs.current.get(friendID) ??
                                      crypto.randomUUID();
                                  pokeRequestIDs.current.set(
                                      friendID,
                                      requestID,
                                  );
                                  await onPoke(friendID, requestID);
                                  pokeRequestIDs.current.delete(friendID);
                              }
                            : undefined
                    }
                    onProfile={
                        onOpenFriend
                            ? () => onOpenFriend(selectedFriend.friend.id)
                            : undefined
                    }
                    onUnfriend={
                        onUnfriend
                            ? () => {
                                  setUnfriendErrorMessage(null);
                                  setFriendToUnfriend(selectedFriend.friend);
                                  setIsUnfriendOpen(true);
                              }
                            : undefined
                    }
                />
            )}
            <ConfirmationActionSheet
                open={isUnfriendOpen}
                title={`Unfriend ${friendToUnfriend?.fullName.trim().split(/\s+/)[0] || friendToUnfriend?.username}?`}
                description="You’ll no longer see each other’s posts or message each other."
                confirmLabel="Unfriend"
                confirmActionPhase={unfriendActionPhase}
                confirmDisabled={isUnfriendActionRunning}
                errorMessage={unfriendErrorMessage}
                cancelDisabled={isUnfriendActionRunning}
                onCancel={cancelUnfriend}
                onConfirm={confirmUnfriend}
                onExited={handleUnfriendSheetExited}
            />
        </Box>
    );
};
