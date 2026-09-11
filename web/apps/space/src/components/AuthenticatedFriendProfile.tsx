import { spaceDefaultProfilePicPath } from "components/AvatarImage";
import { SpacePageMeta } from "components/PageMeta";
import { SpaceRouteFallback } from "components/RouteFallback";
import log from "ente-base/log";
import { useBrowserBackClose } from "hooks/use-browser-back-close";
import React from "react";
import {
    FriendProfileImageViewerScreen,
    friendProfileImageViewerBackground,
} from "screens/ProfileImageViewerScreen";
import { ProfileScreen } from "screens/ProfileScreen";
import {
    markSpaceHomePostRead,
    patchCachedSpaceHomePost,
    removeCachedSpaceHomePostsBySpace,
} from "services/home-posts";
import {
    loadCurrentSpacePostAssetURL,
    loadCurrentSpaceProfile,
    loadCurrentSpaceProfilePostsPage,
    removeCurrentSpaceFriend,
    replyToCurrentPost,
    setCurrentPostLiked,
    type SpaceProfilePost,
} from "services/space";
import { useSpaceAppState } from "state/app-state";
import { spaceAppBackgroundColor } from "styles/colors";
import { profilePostItemsFromPosts } from "utils/post-display";
import { spaceDefaultCoverImagePath } from "utils/post-image";
import { hasPreviousSpaceRoute, useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

interface AuthenticatedFriendProfileProps {
    friendSpaceId: string;
    username: string;
}

export const AuthenticatedFriendProfile: React.FC<
    AuthenticatedFriendProfileProps
> = ({ friendSpaceId, username }) => {
    const router = useSpaceRouter();
    const initialSection =
        router.query.section == "latest" ? "latest" : undefined;
    const { friends, profile, profileLoadError, profileLoadStatus } =
        useSpaceAppState();
    const [friendProfile, setFriendProfile] =
        React.useState<Awaited<ReturnType<typeof loadCurrentSpaceProfile>>>();
    const [posts, setPosts] = React.useState<SpaceProfilePost[]>([]);
    const [isProfileLoading, setIsProfileLoading] = React.useState(true);
    const [isPostsLoading, setIsPostsLoading] = React.useState(true);
    const [openProfileImage, setOpenProfileImage] = React.useState<
        "avatar" | "cover" | null
    >(null);
    const postItems = React.useMemo(
        () => profilePostItemsFromPosts(posts),
        [posts],
    );
    const cachedFriendProfile = friends.find(
        (friend) =>
            friend.spaceId == friendSpaceId ||
            friend.id == friendSpaceId ||
            friend.username == username,
    );
    const hadCachedFriendProfileOnMount = React.useRef(
        Boolean(cachedFriendProfile),
    );
    const immediateFriendProfile = friendProfile ?? cachedFriendProfile;
    const displayedProfile = immediateFriendProfile
        ? {
              ...immediateFriendProfile,
              avatarUrl: immediateFriendProfile.avatarUrl ?? null,
          }
        : {
              avatarUrl: null,
              friendsCount: 0,
              fullName: username,
              id: friendSpaceId,
              spaceId: friendSpaceId,
              spaceSlug: username,
              username,
          };
    const friendAvatarUrl =
        displayedProfile.avatarUrl || spaceDefaultProfilePicPath;
    const friendCoverUrl =
        displayedProfile.coverUrl || spaceDefaultCoverImagePath;
    const friendDisplayName =
        displayedProfile.fullName.trim() ||
        displayedProfile.username.trim() ||
        "Friend";

    useBrowserBackClose({
        open: Boolean(openProfileImage),
        onClose: () => setOpenProfileImage(null),
        stateKey: "space-friend-profile-image",
    });

    React.useEffect(() => {
        const viewerSpaceId = profile?.spaceId;
        if (!viewerSpaceId) return;

        let cancelled = false;
        setFriendProfile(undefined);
        setPosts([]);
        setIsProfileLoading(true);
        setIsPostsLoading(true);
        void loadCurrentSpaceProfile(friendSpaceId, viewerSpaceId)
            .then((nextProfile) => {
                if (!cancelled) setFriendProfile(nextProfile);
            })
            .catch((error: unknown) =>
                log.error("Failed to load friend profile", error),
            )
            .finally(() => {
                if (!cancelled) setIsProfileLoading(false);
            });
        void loadCurrentSpaceProfilePostsPage(friendSpaceId, viewerSpaceId)
            .then((page) => {
                if (!cancelled) setPosts(page.items);
            })
            .catch((error: unknown) =>
                log.error("Failed to load friend posts", error),
            )
            .finally(() => {
                if (!cancelled) setIsPostsLoading(false);
            });

        return () => {
            cancelled = true;
        };
    }, [friendSpaceId, profile?.spaceId]);

    const goBack = () => {
        if (hasPreviousSpaceRoute()) {
            router.back();
        } else {
            void router.push(spaceRoutes.home);
        }
    };

    const unfriend = React.useCallback(async () => {
        const actorSpaceId = profile?.spaceId;
        if (!actorSpaceId) return;

        await removeCurrentSpaceFriend(actorSpaceId, friendSpaceId);
        await removeCachedSpaceHomePostsBySpace(actorSpaceId, friendSpaceId);
    }, [friendSpaceId, profile?.spaceId]);

    if (profileLoadStatus != "ready" || !profile?.spaceId) {
        return (
            <SpaceRouteFallback
                background={spaceAppBackgroundColor}
                message={profileLoadError}
            />
        );
    }
    if (
        (!hadCachedFriendProfileOnMount.current ||
            initialSection == "latest") &&
        (isProfileLoading || isPostsLoading)
    ) {
        return <SpaceRouteFallback background={spaceAppBackgroundColor} />;
    }
    const actorSpaceId = profile.spaceId;

    return (
        <>
            <SpacePageMeta themeColor={spaceAppBackgroundColor} />
            <ProfileScreen
                friendsCount={displayedProfile.friendsCount}
                headerVariant="friend"
                initialSection={initialSection}
                isCoverLoading={isProfileLoading}
                isNameLoading={isProfileLoading && !immediateFriendProfile}
                isPostsLoading={isPostsLoading}
                isStatsLoading={isProfileLoading || isPostsLoading}
                onBack={goBack}
                onLoadPostImage={loadCurrentSpacePostAssetURL}
                onMessageFriend={() =>
                    void router.push(spaceRoutes.message(friendSpaceId))
                }
                onOpenProfileCover={() => setOpenProfileImage("cover")}
                onOpenProfilePhoto={() => setOpenProfileImage("avatar")}
                onOpenPost={(post) => {
                    if (!post.postId) return;
                    void markSpaceHomePostRead(actorSpaceId, {
                        postId: post.postId,
                        timestampMs: post.timestampMs,
                    }).catch((error: unknown) =>
                        log.warn("Failed to mark Space post as read", error),
                    );
                }}
                onReplyToPost={(postSpaceId, postId, text) =>
                    replyToCurrentPost(actorSpaceId, postSpaceId, postId, text)
                }
                onSetPostLiked={async (postId, liked) => {
                    const previousLiked =
                        posts.find((post) => post.postId == postId)
                            ?.viewerLiked ?? false;
                    const updateLiked = (viewerLiked: boolean) =>
                        setPosts((current) =>
                            current.map((post) =>
                                post.postId == postId
                                    ? { ...post, viewerLiked }
                                    : post,
                            ),
                        );
                    updateLiked(liked);
                    try {
                        await setCurrentPostLiked(actorSpaceId, postId, liked);
                    } catch (error) {
                        updateLiked(previousLiked);
                        throw error;
                    }
                    void patchCachedSpaceHomePost(actorSpaceId, postId, {
                        viewerLiked: liked,
                    });
                }}
                onUnfriend={unfriend}
                onUnfriendComplete={() =>
                    window.location.replace(spaceRoutes.friends)
                }
                postItems={postItems}
                profile={displayedProfile}
                showPostLoadingIndicator={false}
            />
            {openProfileImage && (
                <>
                    <SpacePageMeta
                        themeColor={friendProfileImageViewerBackground}
                    />
                    <FriendProfileImageViewerScreen
                        displayName={friendDisplayName}
                        imageUrl={
                            openProfileImage == "cover"
                                ? friendCoverUrl
                                : friendAvatarUrl
                        }
                        onClose={() => setOpenProfileImage(null)}
                        variant={openProfileImage}
                    />
                </>
            )}
        </>
    );
};
