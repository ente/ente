import { getKV, setKV } from "ente-base/kv";
import log from "ente-base/log";
import { apiOrigin } from "ente-base/origins";
import type { Collection } from "ente-media/collection";
import {
    getAnonProfiles,
    getCollectionSocialDiff,
    getSocialUpdates,
} from "ente-new/photos/services/social";
import { emptyFeedSocialData, type FeedSocialData } from "./feed";

export interface FeedSnapshot {
    version: 1;
    sharedPhotoCutoff: number;
    collections: Record<number, FeedSocialData>;
}

const storageKey = async (userID: number) =>
    `photos-feed:v1:${await apiOrigin()}:${userID}`;

export const readFeedSnapshot = async (
    userID: number,
    signal?: AbortSignal,
): Promise<FeedSnapshot> => {
    const key = await storageKey(userID);
    const saved = (await getKV(key)) as FeedSnapshot | undefined;
    if (saved?.version === 1) return saved;
    const initial: FeedSnapshot = {
        version: 1,
        sharedPhotoCutoff: Date.now() * 1000,
        collections: {},
    };
    // Keep the rollout boundary stable even if the initial network sync fails.
    signal?.throwIfAborted();
    await setKV(key, initial);
    return initial;
};

const mergeRecords = <T extends { id: string; isDeleted: boolean }>(
    existing: T[],
    changes: T[],
    retainDeleted = false,
) => {
    const records = new Map(existing.map((record) => [record.id, record]));
    for (const record of changes) {
        if (record.isDeleted && !retainDeleted) records.delete(record.id);
        else records.set(record.id, record);
    }
    return [...records.values()];
};

/** Sync whole collections, with independent cursors and tombstone handling. */
export const syncFeedSnapshot = async (
    userID: number,
    albums: readonly Collection[],
    snapshot: FeedSnapshot,
    signal: AbortSignal,
): Promise<{ snapshot: FeedSnapshot; failed: boolean }> => {
    const updates = await getSocialUpdates(signal);
    const albumsByID = new Map(albums.map((album) => [album.id, album]));
    const next: FeedSnapshot = {
        ...snapshot,
        collections: Object.fromEntries(
            Object.entries(snapshot.collections).filter(([id]) =>
                albumsByID.has(Number(id)),
            ),
        ),
    };
    let failed = false;
    // Limit concurrent decryption and requests for accounts with many albums.
    const pending = updates.filter((update) =>
        albumsByID.has(update.collectionID),
    );
    let index = 0;
    const worker = async () => {
        while (index < pending.length) {
            signal.throwIfAborted();
            const update = pending[index++]!;
            const album = albumsByID.get(update.collectionID)!;
            let data = next.collections[album.id] ?? emptyFeedSocialData();
            try {
                if (
                    (update.commentsUpdatedAt ?? 0) > data.commentsUpdatedAt ||
                    (update.reactionsUpdatedAt ?? 0) > data.reactionsUpdatedAt
                ) {
                    // Overlap the boundary to reconcile edits at equal timestamps.
                    let commentsSinceTime = Math.max(
                        0,
                        data.commentsUpdatedAt - 1,
                    );
                    let reactionsSinceTime = Math.max(
                        0,
                        data.reactionsUpdatedAt - 1,
                    );
                    for (;;) {
                        signal.throwIfAborted();
                        const diff = await getCollectionSocialDiff(
                            album.id,
                            album.key,
                            { commentsSinceTime, reactionsSinceTime },
                            signal,
                        );
                        data = {
                            ...data,
                            comments: mergeRecords(
                                data.comments,
                                diff.comments,
                                // A deleted parent still identifies a reply's owner.
                                true,
                            ),
                            reactions: mergeRecords(
                                data.reactions,
                                diff.reactions,
                            ),
                            commentsUpdatedAt: Math.max(
                                data.commentsUpdatedAt,
                                diff.commentsUpdatedAt,
                            ),
                            reactionsUpdatedAt: Math.max(
                                data.reactionsUpdatedAt,
                                diff.reactionsUpdatedAt,
                            ),
                        };
                        if (!diff.hasMoreComments && !diff.hasMoreReactions)
                            break;
                        if (
                            (diff.hasMoreComments &&
                                diff.commentsUpdatedAt <= commentsSinceTime) ||
                            (diff.hasMoreReactions &&
                                diff.reactionsUpdatedAt <= reactionsSinceTime)
                        ) {
                            throw new Error(
                                "Social sync cursor did not advance",
                            );
                        }
                        commentsSinceTime = diff.commentsUpdatedAt;
                        reactionsSinceTime = diff.reactionsUpdatedAt;
                    }
                }
                if (
                    (update.anonProfilesUpdatedAt ?? 0) >
                    data.anonProfilesUpdatedAt
                ) {
                    data = {
                        ...data,
                        anonNames: Object.fromEntries(
                            await getAnonProfiles(album.id, album.key, signal),
                        ),
                        anonProfilesUpdatedAt: update.anonProfilesUpdatedAt!,
                    };
                }
                next.collections[album.id] = data;
            } catch (error) {
                signal.throwIfAborted();
                // Keep the previous collection snapshot and cursors on failure.
                failed = true;
                log.warn("Could not refresh album activity", error);
            }
        }
    };
    await Promise.all(
        Array.from({ length: Math.min(3, pending.length) }, worker),
    );
    const key = await storageKey(userID);
    signal.throwIfAborted();
    await setKV(key, next);
    return { snapshot: next, failed };
};
