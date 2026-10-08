import { SpacePageMeta } from "components/PageMeta";
import { SpaceRouteFallback } from "components/RouteFallback";
import log from "ente-base/log";
import React from "react";
import { MessagesScreen } from "screens/MessagesScreen";
import type { SetupProfile } from "screens/SetupProfileScreen";
import { spaceInviteURL } from "services/invite";
import {
    deleteCurrentMessage,
    loadCurrentFriendAvatarURL,
    loadCurrentMessageConversations,
    loadCurrentMessageThread,
    loadCurrentPostPreview,
    loadCurrentSpaceProfile,
    markCurrentMessagesRead,
    replyToCurrentMessage,
    sendCurrentMessage,
    setCurrentMessageReaction,
    shouldAutoReadMessageActivities,
    type SpaceMessage,
    type SpaceMessageConversation,
} from "services/space";
import { useSpaceAppState } from "state/app-state";
import { spaceAppBackgroundColor } from "styles/colors";
import { useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

interface SpaceMessagesPageProps {
    selectedSpaceId?: string;
}

const friendSpaceId = (friend: SpaceMessageConversation["friend"]) =>
    friend.spaceId ?? friend.id;

const conversationId = (conversation: SpaceMessageConversation) =>
    friendSpaceId(conversation.friend);

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
    kind,
    profile,
    recipient,
    replyMessageId,
    text,
}: {
    kind: SpaceMessage["kind"];
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
        kind,
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
    const {
        postPublication,
        profile,
        profileLoadError,
        profileLoadStatus,
        setFriends,
    } = useSpaceAppState();
    const [conversations, setConversations] = React.useState<
        SpaceMessageConversation[]
    >([]);
    const [isConversationsLoading, setIsConversationsLoading] =
        React.useState(true);
    const [isThreadLoading, setIsThreadLoading] = React.useState(false);
    const [messages, setMessages] = React.useState<SpaceMessage[]>([]);
    const reactionQueues = React.useRef(new Map<string, Promise<void>>());
    const savedReactions = React.useRef(new Map<string, string | undefined>());
    const localReactions = React.useRef(new Map<string, string | undefined>());

    const [selectedFriendProfile, setSelectedFriendProfile] =
        React.useState<SpaceMessageConversation["friend"]>();
    const [
        selectedFriendProfileLoadFailedSpaceId,
        setSelectedFriendProfileLoadFailedSpaceId,
    ] = React.useState<string>();
    const selectedFriendSpaceIdRef = React.useRef<string | undefined>(
        undefined,
    );
    const markedReadSpaceIdRef = React.useRef<string | undefined>(undefined);
    const conversationsLoadGenerationRef = React.useRef(0);
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
        () => conversations.map((conversation) => conversation.friend),
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
    const selectedFriendName =
        selectedFriend?.fullName.trim() || selectedFriend?.username;
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
                    log.warn("Failed to mark message conversation read", error),
            );
        },
        [profile?.spaceId],
    );

    const refreshConversations = React.useCallback(async () => {
        const actorSpaceId = profile?.spaceId;
        if (!actorSpaceId) return false;

        const generation = ++conversationsLoadGenerationRef.current;
        setIsConversationsLoading(true);
        try {
            const page = await loadCurrentMessageConversations(actorSpaceId);
            if (conversationsLoadGenerationRef.current != generation) {
                return false;
            }
            const items = page.items.sort((a, b) => {
                const createdAtDiff =
                    b.latestActivity.createdAtMs - a.latestActivity.createdAtMs;
                if (createdAtDiff != 0) return createdAtDiff;
                return b.latestActivity.id.localeCompare(a.latestActivity.id);
            });
            const passiveUnreadConversationIds = items
                .filter((conversation) =>
                    shouldAutoReadMessageActivities(
                        conversation.unreadActivities,
                    ),
                )
                .map(conversationId);
            setConversations(items);
            setFriends(items.map((conversation) => conversation.friend));
            for (const conversation of items) {
                const friend = conversation.friend;
                if (
                    friend.avatarUrl ||
                    !friend.avatarObjectID ||
                    !friend.avatarKeyVersion
                ) {
                    continue;
                }

                const itemID = conversationId(conversation);
                const itemFriendSpaceID = friendSpaceId(friend);
                void loadCurrentFriendAvatarURL(friend, actorSpaceId)
                    .then((avatarUrl) => {
                        if (
                            !avatarUrl ||
                            conversationsLoadGenerationRef.current != generation
                        ) {
                            return;
                        }

                        setConversations((currentConversations) =>
                            currentConversations.map((currentConversation) => {
                                const currentFriend =
                                    currentConversation.friend;
                                return conversationId(currentConversation) ==
                                    itemID &&
                                    currentFriend.avatarObjectID ==
                                        friend.avatarObjectID &&
                                    currentFriend.avatarKeyVersion ==
                                        friend.avatarKeyVersion
                                    ? {
                                          ...currentConversation,
                                          friend: {
                                              ...currentFriend,
                                              avatarUrl,
                                          },
                                      }
                                    : currentConversation;
                            }),
                        );
                        setFriends((currentFriends) =>
                            currentFriends.map((currentFriend) =>
                                friendSpaceId(currentFriend) ==
                                    itemFriendSpaceID &&
                                currentFriend.avatarObjectID ==
                                    friend.avatarObjectID &&
                                currentFriend.avatarKeyVersion ==
                                    friend.avatarKeyVersion
                                    ? { ...currentFriend, avatarUrl }
                                    : currentFriend,
                            ),
                        );
                    })
                    .catch((error: unknown) =>
                        log.warn(
                            "Failed to load message conversation avatar",
                            error,
                        ),
                    );
            }
            if (passiveUnreadConversationIds.length > 0) {
                void Promise.all(
                    passiveUnreadConversationIds.map((spaceId) =>
                        markCurrentMessagesRead(actorSpaceId, spaceId),
                    ),
                ).catch((error: unknown) =>
                    log.warn(
                        "Failed to mark passive message activity read",
                        error,
                    ),
                );
            }
            return true;
        } catch (error: unknown) {
            log.error("Failed to load message conversations", error);
            return false;
        } finally {
            if (conversationsLoadGenerationRef.current == generation) {
                setIsConversationsLoading(false);
            }
        }
    }, [profile?.spaceId, setFriends]);

    React.useEffect(
        () => () => {
            conversationsLoadGenerationRef.current += 1;
        },
        [],
    );

    const openConversation = React.useCallback(
        (conversation: SpaceMessageConversation) => {
            void router.push(spaceRoutes.message(conversationId(conversation)));
        },
        [router],
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
        if (postPublication?.phase == "posted") void refreshConversations();
    }, [postPublication?.phase, refreshConversations]);

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
                log.error("Failed to load selected space profile", error);
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
        for (const messageId of localReactions.current.keys()) {
            if (!reactionQueues.current.has(messageId))
                localReactions.current.delete(messageId);
        }
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
                        ...page.items.map((message) => {
                            if (!localReactions.current.has(message.id))
                                return message;
                            const reaction = localReactions.current.get(
                                message.id,
                            );
                            return {
                                ...message,
                                reaction,
                                liked: Boolean(reaction),
                                viewerLiked: Boolean(reaction),
                            };
                        }),
                        ...currentMessages.filter(
                            (message) => !loadedMessageIds.has(message.id),
                        ),
                    ]);
                }
            })
            .catch((error: unknown) =>
                log.error("Failed to load message thread", error),
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
            <SpacePageMeta
                themeColor={spaceAppBackgroundColor}
                title={
                    selectedFriendName
                        ? `Messages with ${selectedFriendName}`
                        : "Messages"
                }
            />
            <MessagesScreen
                conversations={conversations}
                friendsCount={conversationFriends.length}
                isConversationsLoading={isConversationsLoading}
                isThreadLoading={isThreadLoading}
                isThreadReadOnly={isThreadReadOnly}
                isThreadRecipientLoading={isThreadRecipientLoading}
                messages={messages}
                onCloseThread={closeConversation}
                onOpenSelectedFriendProfile={(friend) => {
                    const username = friend.username || friend.spaceSlug;
                    if (username)
                        void router.push(
                            spaceRoutes.friendPage,
                            spaceRoutes.friend(username),
                        );
                }}
                onOpenQuotePost={(quote) =>
                    void router.push(
                        spaceRoutes.post(
                            quote.spaceId,
                            quote.postId,
                            quote.objectKey,
                        ),
                    )
                }
                onOpenThread={openConversation}
                onLoadActivityPost={(post) =>
                    loadCurrentPostPreview(post, actorSpaceId)
                }
                onSendMessage={async (spaceId, text) => {
                    const sender = currentProfileMessageActor(profile);
                    const recipient =
                        selectedFriend ?? placeholderFriend(spaceId);
                    const optimisticMessage = createLocalMessage({
                        kind: "regular",
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
                        kind: "regular",
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
                onSetMessageReaction={async (messageId, emoji) => {
                    const message = messages.find(
                        (item) => item.id == messageId,
                    )!;
                    const previous = reactionQueues.current.get(messageId);
                    if (!previous)
                        savedReactions.current.set(messageId, message.reaction);
                    const update = (reaction: string | undefined) => {
                        localReactions.current.set(messageId, reaction);
                        setMessages((items) =>
                            items.map((item) =>
                                item.id == messageId
                                    ? {
                                          ...item,
                                          reaction,
                                          liked: Boolean(reaction),
                                          viewerLiked: Boolean(reaction),
                                      }
                                    : item,
                            ),
                        );
                    };
                    update(emoji);
                    const request = (previous ?? Promise.resolve())
                        .catch(() => undefined)
                        .then(async () => {
                            await setCurrentMessageReaction(
                                actorSpaceId,
                                message.sender.spaceId!,
                                messageId,
                                emoji,
                            );
                            savedReactions.current.set(messageId, emoji);
                        });
                    reactionQueues.current.set(messageId, request);
                    try {
                        await request;
                        if (reactionQueues.current.get(messageId) == request)
                            update(emoji);
                    } catch (error) {
                        if (reactionQueues.current.get(messageId) == request)
                            update(savedReactions.current.get(messageId));
                        throw error;
                    } finally {
                        if (reactionQueues.current.get(messageId) == request) {
                            reactionQueues.current.delete(messageId);
                            savedReactions.current.delete(messageId);
                            void refreshConversations();
                        }
                    }
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
