import { ArrowLeft02Icon, UserAdd02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Skeleton } from "@mui/material";
import { SpaceAddFriendDialog } from "components/AddFriendDialog";
import { SpaceAvatarImage } from "components/AvatarImage";
import { FriendOrbit } from "components/FriendOrbit";
import {
    FriendRequestSheet,
    type FriendRequestSheetActions,
} from "components/FriendRequestSheet";
import { FriendStarField } from "components/FriendStarField";
import { SpaceLoadingSpinner } from "components/RouteFallback";
import { SpaceSkipLink } from "components/SkipLink";
import type { FriendProfile } from "data/friends";
import log from "ente-base/log";
import React, { useState } from "react";
import type { SpaceFriendRequest, SpaceFriendSuggestion } from "services/space";
import { spaceEmptyStateButtonSx } from "styles/buttons";
import {
    spaceAppBackground,
    spaceSurface,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import { spaceTouchTargetSize } from "styles/touch-targets";

const green = "#08C225";
const avatarSkeletonBackground = spaceSurface;
const textBase = spaceText;
const friendAvatarLoadRootMargin = "800px 0px";

const orbitGlassSx = {
    isolation: "isolate",
    overflow: "hidden",
    position: "relative",
    "&::after": {
        content: '""',
        borderRadius: "inherit",
        inset: 0,
        pointerEvents: "none",
        position: "absolute",
        zIndex: 1,
        opacity: 0.9,
        background:
            "linear-gradient(180deg, rgba(255, 255, 255, 0.95), rgba(255, 255, 255, 0.75) 4%, transparent 24%, transparent 76%, rgba(230, 240, 255, 0.55) 96%, rgba(230, 240, 255, 0.75))",
        mask: "radial-gradient(farthest-side, transparent 94%, #000 98%)",
        animation: "spaceFriendGlassShimmer 12s ease-in-out infinite alternate",
    },
    "@keyframes spaceFriendGlassShimmer": {
        from: { transform: "rotate(-5deg)", opacity: 0.85 },
        to: { transform: "rotate(5deg)", opacity: 1 },
    },
    "@media (prefers-reduced-motion: reduce)": {
        "&::after": { animation: "none" },
    },
} as const;

type OrbitFriend = Omit<FriendProfile, "friendsCount">;
type OrbitContact = FriendRequestSheetActions & {
    id: string;
    isSuggestion?: boolean;
};

const friendAvatarCacheKey = (friend: OrbitFriend) =>
    [
        friend.id,
        friend.avatarKeyVersion ?? "",
        friend.avatarObjectID ?? "",
        friend.avatarUpdatedAt ?? "",
        friend.avatarSize ?? "",
    ].join(":");

interface FriendsScreenProps {
    friendRequests: SpaceFriendRequest[];
    suggestions: SpaceFriendSuggestion[];
    friends: FriendProfile[];
    isLoading: boolean;
    onBack: () => void;
    onAcceptFriendRequest: (requestID: number) => Promise<boolean>;
    onDeleteFriendRequest: (requestID: number) => Promise<void>;
    onLoadFriendAvatar?: (friend: OrbitFriend) => Promise<string | null>;
    onAddFriend: (
        target: string | SpaceFriendSuggestion,
    ) => Promise<"friend" | "requested">;
    onHideSuggestion: (spaceId: string) => Promise<void>;
    onOpenFriend: (friendID: string) => void;
    profileLink?: string;
    username: string;
}

interface FriendIdentityProps {
    avatarUrl?: string | null;
    friend: OrbitFriend;
    showsUsername: boolean;
    opensDialog: boolean;
    onLoadAvatar?: () => Promise<string | null | undefined>;
    onOpen: () => void;
}

const FriendIdentity: React.FC<FriendIdentityProps> = ({
    avatarUrl,
    friend,
    showsUsername,
    opensDialog,
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

    const profileLabel = `Open ${displayName}'s profile`;
    if (showsUsername)
        return (
            <OrbitUsernameCircle
                variant="suggested"
                username={friend.username}
                ariaLabel={profileLabel}
                opensDialog={opensDialog}
                onOpen={onOpen}
            />
        );

    return (
        <Box
            component="button"
            type="button"
            onClick={onOpen}
            aria-label={profileLabel}
            aria-haspopup={opensDialog ? "dialog" : undefined}
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
                "&:focus-visible": {
                    outline: `2px solid ${green}`,
                    outlineOffset: 2,
                },
            }}
        >
            <Box
                ref={avatarRef}
                sx={{
                    ...orbitGlassSx,
                    alignItems: "center",
                    bgcolor: avatarSkeletonBackground,
                    border: "1px solid #454545",
                    borderRadius: "50%",
                    display: "flex",
                    flexShrink: 0,
                    height: "auto",
                    aspectRatio: "1",
                    justifyContent: "center",
                    width: "100%",
                    boxShadow: "0 8px 28px rgba(0, 0, 0, 0.2)",
                }}
            >
                {avatarUrl ? (
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
    ...orbitGlassSx,
    alignItems: "center",
    aspectRatio: "1",
    border: "1px solid #454545",
    borderRadius: "50%",
    boxSizing: "border-box",
    boxShadow: "0 8px 28px rgba(0, 0, 0, 0.2)",
    color: textBase,
    display: "flex",
    flexDirection: "column",
    fontFamily: '"Inter Variable", Inter, sans-serif',
    gap: "6px",
    justifyContent: "center",
    p: "16px",
    textAlign: "center",
    width: "100%",
    "&:focus-visible": { outline: `2px solid ${green}`, outlineOffset: 4 },
} as const;

const friendCircleAppearance = {
    received: {
        fill: green,
        border: green,
        pill: "#FFFFFF",
        text: "#000000",
        label: "Friend request from",
    },
    sent: {
        fill: spaceSurface,
        border: "#737373",
        pill: green,
        text: spaceText,
        label: "Pending friend request to",
    },
    suggested: {
        fill: spaceSurface,
        border: "#737373",
        pill: "#303030",
        text: "rgba(255, 255, 255, 0.9)",
        label: "Suggested friend",
    },
};

const OrbitUsername = ({
    username,
    bgcolor,
    color,
}: {
    username: string;
    bgcolor: string;
    color: string;
}) => (
    <Box
        component="span"
        title={`@${username}`}
        sx={{
            bgcolor,
            borderRadius: "999px",
            color,
            fontSize: 12,
            fontWeight: 500,
            lineHeight: "18px",
            maxWidth: "100%",
            overflowWrap: "anywhere",
            px: "8px",
            py: "4px",
        }}
    >
        @{username}
    </Box>
);

interface OrbitUsernameCircleProps {
    onOpen: () => void;
    variant: keyof typeof friendCircleAppearance;
    username: string;
    ariaLabel?: string;
    opensDialog?: boolean;
    isSuggestion?: boolean;
}

const OrbitUsernameCircle: React.FC<OrbitUsernameCircleProps> = ({
    onOpen,
    variant,
    username,
    ariaLabel,
    opensDialog = true,
    isSuggestion = false,
}) => {
    const appearance = friendCircleAppearance[variant];
    return (
        <Box
            component="button"
            type="button"
            aria-label={ariaLabel ?? `${appearance.label} @${username}`}
            aria-haspopup={opensDialog ? "dialog" : undefined}
            onClick={onOpen}
            sx={[
                {
                    ...orbitCircleSx,
                    bgcolor: appearance.fill,
                    borderColor: appearance.border,
                },
                isSuggestion && {
                    bgcolor: "rgba(0, 0, 0, 0.69)",
                    borderColor: "#202020",
                    "&::after": { filter: "brightness(0.2)" },
                },
            ]}
        >
            <OrbitUsername
                username={username}
                bgcolor={isSuggestion ? "#202020" : appearance.pill}
                color={appearance.text}
            />
        </Box>
    );
};

export const FriendsScreen: React.FC<FriendsScreenProps> = ({
    friendRequests,
    suggestions,
    friends,
    isLoading,
    onAcceptFriendRequest,
    onAddFriend,
    onBack,
    onDeleteFriendRequest,
    onHideSuggestion,
    onLoadFriendAvatar,
    onOpenFriend,
    profileLink,
    username,
}) => {
    const [isAddFriendOpen, setIsAddFriendOpen] = React.useState(false);
    const knownSpaceIDs = new Set([
        ...friends.map((friend) => friend.id),
        ...friendRequests.map((request) => request.friend.id),
    ]);
    const contacts: OrbitContact[] = [
        ...friendRequests.map((request) => ({
            id: request.friend.id,
            username: request.friend.username,
            direction: request.direction,
            onPrimary:
                request.direction == "received"
                    ? () => onAcceptFriendRequest(request.requestId)
                    : undefined,
            onSecondary: () => onDeleteFriendRequest(request.requestId),
        })),
        ...suggestions
            .filter((suggestion) => !knownSpaceIDs.has(suggestion.spaceId))
            .map((suggestion) => ({
                id: suggestion.spaceId,
                isSuggestion: true,
                username: suggestion.spaceSlug,
                direction: "suggested" as const,
                onPrimary: async () =>
                    (await onAddFriend(suggestion)) == "requested",
                onSecondary: () => onHideSuggestion(suggestion.spaceId),
            })),
    ];

    return (
        <>
            <FriendsOrbitView
                title="Friends"
                friends={friends}
                contacts={contacts}
                isLoading={isLoading}
                onOpenFriend={onOpenFriend}
                onLoadFriendAvatar={onLoadFriendAvatar}
                onBack={onBack}
                headerAction={
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
                }
                emptyState={
                    <>
                        <Box component="p" sx={{ m: 0, maxWidth: 260 }}>
                            Invite your friends and family. Share everyday
                            photos and keep up with each other.
                        </Box>
                        <Box
                            className="green-bg"
                            component="button"
                            type="button"
                            aria-haspopup="dialog"
                            onClick={() => setIsAddFriendOpen(true)}
                            sx={spaceEmptyStateButtonSx}
                        >
                            <HugeiconsIcon
                                icon={UserAdd02Icon}
                                size={18}
                                strokeWidth={1.8}
                            />
                            Add friends
                        </Box>
                    </>
                }
            />
            <SpaceAddFriendDialog
                friendRequests={friendRequests}
                friends={friends}
                onAddFriend={onAddFriend}
                onClose={() => setIsAddFriendOpen(false)}
                open={isAddFriendOpen}
                profileLink={profileLink}
                username={username}
            />
        </>
    );
};

export const FriendsOrbitView = ({
    title,
    friends,
    contacts,
    isLoading,
    onBack,
    onOpenFriend,
    onLoadFriendAvatar,
    headerAction,
    emptyState,
    currentUsername,
    centerInViewport = false,
}: {
    title: string;
    friends: OrbitFriend[];
    contacts: OrbitContact[];
    isLoading: boolean;
    onBack: () => void;
    onOpenFriend: (id: string) => void;
    onLoadFriendAvatar?: (friend: OrbitFriend) => Promise<string | null>;
    headerAction?: React.ReactNode;
    emptyState: React.ReactNode;
    currentUsername?: string;
    centerInViewport?: boolean;
}) => {
    const [selectedRequest, setSelectedRequest] =
        React.useState<FriendRequestSheetActions | null>(null);
    const [loadedAvatarURLsByKey, setLoadedAvatarURLsByKey] = React.useState<
        Record<string, string | null>
    >({});
    const avatarLoadsInFlightRef = React.useRef<
        Map<string, Promise<string | null | undefined>>
    >(new Map());
    const loadedAvatarURLFor = React.useCallback(
        (friend: OrbitFriend) =>
            friend.avatarUrl ??
            loadedAvatarURLsByKey[friendAvatarCacheKey(friend)],
        [loadedAvatarURLsByKey],
    );

    const loadFriendAvatar = React.useCallback(
        (friend: OrbitFriend) => {
            const loadedAvatarUrl = loadedAvatarURLFor(friend);
            if (loadedAvatarUrl !== undefined)
                return Promise.resolve(loadedAvatarUrl);
            if (!friend.avatarObjectID || !onLoadFriendAvatar) {
                return Promise.resolve(undefined);
            }

            const cacheKey = friendAvatarCacheKey(friend);
            const inFlight = avatarLoadsInFlightRef.current.get(cacheKey);
            if (inFlight) return inFlight;

            const load = onLoadFriendAvatar(friend)
                .catch((error: unknown) => {
                    log.warn("Failed to load friend avatar", error);
                    return null;
                })
                .then((avatarUrl) => {
                    setLoadedAvatarURLsByKey((currentURLs) =>
                        currentURLs[cacheKey] === avatarUrl
                            ? currentURLs
                            : { ...currentURLs, [cacheKey]: avatarUrl },
                    );
                    return avatarUrl;
                })
                .finally(() => {
                    avatarLoadsInFlightRef.current.delete(cacheKey);
                });
            avatarLoadsInFlightRef.current.set(cacheKey, load);
            return load;
        },
        [loadedAvatarURLFor, onLoadFriendAvatar],
    );

    return (
        <Box
            component="main"
            sx={{
                "--space-orbit-header-height":
                    "calc(68px + var(--space-ios-safe-area-top, 0px))",
                "--space-orbit-bottom-inset": centerInViewport
                    ? "var(--space-orbit-header-height)"
                    : "0px",
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
                        height: "var(--space-orbit-header-height)",
                        pt: "var(--space-ios-safe-area-top, 0px)",
                        maxWidth: 390,
                        mx: "auto",
                        pl: "max(16px, var(--space-ios-safe-area-left, 0px))",
                        pr: "max(16px, var(--space-ios-safe-area-right, 0px))",
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
                            overflowWrap: "anywhere",
                            textAlign: "center",
                        }}
                    >
                        {title}
                    </Box>
                    {headerAction}
                </Box>

                <Box
                    component="section"
                    id="space-main-content"
                    aria-label={title}
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
                    ) : friends.length > 0 || contacts.length > 0 ? (
                        <FriendOrbit
                            ariaLabel={title}
                            items={[
                                ...friends.map((friend) => {
                                    const avatarUrl =
                                        loadedAvatarURLFor(friend);
                                    const showsUsername =
                                        !avatarUrl &&
                                        (!friend.avatarObjectID ||
                                            avatarUrl === null);
                                    return {
                                        id: friend.id,
                                        fitContent: showsUsername,
                                        content: (
                                            <FriendIdentity
                                                avatarUrl={avatarUrl}
                                                friend={friend}
                                                showsUsername={showsUsername}
                                                opensDialog={
                                                    friend.username !==
                                                    currentUsername
                                                }
                                                onLoadAvatar={() =>
                                                    loadFriendAvatar(friend)
                                                }
                                                onOpen={() =>
                                                    onOpenFriend(friend.id)
                                                }
                                            />
                                        ),
                                    };
                                }),
                                ...contacts.map((contact) => ({
                                    id: contact.id,
                                    isSuggestion: contact.isSuggestion,
                                    fitContent: true,
                                    content: (
                                        <OrbitUsernameCircle
                                            variant={contact.direction}
                                            username={contact.username}
                                            isSuggestion={contact.isSuggestion}
                                            onOpen={() =>
                                                setSelectedRequest(contact)
                                            }
                                        />
                                    ),
                                })),
                            ]}
                        />
                    ) : (
                        <Box
                            sx={{
                                alignItems: "center",
                                color: spaceTextMuted,
                                display: "flex",
                                flexDirection: "column",
                                gap: "22px",
                                justifyContent: "center",
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 14,
                                fontWeight: 500,
                                lineHeight: "20px",
                                pointerEvents: "none",
                                position: "absolute",
                                px: "24px",
                                textAlign: "center",
                                top: "calc(var(--space-viewport-height, 100svh) / 2)",
                                transform: "translateY(-50%)",
                                width: "100%",
                            }}
                        >
                            {emptyState}
                        </Box>
                    )}
                </Box>
            </Box>
            {selectedRequest && (
                <FriendRequestSheet
                    {...selectedRequest}
                    onClose={() => setSelectedRequest(null)}
                />
            )}
        </Box>
    );
};
