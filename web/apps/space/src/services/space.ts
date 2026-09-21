import type { FriendProfile } from "data/friends";
import { clientPackageName, desktopAppVersion, isDesktop } from "ente-base/app";
import { isNamedError } from "ente-base/error";
import log from "ente-base/log";
import { apiOrigin } from "ente-base/origins";
import {
    openSpaceLinkContext,
    type DecryptedSpaceProfile,
    type MessageConversationActivity,
    type MessageResponse,
    type PostObjectPayload,
    type PostPage,
    type PostResponse,
    type ProfileAvatarResponse,
    type SpaceAccountCtxHandle,
    type SpaceActorResponse,
    type SpaceLinkCtxHandle,
} from "ente-space-wasm";
import {
    invalidateCachedSpaceFeed,
    patchCachedSpaceFeedPost,
    prependCachedSpaceFeedPost,
    removeCachedSpaceFeedPost,
    removeCachedSpaceFeedPostsBySpace,
} from "services/feed-cache";
import type { PendingSpaceInvite } from "services/invite";
import {
    cachedSpaceMediaBlobURL,
    cachedSpaceMediaBlobURLIfPresent,
    clearSpaceMediaCache,
    rememberCachedSpaceMediaBlobURL,
    spacePostMediaCacheKey,
    spaceProfileMediaCacheKey,
} from "services/media-cache";
import {
    ensureCurrentSpaceContext,
    loadExistingSpaceProfile,
    persistCurrentOwnedSpaces,
    releaseCurrentSpaceContext,
} from "services/profile";
import {
    parseSpaceProfilePayload,
    spaceProfileTextField,
} from "services/profile-payload";
import { normalizeSpaceMessageText } from "utils/message-limits";
import { spacePostDeletedEvent } from "utils/post-events";
import { postQuoteErrorState, postQuotePhotoIndex } from "utils/post-quote";

export { clearSpaceMediaURLCache } from "services/media-cache";

type SpaceAvatar = Pick<ProfileAvatarResponse, "objectID" | "keyVersion">;

type SpaceCover = SpaceAvatar;

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
    username?: string;
    viewerLiked: boolean;
    spaceId: string;
    width?: number;
    isUnavailable?: boolean;
}

export interface SpacePostAsset {
    encryptedPostKey: string;
    keyVersion: number;
    mediaType?: string;
    objectKey: string;
    postId: number;
    spaceId: string;
}

export interface SpacePostPhoto {
    height?: number;
    imageAsset?: SpacePostAsset;
    imageUrl?: string;
    thumbHash?: string;
    width?: number;
}

export interface SpacePost extends SpacePostBase, SpacePostPhoto {
    photos?: SpacePostPhoto[];
}

export interface SpacePostPage {
    items: SpacePost[];
    nextCursor?: string;
}

export type SpaceProfilePost = SpacePost;

export interface SpaceProfilePostPage {
    items: SpaceProfilePost[];
    nextCursor?: string;
}

export interface PublicSpaceLinkSession {
    close: () => void;
    loadPostImage: SpacePostAssetURLLoader;
    loadProfileMedia: () => Promise<{
        avatarUrl: string | null;
        coverUrl: string | null;
    }>;
    loadPosts: () => Promise<SpaceProfilePost[]>;
    profile: FriendProfile & { avatarUrl: string | null };
    postsCount: number;
    subscribeWebPush: (
        endpoint: string,
        p256dh: string,
        auth: string,
    ) => Promise<string>;
    unsubscribeWebPush: (endpoint: string) => Promise<void>;
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

export type SpaceMessageKind = MessageResponse["kind"];

export interface SpaceMessageQuote {
    imageUrl?: string;
    isUnavailable?: boolean;
    hasLoadError?: boolean;
    objectKey?: string;
    photoCount?: number;
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
    replyObjectKey?: string;
    sender: FriendProfile;
    text: string;
    updatedAtMs: number;
    viewerLiked: boolean;
    isUnavailable?: boolean;
}

export type SpaceMessageActivityType = MessageConversationActivity["type"];

export type SpaceMessageActivityPost = SpaceMessageQuote;

export interface SpaceMessageActivity {
    createdAtMs: number;
    id: string;
    kind?: SpaceMessageKind;
    messageId?: string;
    outgoing: boolean;
    post?: SpaceMessageActivityPost;
    text?: string;
    type: SpaceMessageActivityType;
    isUnavailable?: boolean;
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
    latestPostCreatedAtMs: number | null;
}

export interface SpaceFriendRequest {
    direction: "received" | "sent";
    friend: FriendProfile;
    requestId: number;
}

export interface SpaceUnreadStatus {
    messagesUnread: boolean;
}

export const isSpaceContentError = (error: unknown) =>
    isNamedError(error, "content_unavailable");

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

const messageActorForSpace = (
    spaceId: string,
    actors: SpaceMessageHydrationActors,
) => {
    if (spaceId == friendSpaceId(actors.viewer)) return { ...actors.viewer };
    if (spaceId == friendSpaceId(actors.friend)) return { ...actors.friend };
    return placeholderMessageActor(spaceId);
};

const actorProfile = (actor: SpaceActorResponse): FriendProfile => {
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
    spaceProfile: DecryptedSpaceProfile,
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
        friendsCount: spaceProfile.friends,
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
        log.warn("Failed to load space cover", error);
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
        log.warn("Failed to load space avatar", error);
        return null;
    }
};

const cachedAccountAvatarURLIfPresent = async (
    spaceId: string | undefined,
    avatar: SpaceAvatar | undefined,
) => {
    if (!spaceId || !avatar?.objectID) return null;
    return (
        (await cachedSpaceMediaBlobURLIfPresent(
            spaceProfileMediaCacheKey(
                spaceId,
                "avatar",
                avatar.objectID,
                avatar.keyVersion,
            ),
        )) ?? null
    );
};

const postAssetFrom = (
    post: PostResponse,
    object: PostObjectPayload,
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
    post: PostResponse,
    object: PostObjectPayload,
    viewerSpaceId?: string,
) =>
    accountPostAssetURLFromAsset(
        ctx,
        postAssetFrom(post, object),
        viewerSpaceId,
    );

const cacheAccountPostAssetURL = async (
    post: PostResponse,
    object: PostObjectPayload,
    blob: Blob,
) => {
    const key = postAssetCacheKey(postAssetFrom(post, object));
    await rememberCachedSpaceMediaBlobURL(key, blob);
};

const firstObject = (post: PostResponse) =>
    post.objects.find((object) => object.objectKey.trim()) ?? null;

const postPhotosFromResponse = (post: PostResponse): SpacePostPhoto[] =>
    post.objects.map((object) => ({
        height: object.height,
        imageAsset: postAssetFrom(post, object),
        thumbHash: object.thumbHash,
        width: object.width,
    }));

const postBaseFromResponse = (
    post: PostResponse,
    author: FriendProfile,
): SpacePostBase => ({
    avatarKeyVersion: author.avatarKeyVersion,
    avatarObjectID: author.avatarObjectID,
    avatarSize: author.avatarSize,
    avatarUpdatedAt: author.avatarUpdatedAt,
    avatarUrl: author.avatarUrl,
    caption: post.caption,
    friendID: author.id,
    isUnavailable: post.isUnavailable,
    name: author.fullName || author.username,
    postId: post.postId,
    spaceId: post.spaceId,
    timestampMs: timestampMsFromSpaceDate(post.createdAt),
    username: author.username,
    viewerLiked: post.viewerLiked,
});

const postFromAccountPost = async (
    ctx: SpaceAccountCtxHandle,
    post: PostResponse,
    loadMedia = true,
    viewerSpaceId?: string,
): Promise<SpacePost> => {
    const object = firstObject(post);
    const author = actorProfile(post.author);
    const base = postBaseFromResponse(post, author);
    if (post.isUnavailable || !object) {
        return { ...base, isUnavailable: true };
    }
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
        ...base,
        avatarUrl: author.avatarUrl,
        height: object.height,
        imageAsset: postAssetFrom(post, object),
        imageUrl,
        photos: postPhotosFromResponse(post),
        thumbHash: object.thumbHash,
        width: object.width,
    };
};

const profilePostFromPost = (post: PostResponse): SpaceProfilePost => {
    const object = firstObject(post);
    const author = actorProfile(post.author);
    const base = postBaseFromResponse(post, author);
    if (post.isUnavailable || !object) {
        return { ...base, avatarUrl: null, isUnavailable: true };
    }
    return {
        ...base,
        avatarUrl: null,
        height: object.height,
        imageAsset: postAssetFrom(post, object),
        photos: postPhotosFromResponse(post),
        thumbHash: object.thumbHash,
        width: object.width,
    };
};

const profilePostPageFromPage = (page: PostPage): SpaceProfilePostPage => ({
    items: page.items.map(profilePostFromPost),
    nextCursor: page.nextCursor || undefined,
});

const publicLinkProfileMediaURL = async (
    ctx: SpaceLinkCtxHandle,
    spaceId: string,
    assetType: "avatar" | "cover",
    asset?: SpaceAvatar,
) => {
    if (!asset?.objectID) return null;
    try {
        return await cachedSpaceMediaBlobURL(
            spaceProfileMediaCacheKey(
                spaceId,
                assetType,
                asset.objectID,
                asset.keyVersion,
            ),
            () =>
                assetType == "avatar"
                    ? ctx.downloadAvatar(asset.objectID, asset.keyVersion)
                    : ctx.downloadCover(asset.objectID, asset.keyVersion),
        );
    } catch (error) {
        log.warn(`Failed to load public Space ${assetType}`, error);
        return null;
    }
};

export const openPublicSpaceLink = async (
    spaceUsername: string,
    accessKey: string,
): Promise<PublicSpaceLinkSession> => {
    const ctx = await openSpaceLinkContext({
        accessKey,
        baseUrl: await apiOrigin(),
        clientPackage: clientPackageName,
        clientVersion: isDesktop ? desktopAppVersion : undefined,
        spaceUsername,
    });
    try {
        const response = ctx.getProfile();
        const profile = profileFromSpaceProfile(response);
        return {
            close: () => ctx.free(),
            loadPostImage: (asset) =>
                cachedSpaceMediaBlobURL(
                    postAssetCacheKey(asset),
                    () =>
                        ctx.downloadPostAsset(
                            asset.encryptedPostKey,
                            asset.keyVersion,
                            asset.objectKey,
                        ),
                    asset.mediaType,
                ),
            loadProfileMedia: async () => {
                const [avatarUrl, coverUrl] = await Promise.all([
                    publicLinkProfileMediaURL(
                        ctx,
                        response.spaceId,
                        "avatar",
                        response.avatar,
                    ),
                    publicLinkProfileMediaURL(
                        ctx,
                        response.spaceId,
                        "cover",
                        response.cover,
                    ),
                ]);
                return { avatarUrl, coverUrl };
            },
            loadPosts: async () =>
                profilePostPageFromPage(await ctx.listPosts()).items,
            profile: { ...profile, avatarUrl: profile.avatarUrl ?? null },
            postsCount: response.posts ?? 0,
            subscribeWebPush: (endpoint, p256dh, auth) =>
                ctx.subscribeWebPush(endpoint, p256dh, auth),
            unsubscribeWebPush: (endpoint) => ctx.unsubscribeWebPush(endpoint),
        };
    } catch (error) {
        ctx.free();
        throw error;
    }
};

const withCurrentSpaceContext = async <T>(
    run: (ctx: SpaceAccountCtxHandle, spaceId: string) => Promise<T>,
) => {
    const profile = await loadExistingSpaceProfile();
    if (!profile?.spaceId) throw new Error("Space profile is unavailable.");
    const ctx = await ensureCurrentSpaceContext();
    try {
        return await run(ctx, profile.spaceId);
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

const messageQuoteFromPostResponse = async (
    ctx: SpaceAccountCtxHandle,
    post: PostResponse,
    includeImage: boolean,
    viewerSpaceId?: string,
    objectKey?: string,
): Promise<SpaceMessageQuote> => {
    const photoIndex = postQuotePhotoIndex(post.objects, objectKey);
    const object = post.objects[photoIndex];
    const quote: SpaceMessageQuote = {
        objectKey,
        photoCount: post.objects.length,
        postId: post.postId,
        spaceId: post.spaceId,
    };
    if (!object || post.isUnavailable) return { ...quote, isUnavailable: true };
    if (!includeImage) return quote;

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
        log.warn("Failed to load quoted post image", error);
        Object.assign(quote, postQuoteErrorState(error));
    }
    return quote;
};

const messageQuoteFromReplyPost = async (
    ctx: SpaceAccountCtxHandle,
    message: MessageResponse,
    includeImage: boolean,
    viewerSpaceId?: string,
): Promise<SpaceMessageQuote | undefined> => {
    if (typeof message.replyPostId != "number" || !message.recipientSpaceId) {
        return undefined;
    }

    const fallbackQuote: SpaceMessageQuote = {
        objectKey: message.replyObjectKey,
        postId: message.replyPostId,
        spaceId: message.recipientSpaceId,
    };
    if (!includeImage) return fallbackQuote;

    try {
        const post = await ctx.getPost(
            message.recipientSpaceId,
            BigInt(message.replyPostId),
            viewerSpaceId ?? null,
        );
        return await messageQuoteFromPostResponse(
            ctx,
            post,
            includeImage,
            viewerSpaceId,
            message.replyObjectKey,
        );
    } catch (error) {
        log.warn("Failed to load quoted post", error);
        return { ...fallbackQuote, ...postQuoteErrorState(error) };
    }
};

const messageQuoteFromSpaceMessage = async (
    ctx: SpaceAccountCtxHandle,
    message: MessageResponse,
    includeImage: boolean,
    viewerSpaceId?: string,
): Promise<SpaceMessageQuote | undefined> =>
    messageQuoteFromReplyPost(ctx, message, includeImage, viewerSpaceId);

const messageFromSpaceMessage = async (
    ctx: SpaceAccountCtxHandle,
    message: MessageResponse,
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
    const quote = message.isUnavailable
        ? undefined
        : await messageQuoteFromSpaceMessage(
              ctx,
              message,
              includeQuoteImage,
              viewerSpaceId,
          );
    return {
        createdAtMs: timestampMsFromSpaceDate(message.createdAt),
        id: message.messageId || message.createdAt,
        isDeleted: message.isDeleted,
        isUnavailable: message.isUnavailable,
        kind: message.kind,
        liked: message.liked,
        quote,
        recipient,
        replyMessageId: message.replyMessageId,
        replyPostId: message.replyPostId,
        replyObjectKey: message.replyObjectKey,
        sender,
        text: message.text,
        updatedAtMs: timestampMsFromSpaceDate(message.updatedAt),
        viewerLiked: message.viewerLiked,
    };
};

const messageActivityPostFromActivity = (
    activity: MessageConversationActivity,
): SpaceMessageActivityPost | undefined => {
    if (typeof activity.postId != "number" || !activity.postSpaceId) {
        return undefined;
    }
    return {
        postId: activity.postId,
        spaceId: activity.postSpaceId,
        objectKey: activity.replyObjectKey,
    };
};

export const loadCurrentMessageActivityPostPreview = async (
    post: SpaceMessageActivityPost,
    viewerSpaceId?: string,
): Promise<SpaceMessageActivityPost | undefined> => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        const response = await ctx.getPost(
            post.spaceId,
            BigInt(post.postId),
            viewerSpaceId ?? null,
        );
        return await messageQuoteFromPostResponse(
            ctx,
            response,
            true,
            viewerSpaceId,
            post.objectKey,
        );
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

const messageActivityFromSpaceActivity = (
    activity: MessageConversationActivity,
): SpaceMessageActivity => {
    const post = messageActivityPostFromActivity(activity);
    return {
        createdAtMs: timestampMsFromSpaceDate(activity.createdAt),
        id: activity.id,
        kind: activity.kind || undefined,
        messageId: activity.messageId,
        outgoing: activity.outgoing,
        post,
        text: activity.text?.trim() || undefined,
        type: activity.type,
        isUnavailable: activity.isUnavailable,
    };
};

const isPokeMessageActivity = (activity: SpaceMessageActivity) =>
    activity.kind == "poke";

const isPassiveAutoReadMessageActivity = (activity: SpaceMessageActivity) =>
    activity.type == "friend_added" ||
    activity.type == "message_like" ||
    activity.type == "post_like" ||
    isPokeMessageActivity(activity);

const messageConversationUnreadCount = (activities: SpaceMessageActivity[]) => {
    const onlyActivity = activities.length == 1 ? activities[0] : undefined;
    if (
        onlyActivity?.type == "post_like" ||
        (onlyActivity && isPokeMessageActivity(onlyActivity))
    ) {
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

export const requestFriendByUsername = async ({
    spaceUsername,
}: PendingSpaceInvite): Promise<"friend" | "requested"> => {
    const profile = await loadExistingSpaceProfile();
    const spaceId = profile?.spaceId;
    if (!spaceId) throw new Error("Missing space.");
    const ctx = await ensureCurrentSpaceContext();
    try {
        const response = await ctx.requestFriendByUsername(
            spaceId,
            spaceUsername,
        );
        return response.status == "friend" ? "friend" : "requested";
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const loadCurrentSpaceRelationship = (targetSpaceId: string) =>
    withCurrentSpaceContext(async (ctx, spaceId) => {
        const response = await ctx.getRelationship(spaceId, targetSpaceId);
        return response.relationship == "self"
            ? "self"
            : response.relationship == "friend"
              ? "friend"
              : null;
    });

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
        const friends = await ctx.listSpaceFriends(spaceId);
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
        const spaceProfile = await ctx.getSpaceProfile(spaceId, spaceId);
        return spaceProfile.friends;
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const loadCurrentFriendRequests = async (
    spaceId: string,
): Promise<SpaceFriendRequest[]> => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        const [receivedRequests, sentRequests] = await Promise.all([
            ctx.listFriendRequests(spaceId),
            ctx.listSentFriendRequests(spaceId),
        ]);
        return [
            ...receivedRequests.map((request) => ({
                direction: "received" as const,
                friend: actorProfile(request.requester),
                requestId: request.requestId,
            })),
            ...sentRequests.map((request) => ({
                direction: "sent" as const,
                friend: actorProfile(request.target),
                requestId: request.requestId,
            })),
        ];
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
        const spaceProfile = await ctx.getSpaceProfile(
            spaceId,
            viewerSpaceId ?? null,
        );
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
        await removeCachedSpaceFeedPostsBySpace(actorSpaceId, spaceId);
        await clearSpaceMediaCache();
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
        const page = await ctx.listFeed(spaceId, cursor ?? null, 10);
        await persistCurrentOwnedSpaces(ctx);
        return {
            items: await Promise.all(
                page.items.map((post) =>
                    postFromAccountPost(ctx, post, false, spaceId),
                ),
            ),
            nextCursor: page.nextCursor || undefined,
        };
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const loadCurrentUnreadStatus = async (
    spaceId: string,
): Promise<SpaceUnreadStatus> => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        const status = await ctx.unreadStatus(spaceId);
        return { messagesUnread: status.notificationsUnread };
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const hasCurrentSpacePosts = async (
    spaceId: string,
): Promise<boolean> => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        const page = await ctx.listPosts(spaceId, spaceId, null, 1);
        return page.items.length > 0;
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
        const page = profilePostPageFromPage(
            await ctx.listPosts(
                spaceId,
                viewerSpaceId ?? null,
                cursor ?? null,
                250,
            ),
        );
        return page;
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
        const response = await ctx.getPost(
            spaceId,
            BigInt(postId),
            viewerSpaceId ?? null,
        );
        const post = await postFromAccountPost(
            ctx,
            response,
            true,
            viewerSpaceId,
        );
        return !post.isUnavailable && post.spaceId == spaceId ? post : null;
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const loadCurrentSpacePostAssetURL: SpacePostAssetURLLoader = async (
    asset,
) => {
    const cachedURL = await cachedSpaceMediaBlobURLIfPresent(
        postAssetCacheKey(asset),
    );
    if (cachedURL) return cachedURL;

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

    const avatar = {
        keyVersion: post.avatarKeyVersion,
        objectID: post.avatarObjectID,
    };
    const cachedAvatarURL = await cachedAccountAvatarURLIfPresent(
        post.spaceId,
        avatar,
    );
    if (cachedAvatarURL) return cachedAvatarURL;
    const profile = await loadExistingSpaceProfile();
    const ctx = await ensureCurrentSpaceContext();
    try {
        return await accountAvatarURL(
            ctx,
            post.spaceId,
            avatar,
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

    const avatar = {
        keyVersion: friend.avatarKeyVersion,
        objectID: friend.avatarObjectID,
    };
    const cachedAvatarURL = await cachedAccountAvatarURLIfPresent(
        friend.spaceId,
        avatar,
    );
    if (cachedAvatarURL) return cachedAvatarURL;

    const profile = await loadExistingSpaceProfile();
    const ctx = await ensureCurrentSpaceContext();
    try {
        return await accountAvatarURL(
            ctx,
            friend.spaceId,
            avatar,
            profile?.spaceId,
        );
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const createCurrentPhotoPost = async ({
    caption,
    images,
    spaceId,
}: {
    caption?: string;
    images: { file: File; height: number; width: number; thumbHash: string }[];
    spaceId: string;
}) => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        const photos = await Promise.all(
            images.map(async (image) => ({
                bytes: new Uint8Array(await image.file.arrayBuffer()),
                options: {
                    width: normalizedImageDimension(image.width),
                    height: normalizedImageDimension(image.height),
                    mediaType: image.file.type || undefined,
                    thumbHash: image.thumbHash || undefined,
                },
            })),
        );
        const created = await ctx.createPhotoPost(
            spaceId,
            photos,
            caption?.trim() || null,
        );
        await Promise.all(
            created.objects.map((object, index) =>
                cacheAccountPostAssetURL(created, object, images[index]!.file),
            ),
        );
        const post = await postFromAccountPost(ctx, created, true, spaceId);
        await prependCachedSpaceFeedPost(spaceId, post);
        return post;
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

const normalizedImageDimension = (dimension: number | undefined) =>
    typeof dimension == "number" && Number.isFinite(dimension) && dimension > 0
        ? Math.round(dimension)
        : undefined;

export const setCurrentPostLiked = async (
    spaceId: string,
    postId: number,
    liked: boolean,
) => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        await ctx.likePost(spaceId, BigInt(postId), liked);
        await patchCachedSpaceFeedPost(spaceId, postId, { viewerLiked: liked });
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const replyToCurrentPost = async (
    actorSpaceId: string,
    postSpaceId: string,
    postId: number,
    text: string,
    objectKey: string,
) => {
    const messageText = normalizeSpaceMessageText(text);
    const ctx = await ensureCurrentSpaceContext();
    try {
        await ctx.replyToPost(
            actorSpaceId,
            postSpaceId,
            BigInt(postId),
            messageText,
            objectKey,
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
            await ctx.sendMessage(senderSpaceId, spaceId, messageText),
            true,
            senderSpaceId,
            { friend: recipient, viewer: sender },
        );
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const sendCurrentPoke = async (
    senderSpaceId: string,
    spaceId: string,
    sender: FriendProfile,
    recipient: FriendProfile,
) => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        return await messageFromSpaceMessage(
            ctx,
            await ctx.sendPoke(senderSpaceId, spaceId),
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
            await ctx.replyToMessage(
                senderSpaceId,
                spaceId,
                messageId,
                messageText,
            ),
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
        const response = await ctx.listConversations(spaceId);
        const summaries = response.chatSummaries;
        const friendItems = await Promise.all(
            response.friends.map(async (conversation) => {
                const friend = actorProfile(conversation.friend);
                const friendSpaceID = friendSpaceId(friend);
                friend.avatarUrl = await cachedAccountAvatarURLIfPresent(
                    friendSpaceID,
                    conversation.friend.avatar,
                );
                const summary = summaries.get(friendSpaceID);
                const latestActivity = summary
                    ? messageActivityFromSpaceActivity(summary.latestActivity)
                    : undefined;
                const unreadActivities = summary
                    ? summary.unreadActivities
                          .map(messageActivityFromSpaceActivity)
                          .map((activity) =>
                              activity.id == latestActivity?.id &&
                              isPokeMessageActivity(latestActivity)
                                  ? { ...activity, kind: "poke" as const }
                                  : activity,
                          )
                    : [];
                const unreadCount =
                    messageConversationUnreadCount(unreadActivities);
                return {
                    friend,
                    latestActivity: latestActivity
                        ? latestActivity
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
        const requestItems = response.pendingRequests.map((request) => ({
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
        }));
        return {
            items: [...requestItems, ...friendItems],
            latestPostCreatedAtMs: response.latestPostCreatedAt
                ? timestampMsFromSpaceDate(response.latestPostCreatedAt)
                : null,
        };
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const loadCurrentMessageConversationAvatar = async (
    viewerSpaceId: string,
    friend: FriendProfile,
) => {
    if (
        friend.avatarUrl ||
        !friend.avatarObjectID ||
        !friend.avatarKeyVersion
    ) {
        return friend.avatarUrl ?? null;
    }

    const ctx = await ensureCurrentSpaceContext();
    try {
        return await accountAvatarURL(
            ctx,
            friendSpaceId(friend),
            {
                keyVersion: friend.avatarKeyVersion,
                objectID: friend.avatarObjectID,
            },
            viewerSpaceId,
        );
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
        await ctx.confirmFriendRequest(spaceId, BigInt(requestId));
        clearSpaceFriendsCache();
        await invalidateCachedSpaceFeed(spaceId);
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
        await ctx.deleteFriendRequest(spaceId, BigInt(requestId));
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
        const page = await ctx.listMessageThread(
            viewerSpaceId,
            spaceId,
            null,
            100,
        );
        const items = (
            await Promise.all(
                page.items.map((message) =>
                    messageFromSpaceMessage(
                        ctx,
                        message,
                        false,
                        viewerSpaceId,
                        { friend, viewer },
                    ),
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
        window.dispatchEvent(new Event(spacePostDeletedEvent));
        await removeCachedSpaceFeedPost(spaceId, postId);
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const updateCurrentPostCaption = async (
    spaceId: string,
    postId: number,
    caption: string,
) => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        await ctx.updatePostCaption(
            spaceId,
            BigInt(postId),
            caption.trim() || null,
        );
        await patchCachedSpaceFeedPost(spaceId, postId, {
            caption: caption.trim() || undefined,
        });
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};
