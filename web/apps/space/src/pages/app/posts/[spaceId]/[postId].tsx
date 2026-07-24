import { SpaceFileViewer } from "components/SpaceFileViewer";
import { SpacePageMeta } from "components/SpacePageMeta";
import { SpaceRouteFallback } from "components/SpaceRouteFallback";
import React from "react";
import {
    loadCurrentSpacePost,
    replyToCurrentPost,
    setCurrentPostLiked,
    type SpacePost,
} from "services/space";
import { useSpaceAppState } from "state/spaceAppState";
import { spaceRoutes } from "utils/spaceRoutes";
import { useSpaceRouter } from "utils/spaceRouteTransitions";

const postBackground = "#000000";

const valueFromQuery = (value: string | string[] | undefined) =>
    Array.isArray(value) ? value[0] : value;

const postIdFromQuery = (value: string | string[] | undefined) => {
    const postIdText = valueFromQuery(value);
    if (!postIdText || !/^\d+$/.test(postIdText)) return undefined;

    const postId = Number(postIdText);
    return Number.isSafeInteger(postId) && postId > 0 ? postId : undefined;
};

const routeParamsFromPath = () => {
    if (typeof window == "undefined") return {};

    const match = /^\/app\/posts\/([^/?#]+)\/([^/?#]+)/.exec(
        window.location.pathname,
    );
    if (!match?.[1] || !match[2]) return {};

    try {
        return {
            postId: postIdFromQuery(decodeURIComponent(match[2])),
            spaceId: decodeURIComponent(match[1]),
        };
    } catch {
        return {};
    }
};

const viewerPhotoFromPost = (post: SpacePost) => ({
    alt: `${post.name} post`,
    avatarUrl: post.avatarUrl,
    caption: post.caption,
    friendID: post.friendID,
    height: post.height,
    imageUrl: post.imageUrl ?? "",
    name: post.name,
    postId: post.postId,
    spaceId: post.spaceId,
    timestampMs: post.timestampMs,
    viewerLiked: post.viewerLiked,
    width: post.width,
});

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const { profile, profileLoadError, profileLoadStatus } = useSpaceAppState();
    const pathParams = routeParamsFromPath();
    const spaceId =
        valueFromQuery(router.query.spaceId) ?? pathParams.spaceId ?? "";
    const postId = postIdFromQuery(router.query.postId) ?? pathParams.postId;
    const [post, setPost] = React.useState<SpacePost | null>(null);
    const [postLoadError, setPostLoadError] = React.useState<string>();
    const [isPostLoading, setIsPostLoading] = React.useState(false);
    const postRouteKey = spaceId && postId ? `${spaceId}:${postId}` : "";
    const isOwnPost = Boolean(post && post.spaceId == profile?.spaceId);

    React.useEffect(() => {
        if (profileLoadStatus == "ready" && !profile) {
            void router.replace(spaceRoutes.onboarding);
        }
    }, [profile, profileLoadStatus, router]);

    React.useEffect(() => {
        if (
            profileLoadStatus != "ready" ||
            !profile?.spaceId ||
            !spaceId ||
            !postId
        ) {
            return;
        }

        let cancelled = false;
        setPost(null);
        setPostLoadError(undefined);
        setIsPostLoading(true);

        void loadCurrentSpacePost(spaceId, postId, profile.spaceId)
            .then((nextPost) => {
                if (cancelled) return;
                if (!nextPost) {
                    setPostLoadError("Post unavailable.");
                    return;
                }
                setPost(nextPost);
            })
            .catch((error: unknown) => {
                console.error("Failed to load space post", error);
                if (!cancelled) setPostLoadError("Post unavailable.");
            })
            .finally(() => {
                if (!cancelled) setIsPostLoading(false);
            });

        return () => {
            cancelled = true;
        };
    }, [postRouteKey, profile?.spaceId, profileLoadStatus, spaceId, postId]);

    const ownerProfileRoute = React.useCallback(() => {
        const ownerSpaceId = post?.spaceId ?? spaceId;
        return ownerSpaceId == profile?.spaceId
            ? spaceRoutes.profile
            : spaceRoutes.friend(ownerSpaceId);
    }, [post?.spaceId, profile?.spaceId, spaceId]);

    const closePost = React.useCallback(() => {
        if (typeof window != "undefined" && window.history.length > 1) {
            router.back();
            return;
        }
        void router.push(ownerProfileRoute());
    }, [ownerProfileRoute, router]);

    if (
        !router.isReady ||
        profileLoadStatus != "ready" ||
        !profile ||
        !spaceId ||
        !postId ||
        isPostLoading ||
        !post
    ) {
        return (
            <SpaceRouteFallback
                background="#FFFFFF"
                message={postLoadError || profileLoadError}
            />
        );
    }
    const actorSpaceId = profile.spaceId;
    if (!actorSpaceId) {
        return (
            <SpaceRouteFallback
                background="#FFFFFF"
                message={postLoadError || profileLoadError}
            />
        );
    }

    return (
        <>
            <SpacePageMeta themeColor={postBackground} />
            <SpaceFileViewer
                photo={viewerPhotoFromPost(post)}
                postActionMode={isOwnPost ? "hidden" : "like-only"}
                onClose={closePost}
                onOpenProfile={() => void router.push(ownerProfileRoute())}
                onReplyToPost={
                    isOwnPost
                        ? undefined
                        : (postSpaceId, nextPostId, text) =>
                              replyToCurrentPost(
                                  actorSpaceId,
                                  postSpaceId,
                                  nextPostId,
                                  text,
                              )
                }
                onSetPostLiked={(nextPostId, liked) =>
                    setCurrentPostLiked(actorSpaceId, nextPostId, liked)
                }
            />
        </>
    );
};

export default Page;
