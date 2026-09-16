import { SpaceAddFriendDialog } from "components/AddFriendDialog";
import { SpacePageMeta } from "components/PageMeta";
import { SpaceRouteFallback } from "components/RouteFallback";
import log from "ente-base/log";
import React, { useEffect, useState } from "react";
import { HomeScreen } from "screens/HomeScreen";
import {
    cacheCurrentSpaceFeedPage,
    loadCachedSpaceFeed,
} from "services/feed-cache";
import { consumeSentSpaceInviteFriend, spaceInviteURL } from "services/invite";
import { savedSpaceOwnedSpaces } from "services/persistent-session";
import { loadExistingSpaceId } from "services/profile";
import {
    clearSpaceFriendsCache,
    deleteCurrentPost,
    hasCurrentSpacePosts,
    loadCurrentFeedPage,
    loadCurrentFriendRequests,
    loadCurrentSpaceFriends,
    loadCurrentSpacePostAssetURL,
    loadCurrentSpacePostAvatarURL,
    loadCurrentUnreadStatus,
    replyToCurrentPost,
    requestFriendByUsername,
    setCurrentPostLiked,
    updateCurrentPostCaption,
    type SpaceFriendRequest,
    type SpacePost,
} from "services/space";
import { useSpaceAppState } from "state/app-state";
import { spaceAppBackgroundColor as homeBackground } from "styles/colors";
import { useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

const inviteFriendsToastDelayMs = 3000;

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const {
        friends,
        localFeedPosts,
        profile,
        profileLoadError,
        profileLoadStatus,
        setFriends,
        setLocalFeedPosts,
        setPendingPostPhotoFile,
    } = useSpaceAppState();
    const [friendRequestSentToastName, setFriendRequestSentToastName] =
        useState<string>();
    const [isAddFriendOpen, setIsAddFriendOpen] = useState(false);
    const [friendRequests, setFriendRequests] = useState<SpaceFriendRequest[]>(
        [],
    );
    const [feedItems, setFeedItems] = useState<SpacePost[]>([]);
    const [hasFeedLoadMoreError, setHasFeedLoadMoreError] = useState(false);
    const [feedNextCursor, setFeedNextCursor] = useState<string>();
    const [hasUnreadMessages, setHasUnreadMessages] = useState<boolean>();
    const [hasOwnPosts, setHasOwnPosts] = useState<boolean>();
    const [isFeedLoading, setIsFeedLoading] = useState(true);
    const [isFeedLoadingMore, setIsFeedLoadingMore] = useState(false);
    const [isFriendsLoading, setIsFriendsLoading] = useState(true);
    const [spaceId, setSpaceId] = useState<string>();
    const [showInviteFriendsToast, setShowInviteFriendsToast] = useState(false);
    const closeFriendRequestSentToast = React.useCallback(
        () => setFriendRequestSentToastName(undefined),
        [],
    );
    const closeInviteFriendsToast = React.useCallback(
        () => setShowInviteFriendsToast(false),
        [],
    );

    const firstPostID =
        localFeedPosts.length == 1 &&
        localFeedPosts[0]?.status == "ready" &&
        !feedItems.some((post) => post.spaceId == profile?.spaceId)
            ? localFeedPosts[0].id
            : undefined;
    useEffect(() => {
        if (!firstPostID) return;
        const timer = window.setTimeout(
            () => setShowInviteFriendsToast(true),
            inviteFriendsToastDelayMs,
        );
        return () => window.clearTimeout(timer);
    }, [firstPostID]);

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
        if (!isAddFriendOpen || !profile?.spaceId) return;

        let cancelled = false;
        void loadCurrentFriendRequests(profile.spaceId)
            .then((requests) => {
                if (!cancelled) setFriendRequests(requests);
            })
            .catch((error: unknown) =>
                log.error("Failed to load Space friend requests", error),
            );
        return () => {
            cancelled = true;
        };
    }, [isAddFriendOpen, profile?.spaceId]);

    useEffect(() => {
        setHasOwnPosts(undefined);
        if (!spaceId) return;

        let cancelled = false;
        void hasCurrentSpacePosts(spaceId)
            .then((hasPosts) => {
                if (!cancelled) setHasOwnPosts(hasPosts);
            })
            .catch((error: unknown) =>
                log.error("Failed to check for own Space posts", error),
            );
        return () => {
            cancelled = true;
        };
    }, [spaceId]);

    useEffect(() => {
        const request = { cancelled: false };
        const isCancelled = () => request.cancelled;
        let loadedSpaceId: string | undefined;
        let cachedFeedSyncedAtMs: number | undefined;
        setSpaceId(undefined);
        setFeedItems([]);
        setHasFeedLoadMoreError(false);
        setFeedNextCursor(undefined);
        setHasUnreadMessages(undefined);
        setIsFeedLoading(true);
        setIsFeedLoadingMore(false);
        setIsFriendsLoading(true);
        void (async () => {
            const savedSpaceId = savedSpaceOwnedSpaces()?.[0]?.spaceId;
            const loadCache = async (spaceId: string) => {
                const cachedFeed = await loadCachedSpaceFeed(spaceId);
                if (isCancelled()) return;
                cachedFeedSyncedAtMs = cachedFeed?.syncedAtMs;
                setFeedItems(cachedFeed?.items ?? []);
                setFeedNextCursor(
                    cachedFeed?.dirty ? undefined : cachedFeed?.nextCursor,
                );
            };
            if (savedSpaceId) {
                loadedSpaceId = savedSpaceId;
                setSpaceId(savedSpaceId);
                await loadCache(savedSpaceId);
            }
            const nextSpaceId = await loadExistingSpaceId();
            if (isCancelled()) return undefined;
            loadedSpaceId = nextSpaceId;
            setSpaceId(nextSpaceId);
            if (!nextSpaceId) {
                setFeedItems([]);
                return undefined;
            }
            if (savedSpaceId != nextSpaceId) await loadCache(nextSpaceId);
            while (!isCancelled()) {
                const feed = await loadCurrentFeedPage(nextSpaceId);
                if (isCancelled()) return undefined;
                const applied = await cacheCurrentSpaceFeedPage(
                    nextSpaceId,
                    feed,
                    { syncedAtMs: cachedFeedSyncedAtMs },
                );
                if (applied) return feed;
                cachedFeedSyncedAtMs = (await loadCachedSpaceFeed(nextSpaceId))
                    ?.syncedAtMs;
            }
            return undefined;
        })()
            .then((feed) => {
                if (isCancelled() || !loadedSpaceId || !feed) return;

                setFeedItems(feed.items);
                setFeedNextCursor(feed.nextCursor);
                const refreshedPostIDs = new Set(
                    feed.items.map((item) => item.postId),
                );
                setLocalFeedPosts((currentPosts) =>
                    currentPosts.filter(
                        (item) =>
                            item.status != "ready" ||
                            !refreshedPostIDs.has(item.post.postId),
                    ),
                );
            })
            .catch((error: unknown) =>
                log.error("Failed to load space feed", error),
            )
            .finally(() => {
                if (isCancelled()) return;

                setIsFeedLoading(false);
                if (!loadedSpaceId) {
                    setHasUnreadMessages(false);
                    setIsFriendsLoading(false);
                    return;
                }

                void loadCurrentUnreadStatus(loadedSpaceId)
                    .then((unreadStatus) => {
                        if (!isCancelled()) {
                            setHasUnreadMessages(unreadStatus.messagesUnread);
                        }
                    })
                    .catch((error: unknown) =>
                        log.error("Failed to load space unread status", error),
                    );
                void loadCurrentSpaceFriends(loadedSpaceId)
                    .then((nextFriends) => {
                        if (!isCancelled()) setFriends(nextFriends);
                    })
                    .catch((error: unknown) =>
                        log.error("Failed to load space friends", error),
                    )
                    .finally(() => {
                        if (!isCancelled()) setIsFriendsLoading(false);
                    });
            });

        return () => {
            request.cancelled = true;
        };
    }, [setFriends, setLocalFeedPosts]);

    const loadMoreFeedItems = React.useCallback(async () => {
        if (!spaceId || !feedNextCursor || isFeedLoading || isFeedLoadingMore)
            return;

        setHasFeedLoadMoreError(false);
        setIsFeedLoadingMore(true);
        try {
            const feed = await loadCurrentFeedPage(spaceId, feedNextCursor);
            setFeedItems((currentItems) => {
                const existingPostIds = new Set(
                    currentItems.map((item) => item.postId),
                );
                return [
                    ...currentItems,
                    ...feed.items.filter(
                        (item) => !existingPostIds.has(item.postId),
                    ),
                ];
            });
            setFeedNextCursor(feed.nextCursor);
        } catch (error) {
            setHasFeedLoadMoreError(true);
            log.error("Failed to load more space feed", error);
        } finally {
            setIsFeedLoadingMore(false);
        }
    }, [feedNextCursor, isFeedLoading, isFeedLoadingMore, spaceId]);

    const setFeedPostLiked = React.useCallback(
        async (postId: number, liked: boolean) => {
            if (!spaceId) throw new Error("Missing space.");

            await setCurrentPostLiked(spaceId, postId, liked);
            setFeedItems((currentItems) =>
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
        (profileLoadStatus == "error" &&
            feedItems.length == 0 &&
            localFeedPosts.length == 0) ||
        (profileLoadStatus == "ready" && !profile)
    ) {
        return (
            <SpaceRouteFallback
                background={homeBackground}
                message={profileLoadError}
            />
        );
    }

    return (
        <>
            <SpacePageMeta themeColor={homeBackground} />
            <HomeScreen
                feedItems={feedItems}
                friendRequestSentToastName={friendRequestSentToastName}
                hasFeedLoadMoreError={hasFeedLoadMoreError}
                hasUnreadMessages={hasUnreadMessages}
                hasMoreFeedItems={!isFeedLoading && Boolean(feedNextCursor)}
                isFeedLoading={isFeedLoading}
                isFeedLoadingMore={isFeedLoadingMore}
                localFeedPosts={localFeedPosts}
                showFirstPostPrompt={
                    hasOwnPosts === false &&
                    localFeedPosts.length == 0 &&
                    !feedItems.some((post) => post.spaceId == spaceId)
                }
                profile={profile}
                viewerSpaceId={spaceId ?? profile?.spaceId}
                showInstallPrompt={
                    profileLoadStatus == "ready" &&
                    Boolean(profile) &&
                    !isFeedLoading
                }
                showInviteFriendsToast={
                    showInviteFriendsToast &&
                    !isFriendsLoading &&
                    friends.length == 0
                }
                onFriendRequestSentToastClose={closeFriendRequestSentToast}
                onInviteFriendsToastClose={closeInviteFriendsToast}
                onAddFriend={() => setIsAddFriendOpen(true)}
                onPostPhotoSelect={setPendingPostPhotoFile}
                onDeletePost={async (postId) => {
                    const spaceId = profile?.spaceId;
                    if (!spaceId) throw new Error("Missing space.");
                    await deleteCurrentPost(spaceId, postId);
                    setLocalFeedPosts((currentPosts) =>
                        currentPosts.filter(
                            (item) =>
                                item.status == "pending" ||
                                item.status == "failed" ||
                                item.post.postId != postId,
                        ),
                    );
                    setFeedItems((currentItems) =>
                        currentItems.filter((item) => item.postId != postId),
                    );
                }}
                onUpdatePostCaption={async (postId, caption) => {
                    const spaceId = profile?.spaceId;
                    if (!spaceId) throw new Error("Missing space.");

                    await updateCurrentPostCaption(spaceId, postId, caption);
                    const normalizedCaption = caption.trim() || undefined;
                    setLocalFeedPosts((currentPosts) =>
                        currentPosts.map((item) =>
                            (item.status == "posted" ||
                                item.status == "ready") &&
                            item.post.postId == postId
                                ? {
                                      ...item,
                                      post: {
                                          ...item.post,
                                          caption: normalizedCaption,
                                      },
                                  }
                                : item,
                        ),
                    );
                    setFeedItems((currentItems) =>
                        currentItems.map((item) =>
                            item.postId == postId
                                ? { ...item, caption: normalizedCaption }
                                : item,
                        ),
                    );
                }}
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
                onLoadMoreFeedItems={loadMoreFeedItems}
                onLoadPostAvatar={loadCurrentSpacePostAvatarURL}
                onLoadPostImage={loadCurrentSpacePostAssetURL}
                onOpenMessages={() => void router.push(spaceRoutes.messages)}
                onOpenProfile={
                    profile
                        ? () => void router.push(spaceRoutes.profile)
                        : undefined
                }
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
                onSetPostLiked={setFeedPostLiked}
                profileLink={
                    profile
                        ? spaceInviteURL({ spaceUsername: profile.username })
                        : undefined
                }
            />
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
                                const [requests, friends, feed] =
                                    await Promise.all([
                                        loadCurrentFriendRequests(actorSpaceId),
                                        loadCurrentSpaceFriends(actorSpaceId),
                                        loadCurrentFeedPage(actorSpaceId),
                                    ]);
                                setFriendRequests(requests);
                                setFriends(friends);
                                setFeedItems(feed.items);
                                setFeedNextCursor(feed.nextCursor);
                                await cacheCurrentSpaceFeedPage(
                                    actorSpaceId,
                                    feed,
                                );
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
        </>
    );
};

export default Page;
