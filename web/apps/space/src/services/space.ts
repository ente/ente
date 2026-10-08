import type { FriendProfile } from "data/friends";
import { clientPackageName, desktopAppVersion, isDesktop } from "ente-base/app";
import { isNamedError } from "ente-base/error";
import log from "ente-base/log";
import { logToDisk } from "ente-base/log-web";
import { apiOrigin } from "ente-base/origins";
import type { UploadedPostAsset } from "ente-space-wasm";
import {
    openSpaceLinkContext,
    type DecryptedSpaceProfile,
    type MessageConversationActivity,
    type MessageResponse,
    type PostAsset,
    type PostPage,
    type PostPhoto,
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
    rememberCachedSpaceVideoBlob,
    spacePostMediaCacheKey,
    spaceProfileMediaCacheKey,
} from "services/media-cache";
import { loadSpaceMedia } from "services/media-load";
import {
    ensureCurrentSpaceContext,
    loadExistingSpaceProfile,
    persistCurrentOwnedSpaces,
    releaseCurrentSpaceContext,
} from "services/profile";
import { normalizeSpaceMessageText } from "utils/message-limits";
import { spaceUnreadStatusChangedEvent } from "utils/navigation";
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

export type SpacePostAsset = PostAsset & { mediaType?: string };

export interface SpacePostVideo {
    asset?: SpacePostAsset;
    url?: string;
    durationMs: number;
    start?: number;
    end?: number;
    muted?: boolean;
}

export interface SpacePostPhoto {
    video?: SpacePostVideo;
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

type SpaceMessageKind = MessageResponse["kind"];

export interface SpacePostPreview {
    durationMs?: number;
    imageUrl?: string;
    isUnavailable?: boolean;
    hasLoadError?: boolean;
    retryAt?: number;
    objectKey?: string;
    photoCount?: number;
    postId: number;
    spaceId: string;
}

export type SpaceMessageQuote = SpacePostPreview;

export interface SpaceMessage {
    createdAtMs: number;
    id: string;
    isDeleted: boolean;
    kind: SpaceMessageKind;
    liked: boolean;
    reaction?: string;
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

type SpaceMessageActivityType = MessageConversationActivity["type"];

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
    reaction?: string;
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
    notificationsUnread: boolean;
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
    const payload = actor.profile;
    const fullName =
        payload?.fullName || payload?.displayName || actor.spaceSlug;
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
    const payload = spaceProfile.profile;
    const fullName =
        payload?.fullName || payload?.displayName || spaceProfile.spaceSlug;

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

const postAssetFrom = (photo: PostPhoto): SpacePostAsset => ({
    ...photo.asset,
    mediaType: photo.mediaType,
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
        () => ctx.downloadPostAsset(asset, viewerSpaceId ?? null),
        asset.mediaType,
    );

const accountPostAssetURL = (
    ctx: SpaceAccountCtxHandle,
    photo: PostPhoto,
    viewerSpaceId?: string,
) => accountPostAssetURLFromAsset(ctx, postAssetFrom(photo), viewerSpaceId);

const cacheAccountPostAssetURL = async (photo: PostPhoto, blob: Blob) => {
    const key = postAssetCacheKey(postAssetFrom(photo));
    return rememberCachedSpaceMediaBlobURL(key, blob);
};

const postVideoFrom = (photo: PostPhoto): SpacePostVideo | undefined =>
    photo.video
        ? {
              asset: { ...photo.video.asset, mediaType: "video/mp4" },
              durationMs: photo.video.durationMs,
          }
        : undefined;

const postPhotosFromResponse = (post: PostResponse): SpacePostPhoto[] =>
    post.photos.map((photo) => ({
        video: postVideoFrom(photo),
        height: photo.height,
        imageAsset: postAssetFrom(photo),
        thumbHash: photo.thumbHash,
        width: photo.width,
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
    const author = actorProfile(post.author);
    const base = postBaseFromResponse(post, author);
    if (post.isUnavailable) {
        return { ...base, isUnavailable: true };
    }
    const photo = post.photos[0]!;
    if (loadMedia) {
        author.avatarUrl = await accountAvatarURL(
            ctx,
            post.author.spaceId,
            post.author.avatar,
            viewerSpaceId,
        );
    }

    const imageUrl = loadMedia
        ? await accountPostAssetURL(ctx, photo, viewerSpaceId)
        : undefined;
    return {
        ...base,
        avatarUrl: author.avatarUrl,
        video: postVideoFrom(photo),
        height: photo.height,
        imageAsset: postAssetFrom(photo),
        imageUrl,
        photos: postPhotosFromResponse(post),
        thumbHash: photo.thumbHash,
        width: photo.width,
    };
};

const profilePostFromPost = (post: PostResponse): SpaceProfilePost => {
    const author = actorProfile(post.author);
    const base = postBaseFromResponse(post, author);
    if (post.isUnavailable) {
        return { ...base, avatarUrl: null, isUnavailable: true };
    }
    const photo = post.photos[0]!;
    return {
        ...base,
        avatarUrl: null,
        video: postVideoFrom(photo),
        height: photo.height,
        imageAsset: postAssetFrom(photo),
        photos: postPhotosFromResponse(post),
        thumbHash: photo.thumbHash,
        width: photo.width,
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
                    () => ctx.downloadPostAsset(asset),
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
    const photoIndex = postQuotePhotoIndex(
        post.photos.map((photo) => photo.asset),
        objectKey,
    );
    const photo = post.photos[photoIndex];
    const quote: SpaceMessageQuote = {
        durationMs: photo?.video?.durationMs,
        objectKey,
        photoCount: post.photos.length,
        postId: post.postId,
        spaceId: post.spaceId,
    };
    if (!photo || post.isUnavailable) return { ...quote, isUnavailable: true };
    if (!includeImage) return quote;

    try {
        const imageUrl = await accountPostAssetURL(ctx, photo, viewerSpaceId);
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
        const post = await loadSpaceMedia(() =>
            ctx.getPost(
                fallbackQuote.spaceId,
                BigInt(fallbackQuote.postId),
                viewerSpaceId ?? null,
            ),
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
        reaction: message.reaction ?? undefined,
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

export const loadCurrentPostPreview = async (
    post: SpacePostPreview,
    viewerSpaceId?: string,
): Promise<SpacePostPreview | undefined> => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        const response = await loadSpaceMedia(() =>
            ctx.getPost(
                post.spaceId,
                BigInt(post.postId),
                viewerSpaceId ?? null,
            ),
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
        reaction: activity.reaction ?? undefined,
        isUnavailable: activity.isUnavailable,
    };
};

const isPokeMessageActivity = (activity: SpaceMessageActivity) =>
    activity.kind == "poke";

const isPassiveAutoReadMessageActivity = (activity: SpaceMessageActivity) =>
    activity.type == "message_like" || isPokeMessageActivity(activity);

const messageConversationUnreadCount = (activities: SpaceMessageActivity[]) => {
    const onlyActivity = activities.length == 1 ? activities[0] : undefined;
    if (onlyActivity && isPokeMessageActivity(onlyActivity)) {
        return 0;
    }

    return activities.filter((activity) => {
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
        const page = await ctx.listFeed(
            spaceId,
            cursor ?? null,
            cursor ? 10 : 20,
        );
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
        const [status, notificationsUnread] = await Promise.all([
            ctx.unreadStatus(spaceId),
            ctx.notificationsUnread(spaceId),
        ]);
        return {
            messagesUnread: status.notificationsUnread,
            notificationsUnread,
        };
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export interface SpaceNotification {
    id: string;
    kind: string;
    actors: FriendProfile[];
    actorCount: number;
    postId?: number;
    friendRequestId?: number;
    createdAtMs: number;
    read: boolean;
}

export const loadCurrentNotifications = async (
    spaceId: string,
    cursor?: string,
) => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        const page = await ctx.listNotifications(spaceId, cursor, 20);
        return {
            items: await Promise.all(
                page.items.map(async (item): Promise<SpaceNotification> => {
                    const actors = await Promise.all(
                        item.actors.map(async (itemActor) => {
                            const actor = actorProfile(itemActor);
                            actor.avatarUrl =
                                await cachedAccountAvatarURLIfPresent(
                                    actor.spaceId,
                                    itemActor.avatar,
                                );
                            return actor;
                        }),
                    );
                    return {
                        id: item.notificationId,
                        kind: item.kind,
                        actors,
                        actorCount: item.actorCount,
                        postId: item.postId ?? undefined,
                        friendRequestId: item.friendRequestId ?? undefined,
                        createdAtMs: timestampMsFromSpaceDate(item.createdAt),
                        read: !item.unread,
                    };
                }),
            ),
            nextCursor: page.nextCursor || undefined,
            latestPostCreatedAtMs: page.latestPostCreatedAt
                ? timestampMsFromSpaceDate(page.latestPostCreatedAt)
                : null,
        };
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const markCurrentNotificationItemsRead = async (
    spaceId: string,
    ids: string[],
) => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        await ctx.markNotificationItemsRead(spaceId, ids);
        window.dispatchEvent(new Event(spaceUnreadStatusChangedEvent));
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
        asset.mediaType,
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
    viewerSpaceId?: string,
): Promise<string | null> => {
    if (friend.avatarUrl) return friend.avatarUrl;
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

    const actorSpaceId =
        viewerSpaceId ?? (await loadExistingSpaceProfile())?.spaceId;
    const ctx = await ensureCurrentSpaceContext();
    try {
        return await accountAvatarURL(
            ctx,
            friend.spaceId,
            avatar,
            actorSpaceId,
        );
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export interface PreparedSpacePostMedia {
    file: File;
    height: number;
    width: number;
    thumbHash: string;
    video?: { file: File; durationMs: number };
}

export interface SpacePostUploadSession {
    requestId?: string;
    key?: Uint8Array;
    postId?: number;
    uploads: {
        preview?: UploadedPostAsset;
        video?: UploadedPostAsset;
        expiresAt: number;
    }[];
}

export const createCurrentMediaPost = async ({
    images,
    caption,
    spaceId,
    session,
    signal,
}: {
    images: PreparedSpacePostMedia[];
    caption: string;
    spaceId: string;
    session: SpacePostUploadSession;
    signal?: AbortSignal;
}) => {
    const ctx = await ensureCurrentSpaceContext();
    let stage = "prepare";
    let itemIndex: number | undefined;
    let bytes: number | undefined;
    try {
        if (!session.postId) {
            session.key ??= ctx.generatePostKey();
            session.requestId ??= crypto.randomUUID();
            for (const [index, image] of images.entries()) {
                itemIndex = index + 1;
                signal?.throwIfAborted();
                let upload = session.uploads[index];
                if (!upload || upload.expiresAt < Date.now()) {
                    upload = { expiresAt: Date.now() + 25 * 60 * 1000 };
                    session.uploads[index] = upload;
                }
                stage = "upload-preview";
                bytes = image.file.size;
                upload.preview ??= await ctx.uploadPostPhotoAsset(
                    spaceId,
                    session.key,
                    new Uint8Array(await image.file.arrayBuffer()),
                    {
                        width: image.width,
                        height: image.height,
                        mediaType: image.file.type,
                        thumbHash: image.thumbHash,
                    },
                    signal,
                );
                signal?.throwIfAborted();
                if (image.video) {
                    stage = "upload-video";
                    bytes = image.video.file.size;
                    upload.video ??= await ctx.uploadPostVideoAsset(
                        spaceId,
                        session.key,
                        new Uint8Array(await image.video.file.arrayBuffer()),
                        {
                            width: image.width,
                            height: image.height,
                            durationMs: image.video.durationMs,
                        },
                        signal,
                    );
                }
            }
            signal?.throwIfAborted();
            stage = "create-post";
            itemIndex = undefined;
            bytes = undefined;
            session.postId = Number(
                await ctx.createMediaPost(
                    spaceId,
                    session.key,
                    session.uploads.map((upload) => ({
                        preview: upload.preview!,
                        video: upload.video,
                    })),
                    session.requestId,
                    caption.trim() || undefined,
                ),
            );
        }
        return session.postId;
    } catch (error) {
        const uploadError = error as
            | (Error & { status?: number; code?: string })
            | undefined;
        logToDisk(
            `[error] Space post upload failed ${JSON.stringify({ requestId: session.requestId, stage, itemIndex, itemCount: images.length, bytes, status: uploadError?.status, code: uploadError?.code, name: uploadError?.name, message: uploadError?.message, stack: uploadError?.stack })}`.replaceAll(
                spaceId,
                "[space-id]",
            ),
        );
        throw error;
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const loadCurrentCreatedPost = async (
    spaceId: string,
    postId: number,
    media: PreparedSpacePostMedia[],
) => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        const created = await ctx.getPost(spaceId, BigInt(postId), spaceId);
        const imageURLs = await Promise.all(
            created.photos.map(async (photo, index) => {
                const prepared = media[index]!;
                if (photo.video && prepared.video)
                    await rememberCachedSpaceVideoBlob(
                        postAssetCacheKey(photo.video.asset),
                        prepared.video.file,
                    );
                return cacheAccountPostAssetURL(photo, prepared.file);
            }),
        );
        const post = await postFromAccountPost(ctx, created, false, spaceId);
        post.imageUrl = imageURLs[0];
        post.photos?.forEach((photo, index) => {
            photo.imageUrl = imageURLs[index];
        });
        await prependCachedSpaceFeedPost(spaceId, post);
        return post;
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

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
    requestId: string,
) => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        await ctx.sendPoke(senderSpaceId, spaceId, requestId);
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

export const setCurrentMessageReaction = async (
    spaceId: string,
    senderSpaceId: string,
    messageId: string,
    emoji: string | undefined,
) => {
    const ctx = await ensureCurrentSpaceContext();
    try {
        await ctx.setMessageReaction(
            spaceId,
            senderSpaceId,
            messageId,
            emoji ?? null,
        );
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
                    ? summary.unreadActivities.map(
                          messageActivityFromSpaceActivity,
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
        return {
            items: friendItems,
            latestPostCreatedAtMs: response.latestPostCreatedAt
                ? timestampMsFromSpaceDate(response.latestPostCreatedAt)
                : null,
        };
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
        window.dispatchEvent(new Event(spaceUnreadStatusChangedEvent));
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
