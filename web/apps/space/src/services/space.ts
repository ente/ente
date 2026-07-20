import type { FriendProfile } from "data/friends";
import { apiOrigin } from "ente-base/origins";
import type { SpaceAccountCtxHandle } from "ente-space-wasm";
import type { PendingSpaceInvite } from "services/spaceInvite";
import {
    cachedSpaceMediaBlobURL,
    rememberCachedSpaceMediaBlobURL,
    spacePostMediaCacheKey,
    spaceProfileMediaCacheKey,
} from "services/spaceMediaCache";
import {
    ensureCurrentSpaceContext,
    loadExistingSpaceProfile,
    releaseCurrentSpaceContext,
} from "services/spaceProfile";
import {
    parseSpaceProfilePayload,
    spaceProfileTextField,
} from "services/spaceProfilePayload";
import { normalizeSpaceMessageText } from "utils/spaceMessageLimits";

export { clearSpaceMediaURLCache } from "services/spaceMediaCache";

const currentFeedPageSize = 10;

interface SpaceAvatar {
    keyVersion: number;
    objectID: string;
    size?: number;
    updatedAt?: string;
}

type SpaceCover = SpaceAvatar;

interface SpaceProfileResponse {
    avatar?: SpaceAvatar;
    cover?: SpaceCover;
    friends?: number;
    profile: string;
    updatedAt?: string;
    version?: number;
    spaceId: string;
    spaceSlug: string;
}

interface SpaceActor {
    avatar?: SpaceAvatar;
    profile?: string;
    publicKey?: string;
    spaceId: string;
    spaceSlug: string;
}

interface SpacePostObject {
    height?: number;
    mediaType?: string;
    objectKey: string;
    size?: number;
    thumbHash?: string;
    width?: number;
}

interface SpacePostResponse {
    author: SpaceActor;
    caption?: string;
    createdAt: string;
    encryptedPostKey: string;
    keyVersion: number;
    objects?: SpacePostObject[];
    postId: number;
    viewerLiked: boolean;
    spaceId: string;
    spaceSlug: string;
}

interface SpacePostPageResponse {
    items?: SpacePostResponse[];
    nextCursor?: string;
}

type SpaceMessageConversationActivityType =
    | "empty"
    | "friend_request"
    | "friend_added"
    | "message"
    | "message_like"
    | "post_like"
    | "post_reply";

interface SpaceMessageConversationActivity {
    createdAt: string;
    id: string;
    messageId?: string;
    outgoing?: boolean;
    postId?: number;
    postSpaceId?: string;
    text?: string;
    type: SpaceMessageConversationActivityType;
}

interface SpaceFriend {
    createdAt: string;
    friend: SpaceActor;
    shareKeyVersion: number;
}

type SpaceMessageKindResponse =
    | "friend_added"
    | "post_like"
    | "post_reply"
    | "regular";

interface SpaceMessageResponse {
    createdAt: string;
    id?: string;
    isDeleted?: boolean;
    kind: SpaceMessageKindResponse;
    liked?: boolean;
    messageId: string;
    recipientSpaceId: string;
    replyMessageId?: string;
    replyPostId?: number;
    senderSpaceId: string;
    text: string;
    viewerLiked?: boolean;
    updatedAt: string;
}

interface SpaceMessagePageResponse {
    items?: SpaceMessageResponse[];
    nextCursor?: string;
}

interface SpaceFriendRequestResponse {
    requestId: number;
    requester: SpaceActor;
    createdAt: string;
}

interface SpaceConversationChatSummaryResponse {
    latestActivity: SpaceMessageConversationActivity;
    unreadActivities?: SpaceMessageConversationActivity[];
}

type SpaceConversationChatSummaries =
    | Record<string, SpaceConversationChatSummaryResponse>
    | Map<string, SpaceConversationChatSummaryResponse>;

interface SpaceConversationsResponse {
    chatSummaries?: SpaceConversationChatSummaries;
    friends?: SpaceFriend[];
    pendingRequests?: SpaceFriendRequestResponse[];
}

interface SpacePostBase {
    avatarKeyVersion?: number;
    avatarObjectID?: string;
    avatarSize?: number;
    avatarUpdatedAt?: string;
    avatarUrl?: string | null;
    caption?: string;
    friendID: string;
    height?: number;
    name: string;
    postId: number;
    timestampMs: number;
    thumbHash?: string;
    viewerLiked: boolean;
    spaceId: string;
    width?: number;
}

export interface SpacePostAsset {
    encryptedPostKey: string;
    keyVersion: number;
    mediaType?: string;
    objectKey: string;
    postId: number;
    spaceId: string;
}

export interface SpacePost extends SpacePostBase {
    imageAsset?: SpacePostAsset;
    imageUrl?: string;
}

export interface SpacePostPage {
    items: SpacePost[];
    nextCursor?: string;
}

export interface SpaceProfilePost extends SpacePostBase {
    imageAsset?: SpacePostAsset;
    imageUrl?: string;
}

export interface SpaceProfilePostPage {
    items: SpaceProfilePost[];
    nextCursor?: string;
}

export type SpacePostAssetURLLoader = (
    asset: SpacePostAsset,
) => Promise<string>;

export type SpacePostAvatarURLLoader = (
    post: SpacePost,
) => Promise<string | null>;

export interface PublicSpaceIdentity {
    spaceId: string;
    username: string;
}

interface PublicSpaceIdentityResponse {
    spaceId?: string;
    spaceSlug?: string;
}

export type SpaceMessageKind = SpaceMessageKindResponse;

export interface SpaceMessageQuote {
    imageUrl?: string;
    isUnavailable?: boolean;
    postId: number;
    spaceId: string;
}

export interface SpaceMessage {
    createdAtMs: number;
    id: string;
    isDeleted: boolean;
    kind: SpaceMessageKind;
    liked: boolean;
    quote?: SpaceMessageQuote;
    recipient: FriendProfile;
    replyMessageId?: string;
    replyPostId?: number;
    sender: FriendProfile;
    text: string;
    updatedAtMs: number;
    viewerLiked: boolean;
}

export type SpaceMessageActivityType = SpaceMessageConversationActivityType;

export interface SpaceMessageActivityPost {
    imageUrl?: string;
    isDeleted?: boolean;
    postId: number;
    spaceId: string;
}

export interface SpaceMessageActivity {
    createdAtMs: number;
    id: string;
    messageId?: string;
    outgoing: boolean;
    post?: SpaceMessageActivityPost;
    text?: string;
    type: SpaceMessageActivityType;
}

export interface SpaceMessagePage {
    items: SpaceMessage[];
    nextCursor?: string;
}

interface SpaceMessageHydrationActors {
    friend: FriendProfile;
    viewer: FriendProfile;
}

export interface SpaceMessageConversation {
    friend: FriendProfile;
    latestActivity: SpaceMessageActivity;
    notificationUnread: boolean;
    unread: boolean;
    unreadCount: number;
    unreadActivities: SpaceMessageActivity[];
}

export interface SpaceMessageConversationList {
    items: SpaceMessageConversation[];
}

export interface SpaceUnreadStatus {
    messagesUnread: boolean;
}

interface SpaceUnreadStatusResponse {
    notificationsUnread: boolean;
}

interface SpaceFriendRequestContext {
    confirmFriendRequest: (
        spaceId: string,
        requestId: bigint,
    ) => Promise<unknown>;
    deleteFriendRequest: (spaceId: string, requestId: bigint) => Promise<void>;
    requestFriendByUsername: (
        spaceId: string,
        username: string,
    ) => Promise<unknown>;
}

interface SpaceConversationsContext {
    listConversations: (spaceId: string) => Promise<SpaceConversationsResponse>;
}

const timestampMsFromSpaceDate = (value: string) => {
    const parsed = Date.parse(value);
    if (!Number.isFinite(parsed)) {
        throw new Error(`Invalid space date: ${value}`);
    }
    return parsed;
};

const spaceFriendsCache = new Map<string, Promise<FriendProfile[]>>();

export const clearSpaceFriendsCache = () => {
    spaceFriendsCache.clear();
};

const cloneFriendProfiles = (friends: FriendProfile[]) =>
    friends.map((friend) => ({ ...friend }));

const placeholderMessageActor = (spaceId: string): FriendProfile => ({
    avatarUrl: null,
    friendsCount: 0,
    fullName: "",
    id: spaceId,
    spaceId,
    username: "",
});

const friendSpaceId = (friend: FriendProfile) => friend.spaceId || friend.id;

const conversationSummaryForFriend = (
    summaries: SpaceConversationChatSummaries | undefined,
    friendSpaceID: string,
) =>
    summaries instanceof Map
        ? summaries.get(friendSpaceID)
        : summaries?.[friendSpaceID];

const messageActorForSpace = (
    spaceId: string,
    actors: SpaceMessageHydrationActors,
) => {
    if (spaceId == friendSpaceId(actors.viewer)) return { ...actors.viewer };
    if (spaceId == friendSpaceId(actors.friend)) return { ...actors.friend };
    return placeholderMessageActor(spaceId);
};

const actorProfile = (actor: SpaceActor): FriendProfile => {
    const payload = parseSpaceProfilePayload(actor.profile ?? "");
    const fullName =
        spaceProfileTextField(payload.fullName) ||
        spaceProfileTextField(payload.displayName) ||
        actor.spaceSlug;
    const username = actor.spaceSlug;

    return {
        avatarKeyVersion: actor.avatar?.keyVersion,
        avatarObjectID: actor.avatar?.objectID,
        avatarSize: actor.avatar?.size,
        avatarUpdatedAt: actor.avatar?.updatedAt,
        avatarUrl: null,
        friendsCount: 0,
        fullName,
        id: actor.spaceId || username,
        username,
        spaceId: actor.spaceId,
        spaceSlug: actor.spaceSlug,
    };
};

const profileFromSpaceProfile = (
    spaceProfile: SpaceProfileResponse,
): FriendProfile => {
    const payload = parseSpaceProfilePayload(spaceProfile.profile);
    const fullName =
        spaceProfileTextField(payload.fullName) ||
        spaceProfileTextField(payload.displayName) ||
        spaceProfile.spaceSlug;

    return {
        avatarKeyVersion: spaceProfile.avatar?.keyVersion,
        avatarObjectID: spaceProfile.avatar?.objectID,
        avatarSize: spaceProfile.avatar?.size,
        avatarUpdatedAt: spaceProfile.avatar?.updatedAt,
        avatarUrl: null,
        coverKeyVersion: spaceProfile.cover?.keyVersion,
        coverObjectID: spaceProfile.cover?.objectID,
        coverUpdatedAt: spaceProfile.cover?.updatedAt,
        coverUrl: null,
        friendsCount: spaceProfile.friends ?? 0,
        fullName,
        id: spaceProfile.spaceId || spaceProfile.spaceSlug,
        username: spaceProfile.spaceSlug,
        spaceId: spaceProfile.spaceId,
        spaceSlug: spaceProfile.spaceSlug,
    };
};

const accountCoverURL = async (
    ctx: SpaceAccountCtxHandle,
    spaceId: string | undefined,
    cover: SpaceCover | undefined,
    viewerSpaceId?: string,
) => {
    if (!spaceId || !cover?.objectID) return null;
    try {
        return await cachedSpaceMediaBlobURL(
            spaceProfileMediaCacheKey(
                spaceId,
                "cover",
                cover.objectID,
                cover.keyVersion,
            ),
            () =>
                ctx.downloadSpaceCover(
                    spaceId,
                    viewerSpaceId ?? null,
                    cover.objectID,
                    cover.keyVersion,
                ),
        );
    } catch (error) {
        console.warn("Failed to load space cover", error);
        return null;
    }
};

const accountAvatarURL = async (
    ctx: SpaceAccountCtxHandle,
    spaceId: string | undefined,
    avatar: SpaceAvatar | undefined,
    viewerSpaceId?: string,
) => {
    if (!spaceId || !avatar?.objectID) return null;
    try {
        return await cachedSpaceMediaBlobURL(
            spaceProfileMediaCacheKey(
                spaceId,
                "avatar",
                avatar.objectID,
                avatar.keyVersion,
            ),
            () =>
                ctx.downloadSpaceAvatar(
                    spaceId,
                    viewerSpaceId ?? null,
                    avatar.objectID,
                    avatar.keyVersion,
                ),
        );
    } catch (error) {
        console.warn("Failed to load space avatar", error);
        return null;
    }
};

const postAssetFrom = (
    post: SpacePostResponse,
    object: SpacePostObject,
): SpacePostAsset => ({
    encryptedPostKey: post.encryptedPostKey,
    keyVersion: post.keyVersion,
    mediaType: object.mediaType,
    objectKey: object.objectKey,
    postId: post.postId,
    spaceId: post.spaceId,
});

const postAssetCacheKey = (asset: SpacePostAsset) =>
    spacePostMediaCacheKey(asset.spaceId, asset.objectKey);

const accountPostAssetURLFromAsset = (
    ctx: SpaceAccountCtxHandle,
    asset: SpacePostAsset,
    viewerSpaceId?: string,
) =>
    cachedSpaceMediaBlobURL(
        postAssetCacheKey(asset),
        () =>
            ctx.downloadPostAssetWithKey(
                asset.spaceId,
                asset.encryptedPostKey,
                asset.keyVersion,
                viewerSpaceId ?? null,
                asset.objectKey,
            ),
        asset.mediaType,
    );

const accountPostAssetURL = (
    ctx: SpaceAccountCtxHandle,
    post: SpacePostResponse,
    object: SpacePostObject,
    viewerSpaceId?: string,
) =>
    accountPostAssetURLFromAsset(
        ctx,
        postAssetFrom(post, object),
        viewerSpaceId,
    );

const cacheAccountPostAssetURL = async (
    post: SpacePostResponse,
    object: SpacePostObject,
    blob: Blob,
) => {
    const key = postAssetCacheKey(postAssetFrom(post, object));
    await rememberCachedSpaceMediaBlobURL(key, blob);
};

const firstObject = (post: { objects?: SpacePostObject[] }) =>
    post.objects?.find((object) => object.objectKey.trim()) ?? null;

const postFromAccountPost = async (
    ctx: SpaceAccountCtxHandle,
    post: SpacePostResponse,
    loadMedia = true,
    viewerSpaceId?: string,
): Promise<SpacePost | null> => {
    const object = firstObject(post);
    if (!object) return null;

    const author = actorProfile(post.author);
    if (loadMedia) {
        author.avatarUrl = await accountAvatarURL(
            ctx,
            post.author.spaceId,
            post.author.avatar,
            viewerSpaceId,
        );
    }

    const imageUrl = loadMedia
        ? await accountPostAssetURL(ctx, post, object, viewerSpaceId)
        : undefined;
    return {
        avatarKeyVersion: author.avatarKeyVersion,
        avatarObjectID: author.avatarObjectID,
        avatarSize: author.avatarSize,
        avatarUpdatedAt: author.avatarUpdatedAt,
        avatarUrl: author.avatarUrl,
        caption: post.caption,
        friendID: author.id,
        height: object.height,
        imageAsset: postAssetFrom(post, object),
        imageUrl,
        name: author.fullName || author.username,
        postId: post.postId,
        timestampMs: timestampMsFromSpaceDate(post.createdAt),
        thumbHash: object.thumbHash,
        viewerLiked: post.viewerLiked,
        spaceId: post.spaceId,
        width: object.width,
    };
};

const profilePostFromPost = (
    post: SpacePostResponse,
): SpaceProfilePost | null => {
    const object = firstObject(post);
    if (!object) return null;

    const author = actorProfile(post.author);
    return {
        avatarKeyVersion: author.avatarKeyVersion,
        avatarObjectID: author.avatarObjectID,
        avatarSize: author.avatarSize,
        avatarUpdatedAt: author.avatarUpdatedAt,
        avatarUrl: null,
        caption: post.caption,
        friendID: author.id,
        height: object.height,
        imageAsset: postAssetFrom(post, object),
        name: author.fullName || author.username,
        postId: post.postId,
        timestampMs: timestampMsFromSpaceDate(post.createdAt),
        thumbHash: object.thumbHash,
        viewerLiked: post.viewerLiked,
        spaceId: post.spaceId,
        width: object.width,
    };
};

const postPageFromAccountPage = async (
    ctx: SpaceAccountCtxHandle,
    page: SpacePostPageResponse,
    loadMedia = true,
    viewerSpaceId?: string,
): Promise<SpacePostPage> => {
    const items = (
        await Promise.all(
            (page.items ?? []).map((post) =>
                postFromAccountPost(ctx, post, loadMedia, viewerSpaceId),
            ),
        )
    ).filter((post): post is SpacePost => Boolean(post));
    return { items, nextCursor: page.nextCursor || undefined };
};

const profilePostPageFromPage = (
    page: SpacePostPageResponse,
): SpaceProfilePostPage => ({
    items: (page.items ?? [])
        .map(profilePostFromPost)
        .filter((post): post is SpaceProfilePost => Boolean(post)),
    nextCursor: page.nextCursor || undefined,
});

const messageQuoteFromPostResponse = async (
    ctx: SpaceAccountCtxHandle,
    post: SpacePostResponse,
    includeImage: boolean,
    viewerSpaceId?: string,
): Promise<SpaceMessageQuote> => {
    const object = firstObject(post);
    const quote: SpaceMessageQuote = {
        postId: post.postId,
        spaceId: post.spaceId,
    };
    if (!includeImage || !object) return quote;

    try {
        const imageUrl = await accountPostAssetURL(
            ctx,
            post,
            object,
            viewerSpaceId,
        );
        if (!imageUrl) {
            quote.isUnavailable = true;
            return quote;
        }
        quote.imageUrl = imageUrl;
    } catch (error) {
        console.warn("Failed to load quoted post image", error);
        quote.isUnavailable = true;
    }
    return quote;
};

const messageQuoteFromReplyPost = async (
    ctx: SpaceAccountCtxHandle,
    message: SpaceMessageResponse,
    includeImage: boolean,
    viewerSpaceId?: string,
): Promise<SpaceMessageQuote | undefined> => {
    if (typeof message.replyPostId != "number" || !message.recipientSpaceId) {
        return undefined;
    }

    const fallbackQuote: SpaceMessageQuote = {
        postId: message.replyPostId,
        spaceId: message.recipientSpaceId,
    };
    if (!includeImage) return fallbackQuote;

    try {
        const post = (await ctx.getPost(
            message.recipientSpaceId,
            BigInt(message.replyPostId),
            viewerSpaceId ?? null,
        )) as SpacePostResponse;
        return await messageQuoteFromPostResponse(
            ctx,
            post,
            includeImage,
            viewerSpaceId,
        );
    } catch (error) {
        console.warn("Failed to load quoted post", error);
        return { ...fallbackQuote, isUnavailable: true };
    }
};

const messageQuoteFromSpaceMessage = async (
    ctx: SpaceAccountCtxHandle,
    message: SpaceMessageResponse,
    includeImage: boolean,
    viewerSpaceId?: string,
): Promise<SpaceMessageQuote | undefined> =>
    messageQuoteFromReplyPost(ctx, message, includeImage, viewerSpaceId);

const messageFromSpaceMessage = async (
    ctx: SpaceAccountCtxHandle,
    message: SpaceMessageResponse,
    includeQuoteImage: boolean,
    viewerSpaceId?: string,
    actors?: SpaceMessageHydrationActors,
): Promise<SpaceMessage> => {
    const sender = actors
        ? messageActorForSpace(message.senderSpaceId, actors)
        : placeholderMessageActor(message.senderSpaceId);
    const recipient = actors
        ? messageActorForSpace(message.recipientSpaceId, actors)
        : placeholderMessageActor(message.recipientSpaceId);
    const quote = await messageQuoteFromSpaceMessage(
        ctx,
        message,
        includeQuoteImage,
        viewerSpaceId,
    );
    return {
        createdAtMs: timestampMsFromSpaceDate(message.createdAt),
        id: message.messageId || message.id || message.createdAt,
        isDeleted: Boolean(message.isDeleted),
        kind: message.kind,
        liked: Boolean(message.liked),
        quote,
        recipient,
        replyMessageId: message.replyMessageId,
        replyPostId: message.replyPostId,
        sender,
        text: message.text,
        updatedAtMs: timestampMsFromSpaceDate(message.updatedAt),
        viewerLiked: Boolean(message.viewerLiked),
    };
};

const messageActivityPostFromActivity = (
    activity: SpaceMessageConversationActivity,
): SpaceMessageActivityPost | undefined => {
    if (typeof activity.postId != "number" || !activity.postSpaceId) {
        return undefined;
    }
    return { postId: activity.postId, spaceId: activity.postSpaceId };
};

export const loadCurrentMessageActivityPostPreview = async (
    post: SpaceMessageActivityPost,
    viewerSpaceId?: string,
): Promise<SpaceMessageActivityPost | undefined> => {
    if (post.isDeleted) return post;
    const loadedPost = await loadCurrentSpacePost(
        post.spaceId,
        post.postId,
        viewerSpaceId,
    );
    if (!loadedPost) return post;
    return { ...post, imageUrl: loadedPost.imageUrl };
};

const messageActivityFromSpaceActivity = (
    activity: SpaceMessageConversationActivity,
): SpaceMessageActivity => {
    const post = messageActivityPostFromActivity(activity);
    return {
        createdAtMs: timestampMsFromSpaceDate(activity.createdAt),
        id: activity.id,
        messageId: activity.messageId,
        outgoing: Boolean(activity.outgoing),
        post,
        text: activity.text?.trim() || undefined,
        type: activity.type,
    };
};

const isPassiveAutoReadMessageActivity = (activity: SpaceMessageActivity) =>
    activity.type == "friend_added" ||
    activity.type == "message_like" ||
    activity.type == "post_like";

const messageConversationUnreadCount = (activities: SpaceMessageActivity[]) => {
    if (activities.length == 1 && activities[0]?.type == "post_like") {
        return 0;
    }

    return activities.filter((activity) => {
        if (activity.type == "friend_added") return false;
        if (activity.type == "message_like") return false;
        return true;
    }).length;
};

export const shouldAutoReadMessageActivities = (
    activities: SpaceMessageActivity[],
) =>
    activities.length > 0 &&
    activities.every(isPassiveAutoReadMessageActivity) &&
    messageConversationUnreadCount(activities) == 0;

export const joinSpaceInvite = async ({
    spaceUsername,
}: PendingSpaceInvite): Promise<"friend" | "requested"> => {
    const profile = await loadExistingSpaceProfile();
    const spaceId = profile?.spaceId;
    if (!spaceId) throw new Error("Missing space.");
    const ctx = await ensureCurrentSpaceContext();
    try {
        const response = (await (
            ctx as SpaceFriendRequestContext
        ).requestFriendByUsername(spaceId, spaceUsername)) as {
            status?: string;
        };
        return response.status == "friend" ? "friend" : "requested";
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const loadPublicSpaceIdentity = async (
    username: string,
): Promise<PublicSpaceIdentity> => {
    const response = await fetch(
        `${await apiOrigin()}/space/public/by-slug/${encodeURIComponent(username)}`,
    );
    if (!response.ok) throw new Error("Public space lookup failed.");

    const identity = (await response.json()) as PublicSpaceIdentityResponse;
    const spaceId = identity.spaceId?.trim();
    const spaceSlug = identity.spaceSlug?.trim();
    if (!spaceId || !spaceSlug) throw new Error("Public space is invalid.");
    return { spaceId, username: spaceSlug };
};

export const loadCurrentSpaceFriends = async (spaceId: string) => {
    const cached = spaceFriendsCache.get(spaceId);
    if (cached) return cloneFriendProfiles(await cached);

    const ctx = await ensureCurrentSpaceContext();
    const promise = (async () => {
        const friends = (await ctx.listSpaceFriends(spaceId)) as SpaceFriend[];
        return friends.map(({ friend }) => actorProfile(friend));
    })();
    spaceFriendsCache.set(spaceId, promise);

    try {
        return cloneFriendProfiles(await promise);
    } catch (error) {
        if (spaceFriendsCache.get(spaceId) == promise) {
            spaceFriendsCache.delete(spaceId);
        }
        throw error;
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const loadCurrentSpaceFriendsCount = async (spaceId: string) => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        const spaceProfile = (await ctx.getSpaceProfile(
            spaceId,
            spaceId,
        )) as SpaceProfileResponse;
        return spaceProfile.friends ?? 0;
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const loadCurrentSpaceProfile = async (
    spaceId: string,
    viewerSpaceId?: string,
): Promise<FriendProfile> => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        const spaceProfile = (await ctx.getSpaceProfile(
            spaceId,
            viewerSpaceId ?? null,
        )) as SpaceProfileResponse;
        const profile = profileFromSpaceProfile(spaceProfile);
        const [avatarUrl, coverUrl] = await Promise.all([
            accountAvatarURL(
                ctx,
                spaceProfile.spaceId,
                spaceProfile.avatar,
                viewerSpaceId,
            ),
            accountCoverURL(
                ctx,
                spaceProfile.spaceId,
                spaceProfile.cover,
                viewerSpaceId,
            ),
        ]);
        profile.avatarUrl = avatarUrl;
        profile.coverUrl = coverUrl;
        return profile;
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const removeCurrentSpaceFriend = async (
    actorSpaceId: string,
    spaceId: string,
) => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        await ctx.removeFriendBySpace(actorSpaceId, spaceId);
        clearSpaceFriendsCache();
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const loadCurrentFeedPage = async (
    spaceId: string,
    cursor?: string,
): Promise<SpacePostPage> => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        return await postPageFromAccountPage(
            ctx,
            (await ctx.listFeed(
                spaceId,
                cursor ?? null,
                currentFeedPageSize,
            )) as SpacePostPageResponse,
            false,
            spaceId,
        );
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const loadCurrentUnreadStatus = async (
    spaceId: string,
): Promise<SpaceUnreadStatus> => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        const status = (await ctx.unreadStatus(
            spaceId,
        )) as SpaceUnreadStatusResponse;
        return { messagesUnread: status.notificationsUnread };
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const loadCurrentSpaceProfilePostsPage = async (
    spaceId: string,
    viewerSpaceId?: string,
    cursor?: string,
): Promise<SpaceProfilePostPage> => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        return profilePostPageFromPage(
            (await ctx.listPosts(
                spaceId,
                viewerSpaceId ?? null,
                cursor ?? null,
                60,
            )) as SpacePostPageResponse,
        );
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const loadCurrentSpacePost = async (
    spaceId: string,
    postId: number,
    viewerSpaceId?: string,
): Promise<SpacePost | null> => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        const response = (await ctx.getPost(
            spaceId,
            BigInt(postId),
            viewerSpaceId ?? null,
        )) as SpacePostResponse | null;
        if (!response) return null;
        const post = await postFromAccountPost(
            ctx,
            response,
            true,
            viewerSpaceId,
        );
        return post?.spaceId == spaceId ? post : null;
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const loadCurrentSpacePostAssetURL: SpacePostAssetURLLoader = async (
    asset,
) => {
    const profile = await loadExistingSpaceProfile();
    const ctx = await ensureCurrentSpaceContext();
    try {
        return await accountPostAssetURLFromAsset(ctx, asset, profile?.spaceId);
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const loadCurrentSpacePostAvatarURL: SpacePostAvatarURLLoader = async (
    post,
) => {
    if (!post.spaceId || !post.avatarObjectID || !post.avatarKeyVersion) {
        return null;
    }

    const profile = await loadExistingSpaceProfile();
    const ctx = await ensureCurrentSpaceContext();
    try {
        return await accountAvatarURL(
            ctx,
            post.spaceId,
            {
                keyVersion: post.avatarKeyVersion,
                objectID: post.avatarObjectID,
                size: post.avatarSize,
                updatedAt: post.avatarUpdatedAt,
            },
            profile?.spaceId,
        );
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const loadCurrentFriendAvatarURL = async (
    friend: FriendProfile,
): Promise<string | null> => {
    if (!friend.spaceId || !friend.avatarObjectID || !friend.avatarKeyVersion) {
        return null;
    }

    const profile = await loadExistingSpaceProfile();
    const ctx = await ensureCurrentSpaceContext();
    try {
        return await accountAvatarURL(
            ctx,
            friend.spaceId,
            {
                keyVersion: friend.avatarKeyVersion,
                objectID: friend.avatarObjectID,
                size: friend.avatarSize,
                updatedAt: friend.avatarUpdatedAt,
            },
            profile?.spaceId,
        );
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const createCurrentPhotoPost = async ({
    caption,
    file,
    height,
    spaceId,
    thumbHash,
    width,
}: {
    caption?: string;
    file: File;
    height?: number;
    spaceId: string;
    thumbHash: string;
    width?: number;
}) => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        const bytes = new Uint8Array(await file.arrayBuffer());
        const normalizedWidth = normalizedImageDimension(width);
        const normalizedHeight = normalizedImageDimension(height);
        const created = (await ctx.createPhotoPost(
            spaceId,
            bytes,
            caption?.trim() || null,
            normalizedWidth,
            normalizedHeight,
            file.type || null,
            thumbHash || null,
        )) as SpacePostResponse;
        const object = firstObject(created);
        if (object) await cacheAccountPostAssetURL(created, object, file);
        return await postFromAccountPost(ctx, created, true, spaceId);
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const isSpacePostLimitReachedError = (error: unknown) => {
    if (!error || typeof error != "object" || !("status" in error)) {
        return false;
    }
    return (error as { status?: unknown }).status == 409;
};

const normalizedImageDimension = (dimension: number | undefined) =>
    typeof dimension == "number" && Number.isFinite(dimension) && dimension > 0
        ? Math.round(dimension)
        : null;

export const setCurrentPostLiked = async (
    spaceId: string,
    postId: number,
    liked: boolean,
) => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        await ctx.likePost(spaceId, BigInt(postId), liked);
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const replyToCurrentPost = async (
    actorSpaceId: string,
    postSpaceId: string,
    postId: number,
    text: string,
) => {
    const messageText = normalizeSpaceMessageText(text);
    const ctx = await ensureCurrentSpaceContext();
    try {
        await ctx.replyToPost(
            actorSpaceId,
            postSpaceId,
            BigInt(postId),
            messageText,
        );
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const sendCurrentMessage = async (
    senderSpaceId: string,
    spaceId: string,
    text: string,
    sender: FriendProfile,
    recipient: FriendProfile,
) => {
    const messageText = normalizeSpaceMessageText(text);
    const ctx = await ensureCurrentSpaceContext();
    try {
        return await messageFromSpaceMessage(
            ctx,
            (await ctx.sendMessage(
                senderSpaceId,
                spaceId,
                messageText,
            )) as SpaceMessageResponse,
            true,
            senderSpaceId,
            { friend: recipient, viewer: sender },
        );
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const replyToCurrentMessage = async (
    senderSpaceId: string,
    spaceId: string,
    messageId: string,
    text: string,
    sender: FriendProfile,
    recipient: FriendProfile,
) => {
    const messageText = normalizeSpaceMessageText(text);
    const ctx = await ensureCurrentSpaceContext();
    try {
        return await messageFromSpaceMessage(
            ctx,
            (await ctx.replyToMessage(
                senderSpaceId,
                spaceId,
                messageId,
                messageText,
            )) as SpaceMessageResponse,
            true,
            senderSpaceId,
            { friend: recipient, viewer: sender },
        );
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const setCurrentMessageLiked = async (
    spaceId: string,
    messageId: string,
    liked: boolean,
) => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        await ctx.likeMessage(spaceId, messageId, liked);
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const deleteCurrentMessage = async (
    spaceId: string,
    messageId: string,
) => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        await ctx.deleteMessage(spaceId, messageId);
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const loadCurrentMessageConversations = async (
    spaceId: string,
): Promise<SpaceMessageConversationList> => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        const response = await (
            ctx as unknown as SpaceConversationsContext
        ).listConversations(spaceId);
        const summaries = response.chatSummaries;
        const friendItems = await Promise.all(
            (response.friends ?? []).map(async (conversation) => {
                const friend = actorProfile(conversation.friend);
                const friendSpaceID = friendSpaceId(friend);
                friend.avatarUrl = await accountAvatarURL(
                    ctx,
                    friendSpaceID,
                    conversation.friend.avatar,
                    spaceId,
                );
                const summary = conversationSummaryForFriend(
                    summaries,
                    friendSpaceID,
                );
                const unreadActivities = summary
                    ? (summary.unreadActivities ?? []).map(
                          messageActivityFromSpaceActivity,
                      )
                    : [];
                const unreadCount =
                    messageConversationUnreadCount(unreadActivities);
                return {
                    friend,
                    latestActivity: summary
                        ? messageActivityFromSpaceActivity(
                              summary.latestActivity,
                          )
                        : {
                              createdAtMs: timestampMsFromSpaceDate(
                                  conversation.createdAt,
                              ),
                              id: `empty:${friendSpaceID}`,
                              outgoing: false,
                              type: "empty" as const,
                          },
                    notificationUnread: unreadActivities.length > 0,
                    unread: unreadCount > 0,
                    unreadActivities,
                    unreadCount,
                };
            }),
        );
        const requestItems = (response.pendingRequests ?? []).map(
            (request) => ({
                friend: actorProfile(request.requester),
                latestActivity: {
                    createdAtMs: timestampMsFromSpaceDate(request.createdAt),
                    id: `friend_request:${request.requestId}`,
                    outgoing: false,
                    type: "friend_request" as const,
                },
                notificationUnread: true,
                unread: true,
                unreadActivities: [],
                unreadCount: 1,
            }),
        );
        return { items: [...requestItems, ...friendItems] };
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const confirmCurrentFriendRequest = async (
    spaceId: string,
    requestId: number,
) => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        await (ctx as SpaceFriendRequestContext).confirmFriendRequest(
            spaceId,
            BigInt(requestId),
        );
        clearSpaceFriendsCache();
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const deleteCurrentFriendRequest = async (
    spaceId: string,
    requestId: number,
) => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        await (ctx as SpaceFriendRequestContext).deleteFriendRequest(
            spaceId,
            BigInt(requestId),
        );
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const loadCurrentMessageThread = async (
    viewerSpaceId: string,
    spaceId: string,
    viewer: FriendProfile,
    friend: FriendProfile,
): Promise<SpaceMessagePage> => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        const page = (await ctx.listMessageThread(
            viewerSpaceId,
            spaceId,
            null,
            100,
        )) as SpaceMessagePageResponse;
        const items = (
            await Promise.all(
                (page.items ?? []).map((message) =>
                    messageFromSpaceMessage(ctx, message, true, viewerSpaceId, {
                        friend,
                        viewer,
                    }),
                ),
            )
        ).reverse();
        return { items, nextCursor: page.nextCursor || undefined };
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const markCurrentMessagesRead = async (
    spaceId: string,
    friendSpaceId: string,
) => {
    if (!friendSpaceId.trim()) return;
    const ctx = await ensureCurrentSpaceContext();
    try {
        await ctx.markNotificationsRead(spaceId, friendSpaceId);
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const deleteCurrentPost = async (spaceId: string, postId: number) => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        await ctx.deletePost(spaceId, BigInt(postId));
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};
