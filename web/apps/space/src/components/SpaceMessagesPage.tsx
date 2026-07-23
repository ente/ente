import { SpacePageMeta } from "components/SpacePageMeta";
import { SpaceRouteFallback } from "components/SpaceRouteFallback";
import React from "react";
import { MessagesScreen, messagesBackground } from "screens/MessagesScreen";
import type { SetupProfile } from "screens/SetupProfileScreen";
import {
    confirmCurrentFriendRequest,
    deleteCurrentFriendRequest,
    deleteCurrentMessage,
    loadCurrentMessageActivityPostPreview,
    loadCurrentMessageConversations,
    loadCurrentMessageThread,
    loadCurrentSpaceProfile,
    markCurrentMessagesRead,
    replyToCurrentMessage,
    sendCurrentMessage,
    setCurrentMessageLiked,
    shouldAutoReadMessageActivities,
    type SpaceMessage,
    type SpaceMessageConversation,
} from "services/space";
import { spaceInviteURL } from "services/spaceInvite";
import { useSpaceAppState } from "state/spaceAppState";
import { spaceRoutes } from "utils/spaceRoutes";
import { useSpaceRouter } from "utils/spaceRouteTransitions";

interface SpaceMessagesPageProps {
    selectedSpaceId?: string;
}

const friendSpaceId = (friend: SpaceMessageConversation["friend"]) =>
    friend.spaceId ?? friend.id;

const conversationId = (conversation: SpaceMessageConversation) =>
    conversation.latestActivity.type == "friend_request"
        ? conversation.latestActivity.id
        : friendSpaceId(conversation.friend);

const friendRequestIdFromConversation = (
    conversation: SpaceMessageConversation,
) => Number(conversation.latestActivity.id.split(":")[1]);

const isFriendRequestConversation = (conversation: SpaceMessageConversation) =>
    conversation.latestActivity.type == "friend_request";

let nextLocalMessageID = 0;

const localMessageIdPrefix = "space-local-message-";

const createLocalMessageID = () =>
    `${localMessageIdPrefix}${Date.now()}-${nextLocalMessageID++}`;

const placeholderFriend = (
    spaceId: string,
): SpaceMessageConversation["friend"] => ({
    avatarUrl: null,
    friendsCount: 0,
    fullName: "",
    id: spaceId,
    spaceId,
    username: "",
});

const currentProfileMessageActor = (
    profile: SetupProfile,
): SpaceMessage["sender"] => ({
    avatarKeyVersion: profile.avatarKeyVersion,
    avatarObjectID: profile.avatarObjectID,
    avatarUpdatedAt: profile.avatarUpdatedAt,
    avatarUrl: profile.avatarUrl,
    friendsCount: 0,
    fullName: profile.fullName,
    id: profile.spaceId ?? profile.username,
    spaceId: profile.spaceId,
    spaceSlug: profile.spaceSlug,
    username: profile.username,
});

const createLocalMessage = ({
    profile,
    recipient,
    replyMessageId,
    text,
}: {
    profile: SetupProfile;
    recipient: SpaceMessageConversation["friend"];
    replyMessageId?: string;
    text: string;
}): SpaceMessage => {
    const createdAtMs = Date.now();
    return {
        createdAtMs,
        id: createLocalMessageID(),
        isDeleted: false,
        kind: "regular",
        liked: false,
        recipient,
        replyMessageId,
        sender: currentProfileMessageActor(profile),
        text,
        updatedAtMs: createdAtMs,
        viewerLiked: false,
    };
};

export const SpaceMessagesPage: React.FC<SpaceMessagesPageProps> = ({
    selectedSpaceId,
}) => {
    const router = useSpaceRouter();
    const { profile, profileLoadError, profileLoadStatus, setFriends } =
        useSpaceAppState();
    const [conversations, setConversations] = React.useState<
        SpaceMessageConversation[]
    >([]);
    const [isConversationsLoading, setIsConversationsLoading] =
        React.useState(true);
    const [isThreadLoading, setIsThreadLoading] = React.useState(false);
    const [messages, setMessages] = React.useState<SpaceMessage[]>([]);
    const [selectedFriendProfile, setSelectedFriendProfile] =
        React.useState<SpaceMessageConversation["friend"]>();
    const [
        selectedFriendProfileLoadFailedSpaceId,
        setSelectedFriendProfileLoadFailedSpaceId,
    ] = React.useState<string>();
    const [newConversationIds, setNewConversationIds] = React.useState<
        string[]
    >([]);
    const selectedFriendSpaceIdRef = React.useRef<string | undefined>(
        undefined,
    );
    const markedReadSpaceIdRef = React.useRef<string | undefined>(undefined);
    const previousSelectedSpaceIdRef = React.useRef<string | undefined>(
        selectedSpaceId,
    );
    const selectedConversation = React.useMemo(
        () =>
            selectedSpaceId
                ? conversations.find(
                      (conversation) =>
                          conversationId(conversation) == selectedSpaceId,
                  )
                : undefined,
        [conversations, selectedSpaceId],
    );
    const conversationFriends = React.useMemo(
        () =>
            conversations
                .filter(
                    (conversation) =>
                        !isFriendRequestConversation(conversation),
                )
                .map((conversation) => conversation.friend),
        [conversations],
    );
    const selectedFriendFromFriends = React.useMemo(
        () =>
            selectedSpaceId
                ? conversationFriends.find(
                      (friend) => friendSpaceId(friend) == selectedSpaceId,
                  )
                : undefined,
        [conversationFriends, selectedSpaceId],
    );
    const selectedLoadedFriendProfile =
        selectedFriendProfile &&
        friendSpaceId(selectedFriendProfile) == selectedSpaceId
            ? selectedFriendProfile
            : undefined;
    const selectedFriendPlaceholder = React.useMemo(
        () =>
            selectedSpaceId ? placeholderFriend(selectedSpaceId) : undefined,
        [selectedSpaceId],
    );
    const selectedFriend =
        selectedConversation?.friend ??
        selectedFriendFromFriends ??
        selectedLoadedFriendProfile ??
        selectedFriendPlaceholder;
    const selectedFriendSpaceId = selectedFriend
        ? friendSpaceId(selectedFriend)
        : undefined;
    const selectedFriendSpaceSlug = selectedFriend?.spaceSlug;
    const selectedFriendUsername = selectedFriend?.username;
    const isSelectedFriendCurrent = Boolean(
        selectedFriendSpaceId &&
        conversationFriends.some((friend) => {
            const currentFriendSpaceId = friendSpaceId(friend);
            return (
                currentFriendSpaceId == selectedFriendSpaceId ||
                (selectedFriendSpaceSlug &&
                    friend.spaceSlug == selectedFriendSpaceSlug) ||
                friend.username == selectedFriendUsername
            );
        }),
    );
    const isThreadRecipientLoading =
        Boolean(selectedFriend) &&
        isConversationsLoading &&
        !isSelectedFriendCurrent;
    const isThreadReadOnly =
        Boolean(selectedFriend) &&
        !isConversationsLoading &&
        !isSelectedFriendCurrent;

    const markConversationRead = React.useCallback(
        (spaceId: string) => {
            const actorSpaceId = profile?.spaceId;
            if (!actorSpaceId) return;

            setNewConversationIds((currentIds) =>
                currentIds.filter((id) => id != spaceId),
            );
            setConversations((currentConversations) => {
                return currentConversations.map((conversation) =>
                    conversationId(conversation) == spaceId
                        ? {
                              ...conversation,
                              notificationUnread: false,
                              unread: false,
                              unreadActivities: [],
                              unreadCount: 0,
                          }
                        : conversation,
                );
            });
            void markCurrentMessagesRead(actorSpaceId, spaceId).catch(
                (error: unknown) =>
                    console.warn(
                        "Failed to mark message conversation read",
                        error,
                    ),
            );
        },
        [profile?.spaceId],
    );

    const refreshConversations = React.useCallback(async () => {
        const actorSpaceId = profile?.spaceId;
        if (!actorSpaceId) return false;

        setIsConversationsLoading(true);
        try {
            const page = await loadCurrentMessageConversations(actorSpaceId);
            const items = page.items.sort((a, b) => {
                const createdAtDiff =
                    b.latestActivity.createdAtMs - a.latestActivity.createdAtMs;
                if (createdAtDiff != 0) return createdAtDiff;
                return b.latestActivity.id.localeCompare(a.latestActivity.id);
            });
            const unreadConversationIds = items
                .filter((conversation) => conversation.notificationUnread)
                .map(conversationId);
            const passiveUnreadConversationIds = items
                .filter((conversation) =>
                    shouldAutoReadMessageActivities(
                        conversation.unreadActivities,
                    ),
                )
                .map(conversationId);
            setNewConversationIds(unreadConversationIds);
            setConversations(items);
            setFriends(
                items
                    .filter(
                        (conversation) =>
                            !isFriendRequestConversation(conversation),
                    )
                    .map((conversation) => conversation.friend),
            );
            if (passiveUnreadConversationIds.length > 0) {
                void Promise.all(
                    passiveUnreadConversationIds.map((spaceId) =>
                        markCurrentMessagesRead(actorSpaceId, spaceId),
                    ),
                ).catch((error: unknown) =>
                    console.warn(
                        "Failed to mark passive message activity read",
                        error,
                    ),
                );
            }
            return true;
        } catch (error: unknown) {
            console.error("Failed to load message conversations", error);
            return false;
        } finally {
            setIsConversationsLoading(false);
        }
    }, [profile?.spaceId, setFriends]);

    const openConversation = React.useCallback(
        (conversation: SpaceMessageConversation) => {
            if (isFriendRequestConversation(conversation)) return;
            void router.push(spaceRoutes.message(conversationId(conversation)));
        },
        [router],
    );

    const confirmFriendRequest = React.useCallback(
        async (conversation: SpaceMessageConversation) => {
            const actorSpaceId = profile?.spaceId;
            if (!actorSpaceId) throw new Error("Missing space.");

            await confirmCurrentFriendRequest(
                actorSpaceId,
                friendRequestIdFromConversation(conversation),
            );
            window.location.reload();
        },
        [profile?.spaceId],
    );

    const deleteFriendRequest = React.useCallback(
        async (conversation: SpaceMessageConversation) => {
            const actorSpaceId = profile?.spaceId;
            if (!actorSpaceId) throw new Error("Missing space.");

            await deleteCurrentFriendRequest(
                actorSpaceId,
                friendRequestIdFromConversation(conversation),
            );
            void refreshConversations();
        },
        [profile?.spaceId, refreshConversations],
    );

    const closeConversation = React.useCallback(() => {
        if (selectedSpaceId) void router.push(spaceRoutes.messages);
    }, [router, selectedSpaceId]);

    const appendMessageIfThreadIsCurrent = React.useCallback(
        (spaceId: string, message: SpaceMessage) => {
            if (selectedFriendSpaceIdRef.current != spaceId) return;
            setMessages((currentMessages) => [...currentMessages, message]);
        },
        [],
    );

    const replaceMessageIfThreadIsCurrent = React.useCallback(
        (spaceId: string, localMessageId: string, message: SpaceMessage) => {
            if (selectedFriendSpaceIdRef.current != spaceId) return;
            setMessages((currentMessages) => {
                const hasConfirmedMessage = currentMessages.some(
                    (currentMessage) => currentMessage.id == message.id,
                );
                if (hasConfirmedMessage) {
                    return currentMessages
                        .filter(
                            (currentMessage) =>
                                currentMessage.id != localMessageId,
                        )
                        .map((currentMessage) =>
                            currentMessage.id == message.id
                                ? message
                                : currentMessage,
                        );
                }

                const hasLocalMessage = currentMessages.some(
                    (currentMessage) => currentMessage.id == localMessageId,
                );
                if (!hasLocalMessage) return [...currentMessages, message];

                return currentMessages.map((currentMessage) =>
                    currentMessage.id == localMessageId
                        ? message
                        : currentMessage,
                );
            });
        },
        [],
    );

    const removeMessageIfThreadIsCurrent = React.useCallback(
        (spaceId: string, messageId: string) => {
            if (selectedFriendSpaceIdRef.current != spaceId) return;
            setMessages((currentMessages) =>
                currentMessages.filter((message) => message.id != messageId),
            );
        },
        [],
    );

    React.useEffect(() => {
        if (profileLoadStatus == "ready" && !profile) {
            void router.replace(spaceRoutes.onboarding);
        }
    }, [profile, profileLoadStatus, router]);

    React.useEffect(() => {
        if (!profile?.spaceId) return;
        void refreshConversations();
    }, [profile?.spaceId, refreshConversations]);

    React.useEffect(() => {
        const previousSelectedSpaceId = previousSelectedSpaceIdRef.current;
        previousSelectedSpaceIdRef.current = selectedSpaceId;

        if (!profile?.spaceId || selectedSpaceId || !previousSelectedSpaceId)
            return;
        void refreshConversations();
    }, [profile?.spaceId, refreshConversations, selectedSpaceId]);

    React.useEffect(() => {
        if (!selectedSpaceId || !selectedConversation) return;
        if (markedReadSpaceIdRef.current == selectedSpaceId) return;

        markedReadSpaceIdRef.current = selectedSpaceId;
        markConversationRead(selectedSpaceId);
    }, [markConversationRead, selectedConversation, selectedSpaceId]);

    const shouldLoadSelectedFriendProfile = Boolean(
        selectedSpaceId &&
        !isConversationsLoading &&
        !selectedConversation &&
        !selectedFriendFromFriends,
    );

    React.useEffect(() => {
        setSelectedFriendProfile(undefined);
        setSelectedFriendProfileLoadFailedSpaceId(undefined);

        const actorSpaceId = profile?.spaceId;
        if (
            !actorSpaceId ||
            !selectedSpaceId ||
            !shouldLoadSelectedFriendProfile
        )
            return;

        let cancelled = false;
        void loadCurrentSpaceProfile(selectedSpaceId, actorSpaceId)
            .then((friend) => {
                if (!cancelled) setSelectedFriendProfile(friend);
            })
            .catch((error: unknown) => {
                console.error("Failed to load selected space profile", error);
                if (!cancelled) {
                    setSelectedFriendProfileLoadFailedSpaceId(selectedSpaceId);
                }
            });

        return () => {
            cancelled = true;
        };
    }, [profile?.spaceId, selectedSpaceId, shouldLoadSelectedFriendProfile]);

    React.useEffect(() => {
        if (
            !selectedSpaceId ||
            isConversationsLoading ||
            selectedConversation ||
            selectedFriendFromFriends ||
            selectedLoadedFriendProfile ||
            (shouldLoadSelectedFriendProfile &&
                selectedFriendProfileLoadFailedSpaceId != selectedSpaceId)
        ) {
            return;
        }

        void router.replace(spaceRoutes.messages);
    }, [
        isConversationsLoading,
        router,
        selectedConversation,
        selectedFriendFromFriends,
        selectedFriendProfileLoadFailedSpaceId,
        selectedLoadedFriendProfile,
        selectedSpaceId,
        shouldLoadSelectedFriendProfile,
    ]);

    React.useEffect(() => {
        markedReadSpaceIdRef.current = undefined;

        const actorSpaceId = profile?.spaceId;
        if (!profile || !actorSpaceId || !selectedSpaceId) {
            selectedFriendSpaceIdRef.current = undefined;
            setMessages([]);
            setIsThreadLoading(false);
            return;
        }

        let cancelled = false;
        selectedFriendSpaceIdRef.current = selectedSpaceId;
        setMessages([]);
        setIsThreadLoading(true);
        const viewer = currentProfileMessageActor(profile);
        const friend = selectedFriend ?? placeholderFriend(selectedSpaceId);
        void loadCurrentMessageThread(
            actorSpaceId,
            selectedSpaceId,
            viewer,
            friend,
        )
            .then((page) => {
                if (!cancelled) {
                    const loadedMessageIds = new Set(
                        page.items.map((message) => message.id),
                    );
                    setMessages((currentMessages) => [
                        ...page.items,
                        ...currentMessages.filter(
                            (message) => !loadedMessageIds.has(message.id),
                        ),
                    ]);
                }
            })
            .catch((error: unknown) =>
                console.error("Failed to load message thread", error),
            )
            .finally(() => {
                if (!cancelled) setIsThreadLoading(false);
            });

        return () => {
            cancelled = true;
        };
        // This fetch is keyed by thread identity. Actor display hydration should
        // not clear and refetch the open thread.
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [profile?.spaceId, selectedFriendSpaceId, selectedSpaceId]);

    if (profileLoadStatus != "ready" || !profile) {
        return (
            <SpaceRouteFallback
                background={messagesBackground}
                message={profileLoadError}
            />
        );
    }
    const actorSpaceId = profile.spaceId;
    if (!actorSpaceId) {
        return (
            <SpaceRouteFallback
                background={messagesBackground}
                message={profileLoadError}
            />
        );
    }

    return (
        <>
            <SpacePageMeta themeColor={messagesBackground} />
            <MessagesScreen
                conversations={conversations}
                friendsCount={conversationFriends.length}
                isConversationsLoading={isConversationsLoading}
                isThreadLoading={isThreadLoading}
                isThreadReadOnly={isThreadReadOnly}
                isThreadRecipientLoading={isThreadRecipientLoading}
                messages={messages}
                newConversationIds={newConversationIds}
                onBack={() => void router.push(spaceRoutes.home)}
                onCloseThread={closeConversation}
                onConfirmFriendRequest={confirmFriendRequest}
                onDeleteFriendRequest={deleteFriendRequest}
                onOpenSelectedFriendProfile={(friend) =>
                    void router.push(spaceRoutes.friend(friendSpaceId(friend)))
                }
                onOpenQuotePost={(quote) =>
                    void router.push(
                        spaceRoutes.post(quote.spaceId, quote.postId),
                    )
                }
                onOpenThread={openConversation}
                onLoadActivityPost={(post) =>
                    loadCurrentMessageActivityPostPreview(post, actorSpaceId)
                }
                onSendMessage={async (spaceId, text) => {
                    const sender = currentProfileMessageActor(profile);
                    const recipient =
                        selectedFriend ?? placeholderFriend(spaceId);
                    const optimisticMessage = createLocalMessage({
                        profile,
                        recipient,
                        text,
                    });
                    appendMessageIfThreadIsCurrent(spaceId, optimisticMessage);
                    try {
                        const message = await sendCurrentMessage(
                            actorSpaceId,
                            spaceId,
                            text,
                            sender,
                            recipient,
                        );
                        replaceMessageIfThreadIsCurrent(
                            spaceId,
                            optimisticMessage.id,
                            message,
                        );
                    } catch (error) {
                        removeMessageIfThreadIsCurrent(
                            spaceId,
                            optimisticMessage.id,
                        );
                        throw error;
                    }
                    void refreshConversations();
                }}
                onReplyToMessage={async (spaceId, messageId, text) => {
                    const sender = currentProfileMessageActor(profile);
                    const recipient =
                        selectedFriend ?? placeholderFriend(spaceId);
                    const optimisticMessage = createLocalMessage({
                        profile,
                        recipient,
                        replyMessageId: messageId,
                        text,
                    });
                    appendMessageIfThreadIsCurrent(spaceId, optimisticMessage);
                    try {
                        const message = await replyToCurrentMessage(
                            actorSpaceId,
                            spaceId,
                            messageId,
                            text,
                            sender,
                            recipient,
                        );
                        replaceMessageIfThreadIsCurrent(
                            spaceId,
                            optimisticMessage.id,
                            message,
                        );
                    } catch (error) {
                        removeMessageIfThreadIsCurrent(
                            spaceId,
                            optimisticMessage.id,
                        );
                        throw error;
                    }
                    void refreshConversations();
                }}
                onSetMessageLiked={async (messageId, liked) => {
                    await setCurrentMessageLiked(
                        actorSpaceId,
                        messageId,
                        liked,
                    );
                    setMessages((currentMessages) =>
                        currentMessages.map((message) =>
                            message.id == messageId
                                ? { ...message, liked, viewerLiked: liked }
                                : message,
                        ),
                    );
                    void refreshConversations();
                }}
                profileLink={spaceInviteURL({
                    spaceUsername: profile.username,
                })}
                onDeleteMessage={async (messageId) => {
                    await deleteCurrentMessage(actorSpaceId, messageId);
                    setMessages((currentMessages) =>
                        currentMessages.filter(
                            (message) => message.id != messageId,
                        ),
                    );
                    void refreshConversations();
                }}
                profile={profile}
                selectedFriend={selectedFriend}
            />
        </>
    );
};
