import { SpacePageMeta } from "components/SpacePageMeta";
import { SpaceRouteFallback } from "components/SpaceRouteFallback";
import log from "ente-base/log";
import React, { useEffect, useState } from "react";
import { HomeScreen, homeBackground } from "screens/HomeScreen";
import {
    createCurrentPhotoPost,
    deleteCurrentPost,
    isSpacePostLimitReachedError,
    loadCurrentFeedPage,
    loadCurrentSpaceFriends,
    loadCurrentSpacePostAssetURL,
    loadCurrentSpacePostAvatarURL,
    loadCurrentUnreadStatus,
    replyToCurrentPost,
    setCurrentPostLiked,
    updateCurrentPostCaption,
    type SpacePost,
} from "services/space";
import {
    cacheCurrentSpaceFeedPage,
    loadCachedSpaceFeed,
    patchCachedSpaceFeedPost,
    prependCachedSpaceFeedPost,
    removeCachedSpaceFeedPost,
} from "services/spaceFeedCache";
import {
    consumeSentSpaceInviteFriend,
    spaceInviteURL,
} from "services/spaceInvite";
import { loadExistingSpaceId } from "services/spaceProfile";
import { useSpaceAppState } from "state/spaceAppState";
import {
    confirmLocalFeedPost,
    createLocalFeedPostID,
    failLocalFeedPost,
} from "utils/localFeedPost";
import { prepareSpacePostImageFromEdit } from "utils/spacePostImage";
import { spaceRoutes } from "utils/spaceRoutes";
import { useSpaceRouter } from "utils/spaceRouteTransitions";

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
        setSkipNextHomeFeedSkeleton,
        skipNextHomeFeedSkeleton,
    } = useSpaceAppState();
    const [friendRequestSentToastName, setFriendRequestSentToastName] =
        useState<string>();
    const [feedItems, setFeedItems] = useState<SpacePost[]>([]);
    const [hasFeedLoadMoreError, setHasFeedLoadMoreError] = useState(false);
    const [feedNextCursor, setFeedNextCursor] = useState<string>();
    const [hasUnreadMessages, setHasUnreadMessages] = useState<boolean>();
    const [isFeedLoading, setIsFeedLoading] = useState(true);
    const [isFeedLoadingMore, setIsFeedLoadingMore] = useState(false);
    const [isFriendsLoading, setIsFriendsLoading] = useState(true);
    const [spaceId, setSpaceId] = useState<string>();
    const [showInviteFriendsToast, setShowInviteFriendsToast] = useState(false);
    const inviteFriendsToastTimerRef = React.useRef<number | undefined>(
        undefined,
    );
    const isInitialFeedLoading =
        Boolean(spaceId || profile?.spaceId) &&
        isFeedLoading &&
        feedItems.length == 0 &&
        localFeedPosts.length == 0;
    const isSkippingInitialFeedSkeleton =
        isInitialFeedLoading && skipNextHomeFeedSkeleton;
    const isHomeFeedLoading = isFeedLoading && !isSkippingInitialFeedSkeleton;
    const closeFriendRequestSentToast = React.useCallback(
        () => setFriendRequestSentToastName(undefined),
        [],
    );
    const closeInviteFriendsToast = React.useCallback(
        () => setShowInviteFriendsToast(false),
        [],
    );

    useEffect(
        () => () => {
            if (inviteFriendsToastTimerRef.current !== undefined)
                window.clearTimeout(inviteFriendsToastTimerRef.current);
        },
        [],
    );

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
        let cancelled = false;
        let loadedSpaceId: string | undefined;
        setSpaceId(undefined);
        setFeedItems([]);
        setHasFeedLoadMoreError(false);
        setFeedNextCursor(undefined);
        setHasUnreadMessages(undefined);
        setIsFeedLoading(true);
        setIsFeedLoadingMore(false);
        setIsFriendsLoading(true);
        void loadExistingSpaceId()
            .then(async (nextSpaceId) => {
                if (cancelled) return undefined;

                loadedSpaceId = nextSpaceId;
                setSpaceId(nextSpaceId);
                if (!nextSpaceId) return undefined;

                let freshFeedApplied = false;
                const cachedFeedLoad = loadCachedSpaceFeed(nextSpaceId);
                const freshFeedLoad = loadCurrentFeedPage(nextSpaceId);
                void cachedFeedLoad.then((cachedFeed) => {
                    if (cancelled || freshFeedApplied || !cachedFeed) return;

                    setFeedItems(cachedFeed.items);
                    setFeedNextCursor(
                        cachedFeed.dirty ? undefined : cachedFeed.nextCursor,
                    );
                });

                const feed = await freshFeedLoad;
                freshFeedApplied = true;
                return feed;
            })
            .then((feed) => {
                if (cancelled || !loadedSpaceId || !feed) return;

                setFeedItems(feed.items);
                setFeedNextCursor(feed.nextCursor);
                void cacheCurrentSpaceFeedPage(loadedSpaceId, feed);
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
                if (cancelled) return;

                setIsFeedLoading(false);
                setSkipNextHomeFeedSkeleton(false);
                if (!loadedSpaceId) {
                    setHasUnreadMessages(false);
                    setIsFriendsLoading(false);
                    return;
                }

                void loadCurrentUnreadStatus(loadedSpaceId)
                    .then((unreadStatus) => {
                        if (!cancelled) {
                            setHasUnreadMessages(unreadStatus.messagesUnread);
                        }
                    })
                    .catch((error: unknown) =>
                        log.error("Failed to load space unread status", error),
                    );
                void loadCurrentSpaceFriends(loadedSpaceId)
                    .then((nextFriends) => {
                        if (!cancelled) setFriends(nextFriends);
                    })
                    .catch((error: unknown) =>
                        log.error("Failed to load space friends", error),
                    )
                    .finally(() => {
                        if (!cancelled) setIsFriendsLoading(false);
                    });
            });

        return () => {
            cancelled = true;
        };
    }, [setFriends, setLocalFeedPosts, setSkipNextHomeFeedSkeleton]);

    const loadMoreFeedItems = React.useCallback(async () => {
        if (!spaceId || !feedNextCursor || isFeedLoadingMore) return;

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
    }, [feedNextCursor, isFeedLoadingMore, spaceId]);

    const setFeedPostLiked = React.useCallback(
        async (postId: number, liked: boolean) => {
            if (!spaceId) throw new Error("Missing space.");

            await setCurrentPostLiked(spaceId, postId, liked);
            void patchCachedSpaceFeedPost(spaceId, postId, {
                viewerLiked: liked,
            });
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
        profileLoadStatus == "error" ||
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
                hasMoreFeedItems={Boolean(feedNextCursor)}
                isFeedLoading={isHomeFeedLoading}
                isFeedLoadingMore={isFeedLoadingMore}
                localFeedPosts={localFeedPosts}
                profile={profile}
                viewerSpaceId={spaceId ?? profile?.spaceId}
                showInstallPrompt={
                    profileLoadStatus == "ready" &&
                    Boolean(profile) &&
                    !isHomeFeedLoading
                }
                showInviteFriendsToast={
                    showInviteFriendsToast &&
                    !isFriendsLoading &&
                    friends.length == 0
                }
                onFriendRequestSentToastClose={closeFriendRequestSentToast}
                onInviteFriendsToastClose={closeInviteFriendsToast}
                onCreatePost={
                    profile
                        ? async (image, caption) => {
                              const spaceId = profile.spaceId;
                              if (!spaceId) throw new Error("Missing space.");

                              const isFirstPost =
                                  !feedItems.some(
                                      (item) => item.spaceId == spaceId,
                                  ) &&
                                  !localFeedPosts.some(
                                      (item) => item.status != "failed",
                                  );
                              const localPostId = createLocalFeedPostID();
                              const displayName =
                                  profile.fullName.trim() ||
                                  profile.username.trim();
                              setLocalFeedPosts((currentPosts) => [
                                  {
                                      avatarUrl: profile.avatarUrl,
                                      caption: caption.trim() || undefined,
                                      friendID: spaceId,
                                      height: image.height,
                                      id: localPostId,
                                      imageUrl:
                                          image.previewUrl ||
                                          URL.createObjectURL(image.file),
                                      name: displayName || "You",
                                      spaceId,
                                      status: "pending",
                                      timestampMs: Date.now(),
                                      width: image.width,
                                  },
                                  ...currentPosts,
                              ]);
                              try {
                                  const preparedImage =
                                      await prepareSpacePostImageFromEdit(
                                          image.file,
                                          image.cropArea,
                                          image.rotationDegrees,
                                      );
                                  const post = await createCurrentPhotoPost({
                                      caption,
                                      file: preparedImage.file,
                                      height: preparedImage.height,
                                      spaceId,
                                      thumbHash: preparedImage.thumbHash,
                                      width: preparedImage.width,
                                  });
                                  if (!post)
                                      throw new Error("Couldn't create post.");
                                  confirmLocalFeedPost(
                                      setLocalFeedPosts,
                                      localPostId,
                                      post,
                                  );
                                  void prependCachedSpaceFeedPost(
                                      spaceId,
                                      post,
                                  );
                                  if (isFirstPost) {
                                      inviteFriendsToastTimerRef.current =
                                          window.setTimeout(() => {
                                              setShowInviteFriendsToast(true);
                                              inviteFriendsToastTimerRef.current =
                                                  undefined;
                                          }, inviteFriendsToastDelayMs);
                                  }
                              } catch (error) {
                                  failLocalFeedPost(
                                      setLocalFeedPosts,
                                      localPostId,
                                      isSpacePostLimitReachedError(error)
                                          ? "post-limit"
                                          : undefined,
                                  );
                                  throw error;
                              }
                          }
                        : undefined
                }
                onDeletePost={async (postId) => {
                    const spaceId = profile?.spaceId;
                    if (!spaceId) throw new Error("Missing space.");
                    await deleteCurrentPost(spaceId, postId);
                    void removeCachedSpaceFeedPost(spaceId, postId);
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
                    void patchCachedSpaceFeedPost(spaceId, postId, {
                        caption: normalizedCaption,
                    });
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
        </>
    );
};

export default Page;
