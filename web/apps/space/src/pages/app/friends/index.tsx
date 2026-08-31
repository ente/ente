import { SpaceFriendRequestCanceledToast } from "components/FriendRequestCanceledToast";
import { SpacePageMeta } from "components/PageMeta";
import { SpaceRouteFallback } from "components/RouteFallback";
import log from "ente-base/log";
import React, { useEffect } from "react";
import { FriendsScreen, friendsBackground } from "screens/FriendsScreen";
import {
    invalidateCachedSpaceFeed,
    removeCachedSpaceFeedPostsBySpace,
} from "services/feed-cache";
import { spaceInviteURL } from "services/invite";
import {
    clearSpaceFriendsCache,
    confirmCurrentFriendRequest,
    deleteCurrentFriendRequest,
    isFriendRequestCanceledError,
    loadCurrentFriendAvatarURL,
    loadCurrentFriendRequests,
    loadCurrentSpaceFriends,
    removeCurrentSpaceFriend,
    requestFriendByUsername,
    type SpaceFriendRequest,
} from "services/space";
import { useSpaceAppState } from "state/app-state";
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
    } = useSpaceAppState();
    const [friendRequests, setFriendRequests] = React.useState<
        SpaceFriendRequest[]
    >([]);
    const [isFriendsLoading, setIsFriendsLoading] = React.useState(true);
    const [showFriendRequestCanceledToast, setShowFriendRequestCanceledToast] =
        React.useState(false);

    useEffect(() => {
        if (profileLoadStatus == "ready" && !profile) {
            void router.replace(spaceRoutes.onboarding);
        }
    }, [profile, profileLoadStatus, router]);

    useEffect(() => {
        if (!profile?.spaceId) return;

        setIsFriendsLoading(true);
        void Promise.allSettled([
            loadCurrentFriendRequests(profile.spaceId),
            loadCurrentSpaceFriends(profile.spaceId),
        ])
            .then(([requestsResult, friendsResult]) => {
                if (requestsResult.status == "fulfilled") {
                    setFriendRequests(requestsResult.value);
                } else {
                    log.error(
                        "Failed to load space friend requests",
                        requestsResult.reason,
                    );
                }
                if (friendsResult.status == "fulfilled") {
                    setFriends(friendsResult.value);
                } else {
                    log.error(
                        "Failed to load space friends",
                        friendsResult.reason,
                    );
                }
            })
            .finally(() => setIsFriendsLoading(false));
    }, [profile?.spaceId, setFriends]);

    if (profileLoadStatus != "ready" || !profile) {
        return (
            <SpaceRouteFallback
                background={friendsBackground}
                message={profileLoadError}
            />
        );
    }

    return (
        <>
            <SpacePageMeta themeColor={friendsBackground} />
            <FriendsScreen
                friendRequests={friendRequests}
                friends={friends}
                isLoading={isFriendsLoading}
                onLoadFriendAvatar={loadCurrentFriendAvatarURL}
                onBack={() => void router.push(spaceRoutes.profile)}
                onAddFriend={async (username) => {
                    const actorSpaceId = profile.spaceId;
                    if (!actorSpaceId) throw new Error("Missing space.");
                    const status = await requestFriendByUsername({
                        spaceUsername: username,
                    });
                    try {
                        if (status == "friend") {
                            clearSpaceFriendsCache();
                            void invalidateCachedSpaceFeed(actorSpaceId);
                            const [requests, friends] = await Promise.all([
                                loadCurrentFriendRequests(actorSpaceId),
                                loadCurrentSpaceFriends(actorSpaceId),
                            ]);
                            setFriendRequests(requests);
                            setFriends(friends);
                        } else {
                            setFriendRequests(
                                await loadCurrentFriendRequests(actorSpaceId),
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
                onMessage={(friendID) => {
                    const friend = friends.find(
                        (candidate) => candidate.id == friendID,
                    );
                    if (friend?.spaceId) {
                        void router.push(spaceRoutes.message(friend.spaceId));
                    }
                }}
                onOpenFriend={(friendID) => {
                    const friend = friends.find(
                        (candidate) =>
                            candidate.id == friendID ||
                            candidate.spaceId == friendID,
                    );
                    if (friend)
                        void router.push(
                            spaceRoutes.friendPage,
                            spaceRoutes.friend(friend.username),
                        );
                }}
                profileLink={spaceInviteURL({
                    spaceUsername: profile.username,
                })}
                username={profile.username}
                onAcceptFriendRequest={async (requestID) => {
                    const actorSpaceId = profile.spaceId;
                    if (!actorSpaceId) return;

                    try {
                        await confirmCurrentFriendRequest(
                            actorSpaceId,
                            requestID,
                        );
                    } catch (error: unknown) {
                        if (!isFriendRequestCanceledError(error)) throw error;
                        setFriendRequests((currentRequests) =>
                            currentRequests.filter(
                                (request) => request.requestId != requestID,
                            ),
                        );
                        setShowFriendRequestCanceledToast(true);
                        return;
                    }
                    void invalidateCachedSpaceFeed(actorSpaceId);
                    const friends = await loadCurrentSpaceFriends(actorSpaceId);
                    setFriendRequests((currentRequests) =>
                        currentRequests.filter(
                            (request) => request.requestId != requestID,
                        ),
                    );
                    setFriends(friends);
                }}
                onDeleteFriendRequest={async (requestID) => {
                    const actorSpaceId = profile.spaceId;
                    if (!actorSpaceId) return;
                    const friendRequest = friendRequests.find(
                        (request) => request.requestId == requestID,
                    );

                    try {
                        await deleteCurrentFriendRequest(
                            actorSpaceId,
                            requestID,
                        );
                    } catch (error: unknown) {
                        if (!isFriendRequestCanceledError(error)) throw error;
                        clearSpaceFriendsCache();
                        const [requests, friends] = await Promise.all([
                            loadCurrentFriendRequests(actorSpaceId),
                            loadCurrentSpaceFriends(actorSpaceId),
                        ]);
                        setFriendRequests(requests);
                        setFriends(friends);
                        setShowFriendRequestCanceledToast(
                            !friendRequest ||
                                !friends.some(
                                    (friend) =>
                                        friend.id == friendRequest.friend.id,
                                ),
                        );
                        return;
                    }
                    setFriendRequests((currentRequests) =>
                        currentRequests.filter(
                            (request) => request.requestId != requestID,
                        ),
                    );
                }}
                onUnfriend={async (friendID) => {
                    const actorSpaceId = profile.spaceId;
                    if (!actorSpaceId) return;

                    const friend = friends.find(
                        (candidate) => candidate.id == friendID,
                    );
                    if (!friend?.spaceId) return;

                    await removeCurrentSpaceFriend(
                        actorSpaceId,
                        friend.spaceId,
                    );
                    await removeCachedSpaceFeedPostsBySpace(
                        actorSpaceId,
                        friend.spaceId,
                    );
                    window.location.reload();
                }}
            />
            {showFriendRequestCanceledToast && (
                <SpaceFriendRequestCanceledToast
                    onClose={() => setShowFriendRequestCanceledToast(false)}
                />
            )}
        </>
    );
};

export default Page;
