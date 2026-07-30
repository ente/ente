import { spaceDefaultProfilePicPath } from "components/SpaceAvatarImage";
import { SpacePageMeta } from "components/SpacePageMeta";
import { SpaceRouteFallback } from "components/SpaceRouteFallback";
import log from "ente-base/log";
import { useBrowserBackClose } from "hooks/useBrowserBackClose";
import React from "react";
import { friendsBackground } from "screens/FriendsScreen";
import {
    FriendProfileImageViewerScreen,
    friendProfileImageViewerBackground,
} from "screens/ProfileImageViewerScreen";
import { ProfileScreen } from "screens/ProfileScreen";
import {
    loadCurrentSpacePostAssetURL,
    loadCurrentSpaceProfile,
    loadCurrentSpaceProfilePostsPage,
    removeCurrentSpaceFriend,
    replyToCurrentPost,
    setCurrentPostLiked,
    type SpaceProfilePost,
} from "services/space";
import {
    patchCachedSpaceFeedPost,
    removeCachedSpaceFeedPostsBySpace,
} from "services/spaceFeedCache";
import { useSpaceAppState } from "state/spaceAppState";
import { profilePostGroupsFromPosts } from "utils/spacePostDisplay";
import { spaceDefaultCoverImagePath } from "utils/spacePostImage";
import { spaceRoutes } from "utils/spaceRoutes";
import {
    hasPreviousSpaceRoute,
    useSpaceRouter,
} from "utils/spaceRouteTransitions";

interface AuthenticatedFriendProfileProps {
    friendSpaceId: string;
    username: string;
}

export const AuthenticatedFriendProfile: React.FC<
    AuthenticatedFriendProfileProps
> = ({ friendSpaceId, username }) => {
    const router = useSpaceRouter();
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
    const postGroups = React.useMemo(
        () => profilePostGroupsFromPosts(posts),
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
        await removeCachedSpaceFeedPostsBySpace(actorSpaceId, friendSpaceId);
    }, [friendSpaceId, profile?.spaceId]);

    if (profileLoadStatus != "ready" || !profile?.spaceId) {
        return (
            <SpaceRouteFallback
                background={friendsBackground}
                message={profileLoadError}
            />
        );
    }
    if (
        !hadCachedFriendProfileOnMount.current &&
        (isProfileLoading || isPostsLoading)
    ) {
        return <SpaceRouteFallback background={friendsBackground} />;
    }
    const actorSpaceId = profile.spaceId;

    return (
        <>
            <SpacePageMeta themeColor={friendsBackground} />
            <ProfileScreen
                friendsCount={displayedProfile.friendsCount}
                headerVariant="friend"
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
                onReplyToPost={(postSpaceId, postId, text) =>
                    replyToCurrentPost(actorSpaceId, postSpaceId, postId, text)
                }
                onSetPostLiked={async (postId, liked) => {
                    await setCurrentPostLiked(actorSpaceId, postId, liked);
                    void patchCachedSpaceFeedPost(actorSpaceId, postId, {
                        viewerLiked: liked,
                    });
                }}
                onUnfriend={unfriend}
                onUnfriendComplete={() =>
                    window.location.replace(spaceRoutes.friends)
                }
                postGroups={postGroups}
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
