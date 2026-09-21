import { savedPartialLocalUser } from "ente-accounts/services/accounts-db";
import { getKV, removeKV, setKV } from "ente-base/kv";
import log from "ente-base/log";
import { apiOrigin } from "ente-base/origins";
import { CachedSpacePost } from "services/post-cache";
import type { SpacePost, SpacePostPage } from "services/space";
import { z } from "zod";

const spaceFeedCacheVersion = 2;
const spaceFeedCacheSize = 10;

const SpaceFeedCacheSnapshotSchema = z.object({
    dirty: z.boolean(),
    items: CachedSpacePost.array().max(spaceFeedCacheSize),
    nextCursor: z.string().optional(),
    spaceId: z.string(),
    syncedAtMs: z.number(),
    version: z.literal(spaceFeedCacheVersion),
});

export interface SpaceFeedCacheSnapshot {
    dirty: boolean;
    items: SpacePost[];
    nextCursor?: string;
    spaceId: string;
    syncedAtMs: number;
    version: typeof spaceFeedCacheVersion;
}

const memoryCache = new Map<string, SpaceFeedCacheSnapshot | undefined>();
const cacheOperations = new Map<string, Promise<void>>();
let cacheGeneration = 0;

const cacheKey = async (spaceId: string) => {
    const userID = savedPartialLocalUser()?.id;
    if (!userID || !spaceId.trim()) return undefined;
    try {
        return [
            "space-feed",
            `v${spaceFeedCacheVersion}`,
            await apiOrigin(),
            userID,
            spaceId,
        ].join(":");
    } catch (error) {
        log.warn("Failed to resolve cached Space feed", error);
        return undefined;
    }
};

const clonePost = (post: SpacePost): SpacePost => ({
    ...post,
    imageAsset: post.imageAsset ? { ...post.imageAsset } : undefined,
    photos: post.photos?.map((photo) => ({
        ...photo,
        imageAsset: photo.imageAsset ? { ...photo.imageAsset } : undefined,
    })),
});

const cloneSnapshot = (
    snapshot: SpaceFeedCacheSnapshot,
): SpaceFeedCacheSnapshot => ({
    ...snapshot,
    items: snapshot.items.map(clonePost),
});

const cacheablePost = (post: SpacePost): SpacePost => {
    const cached = clonePost(post);
    delete cached.avatarUrl;
    delete cached.imageUrl;
    cached.photos?.forEach((photo) => {
        delete photo.imageUrl;
    });
    return cached;
};

const normalizedSnapshot = (
    snapshot: SpaceFeedCacheSnapshot,
): SpaceFeedCacheSnapshot => ({
    ...snapshot,
    items: snapshot.items.slice(0, spaceFeedCacheSize).map(cacheablePost),
    nextCursor: snapshot.nextCursor || undefined,
    version: spaceFeedCacheVersion,
});

const enqueueCacheOperation = async (
    key: string,
    operation: () => Promise<void>,
) => {
    const previous = cacheOperations.get(key) ?? Promise.resolve();
    const next = previous
        .catch(() => undefined)
        .then(operation)
        .catch((error: unknown) => {
            log.warn("Failed to update cached Space feed", error);
        });
    cacheOperations.set(key, next);
    await next;
    if (cacheOperations.get(key) == next) cacheOperations.delete(key);
};

export const loadCachedSpaceFeed = async (
    spaceId: string,
): Promise<SpaceFeedCacheSnapshot | undefined> => {
    const generation = cacheGeneration;
    const key = await cacheKey(spaceId);
    if (!key || generation != cacheGeneration) return undefined;

    await cacheOperations.get(key);
    if (generation != cacheGeneration) return undefined;
    if (memoryCache.has(key)) {
        const cached = memoryCache.get(key);
        return cached ? cloneSnapshot(cached) : undefined;
    }

    try {
        const parsed = SpaceFeedCacheSnapshotSchema.safeParse(await getKV(key));
        if (generation != cacheGeneration) return undefined;
        if (!parsed.success || parsed.data.spaceId != spaceId) {
            memoryCache.set(key, undefined);
            if (!parsed.success) await removeKV(key);
            return undefined;
        }

        const snapshot = normalizedSnapshot(parsed.data);
        memoryCache.set(key, snapshot);
        return cloneSnapshot(snapshot);
    } catch (error) {
        log.warn("Failed to load cached Space feed", error);
        return undefined;
    }
};

const writeCachedSpaceFeed = async (
    snapshot: SpaceFeedCacheSnapshot,
    previous?: { syncedAtMs?: number },
): Promise<boolean> => {
    const generation = cacheGeneration;
    const key = await cacheKey(snapshot.spaceId);
    if (!key) return true;
    if (generation != cacheGeneration) return false;
    const normalized = normalizedSnapshot(snapshot);
    let applied = false;

    await enqueueCacheOperation(key, async () => {
        if (generation != cacheGeneration) return;
        if (previous && memoryCache.get(key)?.syncedAtMs != previous.syncedAtMs)
            return;
        applied = true;
        memoryCache.set(key, normalized);
        await setKV(key, normalized);
        if (generation != cacheGeneration) {
            memoryCache.delete(key);
            await removeKV(key);
        }
    });
    return applied;
};

export const cacheCurrentSpaceFeedPage = async (
    spaceId: string,
    page: SpacePostPage,
    previous?: { syncedAtMs?: number },
) =>
    writeCachedSpaceFeed(
        {
            dirty: false,
            items: page.items,
            nextCursor: page.nextCursor,
            spaceId,
            syncedAtMs: Date.now(),
            version: spaceFeedCacheVersion,
        },
        previous,
    );

const updateCachedSpaceFeed = async (
    spaceId: string,
    update: (snapshot: SpaceFeedCacheSnapshot) => SpaceFeedCacheSnapshot,
    createIfMissing = false,
) => {
    const generation = cacheGeneration;
    const key = await cacheKey(spaceId);
    if (!key || generation != cacheGeneration) return;

    await enqueueCacheOperation(key, async () => {
        if (generation != cacheGeneration) return;
        let snapshot = memoryCache.get(key);
        if (!memoryCache.has(key)) {
            const parsed = SpaceFeedCacheSnapshotSchema.safeParse(
                await getKV(key),
            );
            snapshot =
                parsed.success && parsed.data.spaceId == spaceId
                    ? normalizedSnapshot(parsed.data)
                    : undefined;
        }
        if (!snapshot) {
            if (!createIfMissing) return;
            snapshot = {
                dirty: true,
                items: [],
                spaceId,
                syncedAtMs: Date.now(),
                version: spaceFeedCacheVersion,
            };
        }

        const nextSnapshot = normalizedSnapshot({
            ...update(cloneSnapshot(snapshot)),
            syncedAtMs: Math.max(Date.now(), snapshot.syncedAtMs + 1),
        });
        if (generation != cacheGeneration) return;
        memoryCache.set(key, nextSnapshot);
        await setKV(key, nextSnapshot);
        if (generation != cacheGeneration) {
            memoryCache.delete(key);
            await removeKV(key);
        }
    });
};

const descendingPostOrder = (a: SpacePost, b: SpacePost) =>
    b.timestampMs - a.timestampMs || b.postId - a.postId;

export const prependCachedSpaceFeedPost = (spaceId: string, post: SpacePost) =>
    updateCachedSpaceFeed(
        spaceId,
        (snapshot) => ({
            ...snapshot,
            dirty: true,
            items: [
                post,
                ...snapshot.items.filter((item) => item.postId != post.postId),
            ]
                .sort(descendingPostOrder)
                .slice(0, spaceFeedCacheSize),
            nextCursor: undefined,
        }),
        true,
    );

export const removeCachedSpaceFeedPost = (spaceId: string, postId: number) =>
    updateCachedSpaceFeed(spaceId, (snapshot) => ({
        ...snapshot,
        dirty: true,
        items: snapshot.items.filter((item) => item.postId != postId),
        nextCursor: undefined,
    }));

export const removeCachedSpaceFeedPostsBySpace = (
    viewerSpaceId: string,
    removedSpaceId: string,
) =>
    updateCachedSpaceFeed(viewerSpaceId, (snapshot) => ({
        ...snapshot,
        dirty: true,
        items: snapshot.items.filter((item) => item.spaceId != removedSpaceId),
        nextCursor: undefined,
    }));

export const patchCachedSpaceFeedPost = (
    spaceId: string,
    postId: number,
    patch: Partial<Pick<SpacePost, "caption" | "viewerLiked">>,
) =>
    updateCachedSpaceFeed(spaceId, (snapshot) => ({
        ...snapshot,
        items: snapshot.items.map((item) =>
            item.postId == postId ? { ...item, ...patch } : item,
        ),
    }));

export const invalidateCachedSpaceFeed = (spaceId: string) =>
    updateCachedSpaceFeed(spaceId, (snapshot) => ({
        ...snapshot,
        dirty: true,
        nextCursor: undefined,
    }));

export const clearSpaceFeedMemoryCache = () => {
    cacheGeneration += 1;
    memoryCache.clear();
};
