import { FriendProfileSheet } from "components/FriendProfileSheet";
import type { FriendRequestSheetActions } from "components/FriendRequestSheet";
import { SpacePageMeta } from "components/PageMeta";
import { SpaceRouteFallback } from "components/RouteFallback";
import log from "ente-base/log";
import React, { useEffect, useState } from "react";
import { FriendsOrbitView } from "screens/FriendsScreen";
import type { SetupProfile } from "screens/SetupProfileScreen";
import { normalizeSpaceUsername } from "services/profile";
import {
    clearSpaceFriendsCache,
    confirmCurrentFriendRequest,
    deleteCurrentFriendRequest,
    loadCurrentFriendAvatarURL,
    loadProfileFriendList,
    requestFriendByUsername,
    type ProfileFriendListEntry,
} from "services/space";
import { useSpaceAppState } from "state/app-state";
import { spaceAppBackgroundColor } from "styles/colors";
import { isFriendRequestCanceledError } from "utils/friend-errors";
import { useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

const ProfileFriends = ({
    viewerSpaceId,
    profile,
    username: ownerUsername,
}: {
    viewerSpaceId: string;
    profile: SetupProfile;
    username: string;
}) => {
    const router = useSpaceRouter();
    const [entries, setEntries] = useState<ProfileFriendListEntry[]>();
    const [failed, setFailed] = useState(false);
    const load = React.useCallback(
        () =>
            loadProfileFriendList(
                viewerSpaceId,
                profile.username,
                ownerUsername,
            ),
        [viewerSpaceId, profile.username, ownerUsername],
    );
    useEffect(() => {
        let active = true;
        void load()
            .then((rows) => {
                if (active) setEntries(rows);
            })
            .catch((error: unknown) => {
                log.error("Failed to load profile friends", error);
                if (active) setFailed(true);
            });
        return () => {
            active = false;
        };
    }, [load]);

    const updateRequest = async (action: () => Promise<boolean>) => {
        let showConfirmation = false;
        try {
            showConfirmation = await action();
        } catch (error) {
            if (!isFriendRequestCanceledError(error)) throw error;
        }
        try {
            setEntries(await load());
        } catch (error) {
            log.error("Failed to refresh profile friends", error);
            setEntries(undefined);
            setFailed(true);
        }
        return showConfirmation;
    };

    const friends = [];
    const contacts: (FriendRequestSheetActions & { id: string })[] = [];
    for (const entry of entries ?? []) {
        const { username } = entry;
        if (entry.status === "self") {
            friends.push({ ...profile, id: username });
        } else if (entry.status === "friend") {
            friends.push({ ...entry.friend, id: username });
        } else if (entry.status === "available") {
            contacts.push({
                id: username,
                username,
                direction: "suggested",
                onPrimary: () =>
                    updateRequest(async () => {
                        const result = await requestFriendByUsername({
                            spaceUsername: username,
                        });
                        if (result === "friend") clearSpaceFriendsCache();
                        return result === "requested";
                    }),
            });
        } else {
            contacts.push({
                id: username,
                username,
                direction: entry.status,
                onPrimary:
                    entry.status === "received"
                        ? () =>
                              updateRequest(async () => {
                                  await confirmCurrentFriendRequest(
                                      viewerSpaceId,
                                      entry.requestId,
                                  );
                                  return true;
                              })
                        : undefined,
                onSecondary: async () => {
                    await updateRequest(async () => {
                        await deleteCurrentFriendRequest(
                            viewerSpaceId,
                            entry.requestId,
                        );
                        return false;
                    });
                },
            });
        }
    }
    const selectedEntry = entries?.find(
        (entry) => entry.username === router.query.friend,
    );
    const selectedFriend =
        selectedEntry?.status === "friend" ? selectedEntry.friend : undefined;
    const expanded = router.query.expanded === "1";
    const title = `@${ownerUsername}’s friends`;
    return (
        <>
            <SpacePageMeta title={title} themeColor={spaceAppBackgroundColor} />
            {!(selectedFriend && expanded) && (
                <div inert={Boolean(selectedFriend)}>
                    <FriendsOrbitView
                        currentUsername={profile.username}
                        centerInViewport
                        title={title}
                        friends={friends}
                        contacts={contacts}
                        isLoading={!entries && !failed}
                        emptyState={
                            failed ? (
                                <span role="alert">Couldn’t load friends.</span>
                            ) : (
                                "No friends yet."
                            )
                        }
                        onBack={() =>
                            void router.back(spaceRoutes.friend(ownerUsername))
                        }
                        onLoadFriendAvatar={(friend) =>
                            loadCurrentFriendAvatarURL(friend, viewerSpaceId)
                        }
                        onOpenFriend={(name) => {
                            if (name === profile.username)
                                void router.push(spaceRoutes.profile);
                            else
                                void router.push(
                                    {
                                        pathname: router.pathname,
                                        query: {
                                            username: ownerUsername,
                                            friend: name,
                                        },
                                    },
                                    undefined,
                                    { shallow: true, scroll: false },
                                );
                        }}
                    />
                </div>
            )}
            {selectedFriend && (
                <FriendProfileSheet
                    key={selectedFriend.id}
                    expanded={expanded}
                    friend={selectedFriend}
                    onClose={() =>
                        void router.back(
                            spaceRoutes.profileFriends(ownerUsername),
                        )
                    }
                    onExpand={() =>
                        void router.replace(
                            {
                                pathname: router.pathname,
                                query: {
                                    username: ownerUsername,
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
        </>
    );
};

const Page = () => {
    const router = useSpaceRouter();
    const { profile, profileLoadStatus, profileLoadError } = useSpaceAppState();
    const username =
        typeof router.query.username === "string"
            ? normalizeSpaceUsername(router.query.username)
            : "";
    const showOwnFriends = !username || username === profile?.username;
    useEffect(() => {
        if (!router.isReady || profileLoadStatus !== "ready") return;
        if (!profile) void router.replace(spaceRoutes.onboarding);
        else if (showOwnFriends) void router.replace(spaceRoutes.friends);
    }, [profile, profileLoadStatus, router, showOwnFriends]);
    if (
        !router.isReady ||
        profileLoadStatus !== "ready" ||
        !profile?.spaceId ||
        showOwnFriends
    )
        return (
            <SpaceRouteFallback
                background={spaceAppBackgroundColor}
                message={profileLoadError}
            />
        );
    return (
        <ProfileFriends
            key={`${profile.spaceId}:${username}`}
            viewerSpaceId={profile.spaceId}
            profile={profile}
            username={username}
        />
    );
};

export default Page;
