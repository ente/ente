import { SpacePageMeta } from "components/SpacePageMeta";
import { SpaceRouteFallback } from "components/SpaceRouteFallback";
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
    type SpacePost,
} from "services/space";
import {
    consumeSentSpaceInviteFriend,
    spaceInviteURL,
} from "services/spaceInvite";
import { useSpaceAppState } from "state/spaceAppState";
import {
    confirmLocalFeedPost,
    createLocalFeedPostID,
    failLocalFeedPost,
} from "utils/localFeedPost";
import { prepareSpacePostImageFromEdit } from "utils/spacePostImage";
import { spaceRoutes } from "utils/spaceRoutes";
import { useSpaceRouter } from "utils/spaceRouteTransitions";

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
    const isInitialFeedLoading =
        profileLoadStatus == "ready" &&
        Boolean(profile?.spaceId) &&
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
        if (profileLoadStatus != "ready") return;

        const spaceId = profile?.spaceId;
        if (!spaceId) {
            setFeedItems([]);
            setHasFeedLoadMoreError(false);
            setFeedNextCursor(undefined);
            setHasUnreadMessages(false);
            setIsFeedLoading(false);
            setIsFeedLoadingMore(false);
            setIsFriendsLoading(false);
            setSkipNextHomeFeedSkeleton(false);
            return;
        }

        let cancelled = false;
        setFeedItems([]);
        setHasFeedLoadMoreError(false);
        setFeedNextCursor(undefined);
        setHasUnreadMessages(undefined);
        setIsFeedLoading(true);
        setIsFeedLoadingMore(false);
        setIsFriendsLoading(true);
        void loadCurrentFeedPage(spaceId)
            .then((feed) => {
                if (cancelled) return;

                setFeedItems(feed.items);
                setFeedNextCursor(feed.nextCursor);
            })
            .catch((error: unknown) =>
                console.error("Failed to load space feed", error),
            )
            .finally(() => {
                if (!cancelled) {
                    setIsFeedLoading(false);
                    setSkipNextHomeFeedSkeleton(false);
                }
            });

        void loadCurrentUnreadStatus(spaceId)
            .then((unreadStatus) => {
                if (!cancelled) {
                    setHasUnreadMessages(unreadStatus.messagesUnread);
                }
            })
            .catch((error: unknown) =>
                console.error("Failed to load space unread status", error),
            );

        void loadCurrentSpaceFriends(spaceId)
            .then((nextFriends) => {
                if (!cancelled) setFriends(nextFriends);
            })
            .catch((error: unknown) =>
                console.error("Failed to load space friends", error),
            )
            .finally(() => {
                if (!cancelled) setIsFriendsLoading(false);
            });

        return () => {
            cancelled = true;
        };
    }, [
        profile?.spaceId,
        profileLoadStatus,
        setFriends,
        setSkipNextHomeFeedSkeleton,
    ]);

    const loadMoreFeedItems = React.useCallback(async () => {
        const spaceId = profile?.spaceId;
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
            console.error("Failed to load more space feed", error);
        } finally {
            setIsFeedLoadingMore(false);
        }
    }, [feedNextCursor, isFeedLoadingMore, profile?.spaceId]);

    const setFeedPostLiked = React.useCallback(
        async (postId: number, liked: boolean) => {
            const spaceId = profile?.spaceId;
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
        [profile?.spaceId],
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
                friendsCount={friends.length}
                friendRequestSentToastName={friendRequestSentToastName}
                hasFeedLoadMoreError={hasFeedLoadMoreError}
                hasUnreadMessages={hasUnreadMessages}
                hasMoreFeedItems={Boolean(feedNextCursor)}
                isFeedLoading={isHomeFeedLoading}
                isFeedLoadingMore={isFeedLoadingMore}
                isFriendsLoading={isFriendsLoading}
                localFeedPosts={localFeedPosts}
                profile={profile}
                showInstallPrompt={
                    profileLoadStatus == "ready" &&
                    Boolean(profile) &&
                    !isHomeFeedLoading
                }
                onFriendRequestSentToastClose={closeFriendRequestSentToast}
                onCreatePost={
                    profile
                        ? async (image, caption) => {
                              const spaceId = profile.spaceId;
                              if (!spaceId) throw new Error("Missing space.");

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
                onOpenFriend={(friendID) =>
                    void router.push(spaceRoutes.friend(friendID))
                }
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
