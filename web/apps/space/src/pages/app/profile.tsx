import { SpacePageMeta } from "components/SpacePageMeta";
import { SpaceRouteFallback } from "components/SpaceRouteFallback";
import React, { useEffect, useMemo, useState } from "react";
import { ProfileScreen, profileBackground } from "screens/ProfileScreen";
import {
    createCurrentPhotoPost,
    deleteCurrentPost,
    isSpacePostLimitReachedError,
    loadCurrentSpaceFriendsCount,
    loadCurrentSpacePostAssetURL,
    loadCurrentSpaceProfilePostsPage,
    setCurrentPostLiked,
    type SpaceProfilePost,
} from "services/space";
import { spaceInviteURL } from "services/spaceInvite";
import { useSpaceAppState } from "state/spaceAppState";
import {
    confirmLocalFeedPost,
    createLocalFeedPostID,
    failLocalFeedPost,
} from "utils/localFeedPost";
import { profilePostGroupsFromPosts } from "utils/spacePostDisplay";
import { prepareSpacePostImageFromEdit } from "utils/spacePostImage";
import { spaceRoutes } from "utils/spaceRoutes";
import { useSpaceRouter } from "utils/spaceRouteTransitions";

const initialPostLoadingIndicatorDelayMs = 350;

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const { profile, profileLoadError, profileLoadStatus, setLocalFeedPosts } =
        useSpaceAppState();
    const [friendsCount, setFriendsCount] = useState(0);
    const [posts, setPosts] = useState<SpaceProfilePost[]>([]);
    const [isPostsLoading, setIsPostsLoading] = useState(true);
    const [
        showInitialPostLoadingIndicator,
        setShowInitialPostLoadingIndicator,
    ] = useState(false);
    const postGroups = useMemo(
        () => profilePostGroupsFromPosts(posts),
        [posts],
    );
    const isInitialPostsLoading =
        profileLoadStatus == "ready" &&
        Boolean(profile?.spaceId) &&
        isPostsLoading &&
        posts.length == 0;

    useEffect(() => {
        if (profileLoadStatus == "ready" && !profile) {
            void router.replace(spaceRoutes.onboarding);
        }
    }, [profile, profileLoadStatus, router]);

    useEffect(() => {
        if (profileLoadStatus != "ready") return;

        const spaceId = profile?.spaceId;
        if (!spaceId) {
            setFriendsCount(0);
            setIsPostsLoading(false);
            return;
        }

        let cancelled = false;
        setIsPostsLoading(true);
        void Promise.all([
            loadCurrentSpaceProfilePostsPage(spaceId, spaceId),
            loadCurrentSpaceFriendsCount(spaceId),
        ])
            .then(([page, nextFriendsCount]) => {
                if (cancelled) return;
                setPosts(page.items);
                setFriendsCount(nextFriendsCount);
            })
            .catch((error: unknown) =>
                console.error("Failed to load space profile", error),
            )
            .finally(() => {
                if (!cancelled) setIsPostsLoading(false);
            });

        return () => {
            cancelled = true;
        };
    }, [profile?.spaceId, profileLoadStatus]);

    useEffect(() => {
        if (!isInitialPostsLoading) {
            setShowInitialPostLoadingIndicator(false);
            return;
        }

        const timeoutID = window.setTimeout(
            () => setShowInitialPostLoadingIndicator(true),
            initialPostLoadingIndicatorDelayMs,
        );
        return () => window.clearTimeout(timeoutID);
    }, [isInitialPostsLoading]);

    if (profileLoadStatus != "ready" || !profile) {
        return (
            <SpaceRouteFallback
                background={profileBackground}
                message={profileLoadError}
            />
        );
    }
    const actorSpaceId = profile.spaceId;
    if (!actorSpaceId) {
        return (
            <SpaceRouteFallback
                background={profileBackground}
                message={profileLoadError}
            />
        );
    }

    return (
        <>
            <SpacePageMeta themeColor={profileBackground} />
            <ProfileScreen
                friendsCount={friendsCount}
                isPostsLoading={isPostsLoading}
                isStatsLoading={isPostsLoading}
                postGroups={postGroups}
                profile={profile}
                showPostLoadingIndicator={showInitialPostLoadingIndicator}
                onBack={() => void router.push(spaceRoutes.home)}
                onCreatePost={async (image, caption) => {
                    const spaceId = profile.spaceId;
                    if (!spaceId) throw new Error("Missing space.");

                    const localPostId = createLocalFeedPostID();
                    const displayName =
                        profile.fullName.trim() || profile.username.trim();
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
                        if (!post) throw new Error("Couldn't create post.");
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
                }}
                onDraftPostPublished={() => void router.push(spaceRoutes.home)}
                onDeletePost={async (postId) => {
                    const spaceId = profile.spaceId;
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
                    setPosts((currentPosts) =>
                        currentPosts.filter((post) => post.postId != postId),
                    );
                }}
                onOpenFriends={() => void router.push(spaceRoutes.friends)}
                onOpenProfileCover={() =>
                    void router.push(spaceRoutes.profileCover)
                }
                onOpenProfilePhoto={() =>
                    void router.push(spaceRoutes.profilePhoto)
                }
                onOpenSettings={() => void router.push(spaceRoutes.settings)}
                onLoadPostImage={loadCurrentSpacePostAssetURL}
                onSetPostLiked={(postId, liked) =>
                    setCurrentPostLiked(actorSpaceId, postId, liked)
                }
                profileLink={spaceInviteURL({
                    spaceUsername: profile.username,
                })}
            />
        </>
    );
};

export default Page;
