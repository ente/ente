import type { FriendProfile } from "data/friends";
import { savedPartialLocalUser } from "ente-accounts/services/accounts-db";
import { getKV, removeKV, setKV } from "ente-base/kv";
import log from "ente-base/log";
import { apiOrigin } from "ente-base/origins";
import { CachedSpacePost } from "services/post-cache";
import { loadCurrentHomePostsPage, type SpacePost } from "services/space";
import { z } from "zod";

const homePostsVersion = 1;

const PostMarker = z.object({
    postId: z.number().int().positive(),
    timestampMs: z.number().nonnegative(),
});

const SpaceHomePostsStateSchema = z.object({
    friendSpaceIds: z.string().array(),
    latestPosts: CachedSpacePost.array(),
    readAheadPosts: PostMarker.array(),
    syncCursor: z.string(),
    unreadPosts: CachedSpacePost.array(),
    version: z.literal(homePostsVersion),
    viewerSpaceId: z.string(),
});

export interface SpaceHomePostsState {
    friendSpaceIds: string[];
    latestPosts: SpacePost[];
    readAheadPosts: SpacePostMarker[];
    syncCursor: string;
    unreadPosts: SpacePost[];
    version: typeof homePostsVersion;
    viewerSpaceId: string;
}

interface SpacePostMarker {
    postId: number;
    timestampMs: number;
}

const memoryCache = new Map<string, SpaceHomePostsState | undefined>();
const cacheOperations = new Map<string, Promise<void>>();
let cacheGeneration = 0;

const storageScope = async (viewerSpaceId: string) => {
    const userID = savedPartialLocalUser()?.id;
    if (!userID) return undefined;
    return { origin: await apiOrigin(), userID, viewerSpaceId };
};

const homePostsKey = async (viewerSpaceId: string) => {
    const scope = await storageScope(viewerSpaceId);
    return scope
        ? [
              "space-home-posts",
              `v${homePostsVersion}`,
              scope.origin,
              scope.userID,
              viewerSpaceId,
          ].join(":")
        : undefined;
};

const clonePost = (post: SpacePost): SpacePost => ({
    ...post,
    imageAsset: post.imageAsset ? { ...post.imageAsset } : undefined,
});

const cacheablePost = (post: SpacePost) => {
    const cached = clonePost(post);
    delete cached.avatarUrl;
    delete cached.imageUrl;
    return cached;
};

const cloneState = (state: SpaceHomePostsState): SpaceHomePostsState => ({
    ...state,
    friendSpaceIds: [...state.friendSpaceIds],
    latestPosts: state.latestPosts.map(clonePost),
    readAheadPosts: state.readAheadPosts.map((post) => ({ ...post })),
    unreadPosts: state.unreadPosts.map(clonePost),
});

const descendingPostOrder = (a: SpacePostMarker, b: SpacePostMarker) =>
    b.timestampMs - a.timestampMs || b.postId - a.postId;

const isAfter = (post: SpacePostMarker, marker: SpacePostMarker) =>
    post.timestampMs > marker.timestampMs ||
    (post.timestampMs == marker.timestampMs && post.postId > marker.postId);

const markerFor = (post: SpacePostMarker): SpacePostMarker => ({
    postId: post.postId,
    timestampMs: post.timestampMs,
});

const markerFromCursor = (cursor: string): SpacePostMarker | undefined => {
    const parts = cursor.split(":", 2);
    const createdAt = Number(parts[0]);
    const postId = Number(parts[1]);
    if (
        !Number.isSafeInteger(createdAt) ||
        createdAt <= 0 ||
        !Number.isSafeInteger(postId) ||
        postId < 0
    ) {
        return undefined;
    }
    return { postId, timestampMs: Math.floor(createdAt / 1000) };
};

const compareCursors = (a: string, b: string) => {
    const [aCreatedAt, aPostID] = a.split(":", 2).map(Number);
    const [bCreatedAt, bPostID] = b.split(":", 2).map(Number);
    return aCreatedAt! - bCreatedAt! || aPostID! - bPostID!;
};

const normalizedState = (state: SpaceHomePostsState): SpaceHomePostsState => ({
    ...state,
    friendSpaceIds: [...new Set(state.friendSpaceIds)].sort(),
    latestPosts: [...state.latestPosts]
        .sort(descendingPostOrder)
        .filter(
            (post, index, posts) =>
                posts.findIndex((item) => item.spaceId == post.spaceId) ==
                index,
        )
        .map(cacheablePost),
    readAheadPosts: [...state.readAheadPosts]
        .sort(descendingPostOrder)
        .filter(
            (post, index, posts) =>
                posts.findIndex((item) => item.postId == post.postId) == index,
        ),
    unreadPosts: [...state.unreadPosts]
        .sort(descendingPostOrder)
        .filter(
            (post, index, posts) =>
                posts.findIndex((item) => item.postId == post.postId) == index,
        )
        .map(cacheablePost),
    version: homePostsVersion,
});

const enqueueCacheOperation = async (
    key: string,
    operation: () => Promise<void>,
) => {
    const previous = cacheOperations.get(key) ?? Promise.resolve();
    const next = previous.catch(() => undefined).then(operation);
    cacheOperations.set(key, next);
    try {
        await next;
    } finally {
        if (cacheOperations.get(key) == next) cacheOperations.delete(key);
    }
};

const readState = async (
    key: string,
): Promise<SpaceHomePostsState | undefined> => {
    if (memoryCache.has(key)) return memoryCache.get(key);
    let value: unknown;
    try {
        value = await getKV(key);
    } catch (error) {
        log.warn("Failed to read Space home posts cache", error);
        memoryCache.set(key, undefined);
        return undefined;
    }
    const parsed = SpaceHomePostsStateSchema.safeParse(value);
    const state = parsed.success ? normalizedState(parsed.data) : undefined;
    memoryCache.set(key, state);
    if (!parsed.success && value !== undefined) {
        try {
            await removeKV(key);
        } catch (error) {
            log.warn("Failed to remove invalid Space home posts cache", error);
        }
    }
    return state;
};

const writeState = async (key: string, state: SpaceHomePostsState) => {
    const normalized = normalizedState(state);
    memoryCache.set(key, normalized);
    try {
        await setKV(key, normalized);
    } catch (error) {
        log.warn("Failed to persist Space home posts cache", error);
    }
};

const updateState = async (
    viewerSpaceId: string,
    update: (state: SpaceHomePostsState) => SpaceHomePostsState,
) => {
    const generation = cacheGeneration;
    const key = await homePostsKey(viewerSpaceId);
    if (!key || generation != cacheGeneration) return undefined;

    let nextState: SpaceHomePostsState | undefined;
    await enqueueCacheOperation(key, async () => {
        if (generation != cacheGeneration) return;
        const state = await readState(key);
        if (
            generation != cacheGeneration ||
            state?.viewerSpaceId != viewerSpaceId
        ) {
            return;
        }
        nextState = normalizedState(update(cloneState(state)));
        if (generation != cacheGeneration) return;
        await writeState(key, nextState);
        if (generation != cacheGeneration) {
            memoryCache.delete(key);
            await removeKV(key);
            nextState = undefined;
        }
    });
    return nextState ? cloneState(nextState) : undefined;
};

export const loadSpaceHomePosts = async (viewerSpaceId: string) => {
    const generation = cacheGeneration;
    const key = await homePostsKey(viewerSpaceId);
    if (!key || generation != cacheGeneration) return undefined;
    await cacheOperations.get(key);
    if (generation != cacheGeneration) return undefined;
    const state = await readState(key);
    if (generation != cacheGeneration) {
        memoryCache.delete(key);
        return undefined;
    }
    return state?.viewerSpaceId == viewerSpaceId
        ? cloneState(state)
        : undefined;
};

const friendSpaceIdsFrom = (friends: FriendProfile[]) =>
    [...new Set(friends.flatMap((friend) => friend.spaceId ?? []))].sort();

const latestPostsFor = (posts: SpacePost[], friendSpaceIds: Set<string>) => {
    const latestPosts = new Map<string, SpacePost>();
    for (const post of posts) {
        if (
            friendSpaceIds.has(post.spaceId) &&
            !latestPosts.has(post.spaceId)
        ) {
            latestPosts.set(post.spaceId, post);
        }
    }
    return latestPosts;
};

const loadAllHomePosts = async (viewerSpaceId: string, after?: string) => {
    const items = new Array<SpacePost>();
    let page = await loadCurrentHomePostsPage(viewerSpaceId, after);
    const syncCursor = page.syncCursor;
    while (true) {
        items.push(...page.items);
        if (!page.nextCursor) break;
        page = await loadCurrentHomePostsPage(
            viewerSpaceId,
            after,
            page.nextCursor,
        );
    }
    return { items, syncCursor };
};

const refreshAfterCursor = (state: SpaceHomePostsState) => {
    const oldestUnreadPost = state.unreadPosts[state.unreadPosts.length - 1];
    return oldestUnreadPost
        ? `${oldestUnreadPost.timestampMs * 1000}:0`
        : state.syncCursor;
};

const removeLegacyState = async (viewerSpaceId: string) => {
    const scope = await storageScope(viewerSpaceId);
    if (!scope) return;
    try {
        await Promise.all([
            removeKV(
                [
                    "space-feed",
                    "v1",
                    scope.origin,
                    scope.userID,
                    viewerSpaceId,
                ].join(":"),
            ),
            removeKV(
                [
                    "space-post-read-state",
                    "v1",
                    scope.origin,
                    scope.userID,
                    viewerSpaceId,
                ].join(":"),
            ),
        ]);
    } catch (error) {
        log.warn("Failed to remove legacy Space home posts cache", error);
    }
};

export const initializeSpaceHomePosts = async (
    viewerSpaceId: string,
    friends: FriendProfile[],
) => {
    const generation = cacheGeneration;
    const key = await homePostsKey(viewerSpaceId);
    if (!key || generation != cacheGeneration) return undefined;

    const friendSpaceIds = friendSpaceIdsFrom(friends);
    const friendSpaceIdSet = new Set(friendSpaceIds);
    const result = await loadAllHomePosts(viewerSpaceId);
    const latestPosts = latestPostsFor(result.items, friendSpaceIdSet);

    const state = normalizedState({
        friendSpaceIds,
        latestPosts: [...latestPosts.values()],
        readAheadPosts: [],
        syncCursor: result.syncCursor,
        unreadPosts: [],
        version: homePostsVersion,
        viewerSpaceId,
    });
    await enqueueCacheOperation(key, async () => {
        if (generation != cacheGeneration) return;
        await writeState(key, state);
        if (generation != cacheGeneration) {
            memoryCache.delete(key);
            await removeKV(key);
        }
    });
    if (generation != cacheGeneration) return undefined;
    await removeLegacyState(viewerSpaceId);
    return cloneState(state);
};

export const refreshSpaceHomePosts = async (
    viewerSpaceId: string,
    friends: FriendProfile[],
) => {
    const savedState = await loadSpaceHomePosts(viewerSpaceId);
    if (!savedState) {
        return initializeSpaceHomePosts(viewerSpaceId, friends);
    }

    const currentFriendSpaceIds = friendSpaceIdsFrom(friends);
    const currentFriendSpaceIdSet = new Set(currentFriendSpaceIds);
    const addedFriendSpaceIds = currentFriendSpaceIds.filter(
        (spaceId) => !savedState.friendSpaceIds.includes(spaceId),
    );
    const addedFriendSpaceIdSet = new Set(addedFriendSpaceIds);
    const savedMarker = markerFromCursor(savedState.syncCursor);
    const result = await loadAllHomePosts(
        viewerSpaceId,
        refreshAfterCursor(savedState),
    );
    const latestPosts = latestPostsFor(result.items, currentFriendSpaceIdSet);
    const savedLatestPostsBySpace = new Map(
        savedState.latestPosts.map((post) => [post.spaceId, post]),
    );
    const returnedPostsByID = new Map(
        result.items.map((post) => [post.postId, post]),
    );
    const discoveredPosts = result.items.filter((post) => {
        if (savedMarker && isAfter(post, savedMarker)) return true;
        if (latestPosts.get(post.spaceId)?.postId != post.postId) {
            return false;
        }
        const savedLatestPost = savedLatestPostsBySpace.get(post.spaceId);
        return !savedLatestPost || isAfter(post, savedLatestPost);
    });
    const nextMarker = markerFromCursor(result.syncCursor);
    return updateState(viewerSpaceId, (state) => {
        const currentMarker = markerFromCursor(state.syncCursor);
        if (
            currentMarker &&
            (!nextMarker ||
                compareCursors(result.syncCursor, state.syncCursor) <= 0)
        ) {
            return state;
        }

        const readAheadPostIds = new Set(
            state.readAheadPosts.map((post) => post.postId),
        );
        const unreadPostsByID = new Map<number, SpacePost>();
        for (const post of state.unreadPosts) {
            const returnedPost = returnedPostsByID.get(post.postId);
            if (
                returnedPost &&
                currentFriendSpaceIdSet.has(returnedPost.spaceId) &&
                !returnedPost.isUnavailable
            ) {
                unreadPostsByID.set(returnedPost.postId, returnedPost);
            }
        }
        for (const post of discoveredPosts) {
            if (
                currentFriendSpaceIdSet.has(post.spaceId) &&
                !addedFriendSpaceIdSet.has(post.spaceId) &&
                !post.isUnavailable &&
                !readAheadPostIds.has(post.postId)
            ) {
                unreadPostsByID.set(post.postId, post);
            }
        }

        return {
            ...state,
            friendSpaceIds: currentFriendSpaceIds,
            latestPosts: [...latestPosts.values()],
            readAheadPosts: nextMarker
                ? state.readAheadPosts.filter((post) =>
                      isAfter(post, nextMarker),
                  )
                : state.readAheadPosts,
            syncCursor: result.syncCursor,
            unreadPosts: [...unreadPostsByID.values()],
        };
    });
};

export const markSpaceHomePostRead = (
    viewerSpaceId: string,
    post: SpacePostMarker,
) =>
    updateState(viewerSpaceId, (state) => {
        const syncMarker = markerFromCursor(state.syncCursor);
        return {
            ...state,
            readAheadPosts:
                syncMarker && !isAfter(post, syncMarker)
                    ? state.readAheadPosts
                    : [...state.readAheadPosts, markerFor(post)],
            unreadPosts: state.unreadPosts.filter(
                (item) => item.postId != post.postId,
            ),
        };
    });

export const patchCachedSpaceHomePost = (
    viewerSpaceId: string,
    postId: number,
    patch: Partial<Pick<SpacePost, "caption" | "viewerLiked">>,
) =>
    updateState(viewerSpaceId, (state) => ({
        ...state,
        latestPosts: state.latestPosts.map((post) =>
            post.postId == postId ? { ...post, ...patch } : post,
        ),
        unreadPosts: state.unreadPosts.map((post) =>
            post.postId == postId ? { ...post, ...patch } : post,
        ),
    }));

export const removeCachedSpaceHomePostsBySpace = (
    viewerSpaceId: string,
    removedSpaceId: string,
) =>
    updateState(viewerSpaceId, (state) => ({
        ...state,
        friendSpaceIds: state.friendSpaceIds.filter(
            (spaceId) => spaceId != removedSpaceId,
        ),
        latestPosts: state.latestPosts.filter(
            (post) => post.spaceId != removedSpaceId,
        ),
        unreadPosts: state.unreadPosts.filter(
            (post) => post.spaceId != removedSpaceId,
        ),
    }));

export const clearSpaceHomePostsMemoryCache = () => {
    cacheGeneration += 1;
    memoryCache.clear();
};
