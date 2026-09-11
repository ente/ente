import { SpacePageMeta } from "components/PageMeta";
import { SpaceRouteFallback } from "components/RouteFallback";
import log from "ente-base/log";
import React, { useEffect, useMemo, useState } from "react";
import { ProfileScreen } from "screens/ProfileScreen";
import { spaceInviteURL } from "services/invite";
import {
    deleteCurrentPost,
    loadCurrentSpaceFriendsCount,
    loadCurrentSpacePostAssetURL,
    loadCurrentSpaceProfilePostsPage,
    setCurrentPostLiked,
    updateCurrentPostCaption,
    type SpaceProfilePost,
} from "services/space";
import { useSpaceAppState } from "state/app-state";
import { spaceAppBackgroundColor } from "styles/colors";
import { profilePostItemsFromPosts } from "utils/post-display";
import { useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

const initialPostLoadingIndicatorDelayMs = 350;

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const initialSection =
        router.query.section == "latest" ? "latest" : undefined;
    const {
        profile,
        profileLoadError,
        profileLoadStatus,
        publishPost,
        setPostPublication,
    } = useSpaceAppState();
    const [friendsCount, setFriendsCount] = useState(0);
    const [posts, setPosts] = useState<SpaceProfilePost[]>([]);
    const [isPostsLoading, setIsPostsLoading] = useState(true);
    const [
        showInitialPostLoadingIndicator,
        setShowInitialPostLoadingIndicator,
    ] = useState(false);
    const postItems = useMemo(() => profilePostItemsFromPosts(posts), [posts]);
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
                log.error("Failed to load space profile", error),
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

    if (
        profileLoadStatus != "ready" ||
        !profile ||
        (initialSection == "latest" && isPostsLoading)
    ) {
        return (
            <SpaceRouteFallback
                background={spaceAppBackgroundColor}
                message={profileLoadError}
            />
        );
    }
    const actorSpaceId = profile.spaceId;
    if (!actorSpaceId) {
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
            <ProfileScreen
                friendsCount={friendsCount}
                initialSection={initialSection}
                isPostsLoading={isPostsLoading}
                isStatsLoading={isPostsLoading}
                postItems={postItems}
                profile={profile}
                showPostLoadingIndicator={showInitialPostLoadingIndicator}
                onBack={() => void router.push(spaceRoutes.home)}
                onCreatePost={async (image, caption) => {
                    const post = await publishPost(image, caption);
                    setPosts((currentPosts) => [
                        post,
                        ...currentPosts.filter(
                            (currentPost) => currentPost.postId != post.postId,
                        ),
                    ]);
                }}
                onDeletePost={async (postId) => {
                    const spaceId = profile.spaceId;
                    if (!spaceId) throw new Error("Missing space.");
                    await deleteCurrentPost(spaceId, postId);
                    setPostPublication((current) =>
                        current?.post.postId == postId ? null : current,
                    );
                    setPosts((currentPosts) =>
                        currentPosts.filter((post) => post.postId != postId),
                    );
                }}
                onUpdatePostCaption={async (postId, caption) => {
                    const spaceId = profile.spaceId;
                    if (!spaceId) throw new Error("Missing space.");

                    await updateCurrentPostCaption(spaceId, postId, caption);
                    const normalizedCaption = caption.trim() || undefined;
                    setPostPublication((current) =>
                        current?.post.postId == postId
                            ? {
                                  ...current,
                                  post: {
                                      ...current.post,
                                      caption: normalizedCaption,
                                  },
                              }
                            : current,
                    );
                    setPosts((currentPosts) =>
                        currentPosts.map((post) =>
                            post.postId == postId
                                ? { ...post, caption: normalizedCaption }
                                : post,
                        ),
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
                onSetPostLiked={async (postId, liked) => {
                    await setCurrentPostLiked(actorSpaceId, postId, liked);
                }}
                profileLink={spaceInviteURL({
                    spaceUsername: profile.username,
                })}
            />
        </>
    );
};

export default Page;
