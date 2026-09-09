import { SpaceAddFriendDialog } from "components/AddFriendDialog";
import { SpaceFriendLimitToast } from "components/FriendLimitToast";
import { SpaceFriendRequestCanceledToast } from "components/FriendRequestCanceledToast";
import { SpacePageMeta } from "components/PageMeta";
import { SpaceRouteFallback } from "components/RouteFallback";
import log from "ente-base/log";
import { useOwnLatestPost } from "hooks/use-own-latest-post";
import React, { useEffect, useState } from "react";
import { HomeScreen } from "screens/HomeScreen";
import {
    cacheSpaceHomeItems,
    loadCachedSpaceHomeItems,
} from "services/home-items";
import {
    loadSpaceHomePosts,
    patchCachedSpaceHomePost,
    refreshSpaceHomePosts,
} from "services/home-posts";
import { consumeSentSpaceInviteFriend, spaceInviteURL } from "services/invite";
import { loadExistingSpaceId } from "services/profile";
import {
    clearSpaceFriendsCache,
    confirmCurrentFriendRequest,
    deleteCurrentFriendRequest,
    loadCurrentFriendAvatarURL,
    loadCurrentFriendRequests,
    loadCurrentSpaceFriends,
    loadCurrentSpacePostAssetURL,
    loadCurrentUnreadStatus,
    replyToCurrentPost,
    requestFriendByUsername,
    sendCurrentPoke,
    setCurrentPostLiked,
    type SpaceFriendRequest,
    type SpacePost,
} from "services/space";
import { useSpaceAppState } from "state/app-state";
import { spaceAppBackgroundColor } from "styles/colors";
import {
    isFriendRequestCanceledError,
    isSpaceFriendLimitError,
} from "utils/friend-errors";
import { maximumSpaceFriendCount } from "utils/friend-limits";
import { useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const {
        friends,
        profile,
        profileLoadError,
        profileLoadStatus,
        setFriends,
        publishPost,
    } = useSpaceAppState();
    const [friendRequestSentToastName, setFriendRequestSentToastName] =
        useState<string>();
    const [isAddFriendOpen, setIsAddFriendOpen] = useState(false);
    const [friendRequests, setFriendRequests] = useState<SpaceFriendRequest[]>(
        [],
    );
    const [latestPosts, setLatestPosts] = useState<SpacePost[]>([]);
    const [spaceId, setSpaceId] = useState<string>();
    const {
        ownLatestPost,
        isOwnLatestPostLoading,
        isOwnLatestPostUnavailable,
        deleteOwnPost,
        updateOwnPostCaption,
    } = useOwnLatestPost(spaceId);
    const [unreadPosts, setUnreadPosts] = useState<SpacePost[]>([]);
    const [hasUnreadMessages, setHasUnreadMessages] = useState<boolean>();
    const [isLatestPostsLoading, setIsLatestPostsLoading] = useState(true);
    const [isFriendsLoading, setIsFriendsLoading] = useState(true);
    const [isFriendRequestsLoading, setIsFriendRequestsLoading] =
        useState(true);
    const [isHomeCacheLoading, setIsHomeCacheLoading] = useState(true);
    const [hasLoadedHomeItems, setHasLoadedHomeItems] = useState(false);
    const [showFriendRequestCanceledToast, setShowFriendRequestCanceledToast] =
        useState(false);
    const [showFriendLimitToast, setShowFriendLimitToast] = useState(false);
    const closeFriendRequestSentToast = React.useCallback(
        () => setFriendRequestSentToastName(undefined),
        [],
    );
    const refreshUnreadStatus = React.useCallback(async (spaceId: string) => {
        try {
            const unreadStatus = await loadCurrentUnreadStatus(spaceId);
            setHasUnreadMessages(unreadStatus.messagesUnread);
        } catch (error: unknown) {
            log.error("Failed to refresh space unread status", error);
        }
    }, []);

    useEffect(() => {
        if (profileLoadStatus == "ready" && !profile) {
            void router.replace(spaceRoutes.onboarding);
        }
    }, [profile, profileLoadStatus, router]);

    useEffect(() => {
        if (!router.isReady) return;

        const sentFriend = consumeSentSpaceInviteFriend();
        if (!sentFriend) return;

        setFriendRequestSentToastName(sentFriend.username.trim());
    }, [router.isReady]);

    useEffect(() => {
        const request = { cancelled: false };
        const isCancelled = () => request.cancelled;
        setSpaceId(undefined);
        setFriendRequests([]);
        setLatestPosts([]);
        setUnreadPosts([]);
        setHasUnreadMessages(undefined);
        setIsLatestPostsLoading(true);
        setIsFriendsLoading(true);
        setIsFriendRequestsLoading(true);
        setIsHomeCacheLoading(true);
        setHasLoadedHomeItems(false);
        void (async () => {
            try {
                const nextSpaceId = await loadExistingSpaceId();
                if (isCancelled()) return;

                setSpaceId(nextSpaceId);
                if (!nextSpaceId) {
                    setHasUnreadMessages(false);
                    return;
                }

                void loadCurrentUnreadStatus(nextSpaceId)
                    .then((unreadStatus) => {
                        if (!isCancelled()) {
                            setHasUnreadMessages(unreadStatus.messagesUnread);
                        }
                    })
                    .catch((error: unknown) =>
                        log.error("Failed to load space unread status", error),
                    );

                const [nextFriends, nextFriendRequests] = await Promise.all([
                    loadCurrentSpaceFriends(nextSpaceId),
                    loadCurrentFriendRequests(nextSpaceId).catch(
                        (error: unknown) => {
                            log.error(
                                "Failed to load Space friend requests",
                                error,
                            );
                            return undefined;
                        },
                    ),
                    Promise.all([
                        loadSpaceHomePosts(nextSpaceId),
                        loadCachedSpaceHomeItems(nextSpaceId),
                    ]).then(([savedHomePosts, savedHomeItems]) => {
                        if (isCancelled()) return;

                        if (savedHomePosts) {
                            setLatestPosts(savedHomePosts.latestPosts);
                            setUnreadPosts(savedHomePosts.unreadPosts);
                        }
                        if (
                            savedHomeItems &&
                            (savedHomeItems.friends.length > 0 ||
                                savedHomeItems.friendRequests.length > 0)
                        ) {
                            setFriends(savedHomeItems.friends);
                            setFriendRequests(savedHomeItems.friendRequests);
                            setIsFriendsLoading(false);
                            setIsFriendRequestsLoading(false);
                            setHasLoadedHomeItems(true);
                        }
                        setIsHomeCacheLoading(false);
                    }),
                ]);
                if (isCancelled()) return;

                setFriends(nextFriends);
                if (nextFriendRequests) {
                    setFriendRequests(nextFriendRequests);
                    setHasLoadedHomeItems(true);
                }
                setIsFriendsLoading(false);
                setIsFriendRequestsLoading(false);
                const refreshedHomePosts = await refreshSpaceHomePosts(
                    nextSpaceId,
                    nextFriends,
                );
                if (isCancelled() || !refreshedHomePosts) return;
                setLatestPosts(refreshedHomePosts.latestPosts);
                setUnreadPosts(refreshedHomePosts.unreadPosts);
            } catch (error) {
                log.error("Failed to load Space home posts", error);
            } finally {
                if (!isCancelled()) {
                    setIsLatestPostsLoading(false);
                    setIsFriendsLoading(false);
                    setIsFriendRequestsLoading(false);
                    setIsHomeCacheLoading(false);
                }
            }
        })();

        return () => {
            request.cancelled = true;
        };
    }, [setFriends]);

    useEffect(() => {
        if (spaceId && hasLoadedHomeItems) {
            void cacheSpaceHomeItems(spaceId, friends, friendRequests);
        }
    }, [spaceId, hasLoadedHomeItems, friends, friendRequests]);

    const setLatestPostLiked = React.useCallback(
        async (postId: number, liked: boolean) => {
            if (!spaceId) throw new Error("Missing space.");

            await setCurrentPostLiked(spaceId, postId, liked);
            void patchCachedSpaceHomePost(spaceId, postId, {
                viewerLiked: liked,
            });
            setLatestPosts((currentItems) =>
                currentItems.map((item) =>
                    item.postId == postId
                        ? { ...item, viewerLiked: liked }
                        : item,
                ),
            );
            setUnreadPosts((currentItems) =>
                currentItems.map((item) =>
                    item.postId == postId
                        ? { ...item, viewerLiked: liked }
                        : item,
                ),
            );
        },
        [spaceId],
    );

    if (
        profileLoadStatus == "error" ||
        (profileLoadStatus == "ready" && !profile)
    ) {
        return (
            <SpaceRouteFallback
                background={spaceAppBackgroundColor}
                message={profileLoadError}
            />
        );
    }

    return (
        <>
            <SpacePageMeta themeColor={spaceAppBackgroundColor} />
            <HomeScreen
                ownLatestPost={ownLatestPost}
                isOwnLatestPostLoading={isOwnLatestPostLoading}
                isOwnLatestPostUnavailable={isOwnLatestPostUnavailable}
                latestPosts={latestPosts}
                unreadPosts={unreadPosts}
                friendRequestSentToastName={friendRequestSentToastName}
                friends={friends}
                friendRequests={friendRequests}
                hasUnreadMessages={hasUnreadMessages}
                isLatestPostsLoading={isLatestPostsLoading}
                isFriendsLoading={isFriendsLoading}
                isFriendRequestsLoading={isFriendRequestsLoading}
                isHomeCacheLoading={isHomeCacheLoading}
                profile={profile}
                viewerSpaceId={spaceId ?? profile?.spaceId}
                showInstallPrompt={
                    profileLoadStatus == "ready" &&
                    Boolean(profile) &&
                    !isLatestPostsLoading &&
                    !isFriendsLoading
                }
                onFriendRequestSentToastClose={closeFriendRequestSentToast}
                onAddFriend={() => setIsAddFriendOpen(true)}
                onAcceptFriendRequest={async (requestID) => {
                    if (!profile?.spaceId) throw new Error("Missing space.");
                    const sentRequestCount = friendRequests.filter(
                        (request) => request.direction == "sent",
                    ).length;
                    if (
                        friends.length + sentRequestCount >=
                        maximumSpaceFriendCount
                    ) {
                        setShowFriendLimitToast(true);
                        return;
                    }

                    try {
                        await confirmCurrentFriendRequest(
                            profile.spaceId,
                            requestID,
                        );
                    } catch (error: unknown) {
                        if (isSpaceFriendLimitError(error)) {
                            setShowFriendLimitToast(true);
                            return;
                        }
                        if (!isFriendRequestCanceledError(error)) throw error;
                        setFriendRequests((currentRequests) =>
                            currentRequests.filter(
                                (request) => request.requestId != requestID,
                            ),
                        );
                        setShowFriendRequestCanceledToast(true);
                        await refreshUnreadStatus(profile.spaceId);
                        return;
                    }
                    const loadedFriends = await loadCurrentSpaceFriends(
                        profile.spaceId,
                    );
                    setIsLatestPostsLoading(true);
                    setFriendRequests((currentRequests) =>
                        currentRequests.filter(
                            (request) => request.requestId != requestID,
                        ),
                    );
                    setFriends(loadedFriends);
                    try {
                        const refreshedHomePosts = await refreshSpaceHomePosts(
                            profile.spaceId,
                            loadedFriends,
                        );
                        if (refreshedHomePosts) {
                            setLatestPosts(refreshedHomePosts.latestPosts);
                            setUnreadPosts(refreshedHomePosts.unreadPosts);
                        }
                    } finally {
                        setIsLatestPostsLoading(false);
                    }
                    await refreshUnreadStatus(profile.spaceId);
                }}
                onCreatePost={
                    profile
                        ? async (image, caption) => {
                              await publishPost(image, caption);
                          }
                        : undefined
                }
                onDeletePost={deleteOwnPost}
                onUpdatePostCaption={updateOwnPostCaption}
                onOpenFriend={(friendID, username) => {
                    const friend = friends.find(
                        (candidate) =>
                            candidate.id == friendID ||
                            candidate.spaceId == friendID,
                    );
                    const friendUsername = username || friend?.username;
                    if (friendUsername) {
                        void router.push(
                            spaceRoutes.friendPage,
                            spaceRoutes.friend(friendUsername),
                        );
                    }
                }}
                onLoadFriendAvatar={loadCurrentFriendAvatarURL}
                onLoadPostImage={loadCurrentSpacePostAssetURL}
                onOpenMessages={() => void router.push(spaceRoutes.messages)}
                onMessageFriend={(friend) =>
                    void router.push(
                        spaceRoutes.message(friend.spaceId ?? friend.id),
                    )
                }
                onPokeFriend={async (friend) => {
                    if (!profile?.spaceId) throw new Error("Missing space.");
                    await sendCurrentPoke(
                        profile.spaceId,
                        friend.spaceId ?? friend.id,
                        {
                            id: profile.spaceId,
                            spaceId: profile.spaceId,
                            fullName: profile.fullName,
                            username: profile.username,
                            avatarUrl: profile.avatarUrl,
                            friendsCount: 0,
                        },
                        friend,
                    );
                }}
                onOpenFriendRequests={() =>
                    void router.push(spaceRoutes.friends)
                }
                onDiscardFriendRequest={async (requestID) => {
                    if (!profile?.spaceId) throw new Error("Missing space.");
                    const friendRequest = friendRequests.find(
                        (request) => request.requestId == requestID,
                    );

                    try {
                        await deleteCurrentFriendRequest(
                            profile.spaceId,
                            requestID,
                        );
                    } catch (error: unknown) {
                        if (!isFriendRequestCanceledError(error)) throw error;
                        clearSpaceFriendsCache();
                        const [requests, loadedFriends] = await Promise.all([
                            loadCurrentFriendRequests(profile.spaceId),
                            loadCurrentSpaceFriends(profile.spaceId),
                        ]);
                        setFriendRequests(requests);
                        setFriends(loadedFriends);
                        setShowFriendRequestCanceledToast(
                            !friendRequest ||
                                !loadedFriends.some(
                                    (friend) =>
                                        friend.id == friendRequest.friend.id,
                                ),
                        );
                        await refreshUnreadStatus(profile.spaceId);
                        return;
                    }
                    setFriendRequests((currentRequests) =>
                        currentRequests.filter(
                            (request) => request.requestId != requestID,
                        ),
                    );
                    await refreshUnreadStatus(profile.spaceId);
                }}
                onOpenProfile={
                    profile
                        ? () => void router.push(spaceRoutes.profile)
                        : undefined
                }
                onOpenSettings={() => void router.push(spaceRoutes.settings)}
                onReplyToPost={
                    profile?.spaceId
                        ? (
                              (actorSpaceId) =>
                              (
                                  postSpaceId: string,
                                  postId: number,
                                  text: string,
                              ) =>
                                  replyToCurrentPost(
                                      actorSpaceId,
                                      postSpaceId,
                                      postId,
                                      text,
                                  )
                          )(profile.spaceId)
                        : undefined
                }
                onSetPostLiked={setLatestPostLiked}
            />
            {showFriendRequestCanceledToast && (
                <SpaceFriendRequestCanceledToast
                    onClose={() => setShowFriendRequestCanceledToast(false)}
                />
            )}
            {profile && (
                <SpaceAddFriendDialog
                    friendRequests={friendRequests}
                    friends={friends}
                    open={isAddFriendOpen}
                    onClose={() => setIsAddFriendOpen(false)}
                    profileLink={spaceInviteURL({
                        spaceUsername: profile.username,
                    })}
                    username={profile.username}
                    onAddFriend={async (username) => {
                        const actorSpaceId = profile.spaceId;
                        if (!actorSpaceId) throw new Error("Missing space.");
                        const status = await requestFriendByUsername({
                            spaceUsername: username,
                        });
                        try {
                            if (status == "friend") {
                                clearSpaceFriendsCache();
                                const [requests, friends] = await Promise.all([
                                    loadCurrentFriendRequests(actorSpaceId),
                                    loadCurrentSpaceFriends(actorSpaceId),
                                ]);
                                setFriendRequests(requests);
                                setFriends(friends);
                                const refreshedHomePosts =
                                    await refreshSpaceHomePosts(
                                        actorSpaceId,
                                        friends,
                                    );
                                if (refreshedHomePosts) {
                                    setLatestPosts(
                                        refreshedHomePosts.latestPosts,
                                    );
                                    setUnreadPosts(
                                        refreshedHomePosts.unreadPosts,
                                    );
                                }
                                await refreshUnreadStatus(actorSpaceId);
                            } else {
                                setFriendRequests(
                                    await loadCurrentFriendRequests(
                                        actorSpaceId,
                                    ),
                                );
                            }
                        } catch (error) {
                            log.error(
                                "Failed to refresh friends after sending request",
                                error,
                            );
                        }
                        return status;
                    }}
                />
            )}
            {showFriendLimitToast && (
                <SpaceFriendLimitToast
                    onClose={() => setShowFriendLimitToast(false)}
                />
            )}
        </>
    );
};

export default Page;
