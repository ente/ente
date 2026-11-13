import { Box } from "@mui/material";
import { FriendProfileSheet } from "components/FriendProfileSheet";
import { SpaceFriendRequestCanceledToast } from "components/FriendRequestCanceledToast";
import { SpacePageMeta } from "components/PageMeta";
import { SpaceRouteFallback } from "components/RouteFallback";
import log from "ente-base/log";
import React, { useEffect } from "react";
import { FriendsScreen } from "screens/FriendsScreen";
import { spaceInviteURL } from "services/invite";
import {
    clearSpaceFriendsCache,
    confirmCurrentFriendRequest,
    deleteCurrentFriendRequest,
    loadCurrentFriendAvatarURL,
    loadCurrentFriendRequests,
    loadCurrentSpaceFriends,
    requestFriendByUsername,
    type SpaceFriendRequest,
} from "services/space";
import { useSpaceAppState } from "state/app-state";
import { spaceAppBackgroundColor } from "styles/colors";
import { isFriendRequestCanceledError } from "utils/friend-errors";
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
    const selectedFriend = friends.find(
        (friend) => friend.username == router.query.friend,
    );
    const isProfileExpanded = router.query.expanded == "1";

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
                background={spaceAppBackgroundColor}
                message={profileLoadError}
            />
        );
    }

    return (
        <>
            <SpacePageMeta themeColor={spaceAppBackgroundColor} />
            {!(selectedFriend && isProfileExpanded) && (
                <Box inert={Boolean(selectedFriend)}>
                    <FriendsScreen
                        friendRequests={friendRequests}
                        friends={friends}
                        isLoading={isFriendsLoading}
                        onBack={() => void router.back(spaceRoutes.home)}
                        onLoadFriendAvatar={loadCurrentFriendAvatarURL}
                        onAddFriend={async (username) => {
                            const actorSpaceId = profile.spaceId;
                            if (!actorSpaceId)
                                throw new Error("Missing space.");
                            const status = await requestFriendByUsername({
                                spaceUsername: username,
                            });
                            try {
                                if (status == "friend") {
                                    clearSpaceFriendsCache();
                                    const [requests, friends] =
                                        await Promise.all([
                                            loadCurrentFriendRequests(
                                                actorSpaceId,
                                            ),
                                            loadCurrentSpaceFriends(
                                                actorSpaceId,
                                            ),
                                        ]);
                                    setFriendRequests(requests);
                                    setFriends(friends);
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
                        onOpenFriend={(friendID) => {
                            const friend = friends.find(
                                (candidate) =>
                                    candidate.id == friendID ||
                                    candidate.spaceId == friendID,
                            );
                            if (friend)
                                void router.push(
                                    {
                                        pathname: spaceRoutes.friends,
                                        query: { friend: friend.username },
                                    },
                                    undefined,
                                    { shallow: true, scroll: false },
                                );
                        }}
                        profileLink={spaceInviteURL({
                            spaceUsername: profile.username,
                        })}
                        username={profile.username}
                        onAcceptFriendRequest={async (requestID) => {
                            const actorSpaceId = profile.spaceId;
                            if (!actorSpaceId) return false;
                            try {
                                await confirmCurrentFriendRequest(
                                    actorSpaceId,
                                    requestID,
                                );
                            } catch (error: unknown) {
                                if (!isFriendRequestCanceledError(error))
                                    throw error;
                                setFriendRequests((currentRequests) =>
                                    currentRequests.filter(
                                        (request) =>
                                            request.requestId != requestID,
                                    ),
                                );
                                setShowFriendRequestCanceledToast(true);
                                return false;
                            }
                            const loadedFriends =
                                await loadCurrentSpaceFriends(actorSpaceId);
                            setFriendRequests((currentRequests) =>
                                currentRequests.filter(
                                    (request) => request.requestId != requestID,
                                ),
                            );
                            setFriends(loadedFriends);
                            return true;
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
                                if (!isFriendRequestCanceledError(error))
                                    throw error;
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
                                                friend.id ==
                                                friendRequest.friend.id,
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
                    />
                </Box>
            )}
            {selectedFriend && (
                <FriendProfileSheet
                    key={selectedFriend.id}
                    expanded={isProfileExpanded}
                    friend={selectedFriend}
                    onClose={() => void router.back(spaceRoutes.friends)}
                    onExpand={() =>
                        void router.replace(
                            {
                                pathname: spaceRoutes.friends,
                                query: {
                                    friend: selectedFriend.username,
                                    expanded: "1",
                                },
                            },
                            spaceRoutes.friend(selectedFriend.username),
                            { shallow: true, scroll: false },
                        )
                    }
                />
            )}
            {showFriendRequestCanceledToast && (
                <SpaceFriendRequestCanceledToast
                    onClose={() => setShowFriendRequestCanceledToast(false)}
                />
            )}
        </>
    );
};

export default Page;
