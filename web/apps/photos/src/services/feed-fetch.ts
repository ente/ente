import log from "ente-base/log";
import type { Collection } from "ente-media/collection";
import {
    getAnonProfiles,
    getSocialUpdates,
    getUnifiedSocialDiff,
} from "ente-new/photos/services/social";
import { emptyFeedSocialData, type FeedSocialData } from "./feed";

export const fetchFeedData = async (
    albums: readonly Collection[],
    signal: AbortSignal,
): Promise<{
    socialByCollection: Record<number, FeedSocialData>;
    failed: boolean;
}> => {
    const updates = await getSocialUpdates(signal);
    const albumsByID = new Map(albums.map((album) => [album.id, album]));
    const socialByCollection: Record<number, FeedSocialData> = {};
    let failed = false;
    const pending = updates.filter((update) =>
        albumsByID.has(update.collectionID),
    );
    let index = 0;
    const worker = async () => {
        while (index < pending.length) {
            signal.throwIfAborted();
            const update = pending[index++]!;
            const album = albumsByID.get(update.collectionID)!;
            const data = emptyFeedSocialData();
            try {
                if (
                    (update.commentsUpdatedAt ?? 0) > 0 ||
                    (update.reactionsUpdatedAt ?? 0) > 0
                ) {
                    let commentsSinceTime = 0;
                    let reactionsSinceTime = 0;
                    while (true) {
                        signal.throwIfAborted();
                        const diff = await getUnifiedSocialDiff(
                            album.id,
                            album.key,
                            { commentsSinceTime, reactionsSinceTime, signal },
                        );
                        data.comments.push(...diff.comments);
                        data.reactions.push(...diff.reactions);
                        if (!diff.hasMoreComments && !diff.hasMoreReactions)
                            break;
                        if (
                            (diff.hasMoreComments &&
                                diff.commentsUpdatedAt <= commentsSinceTime) ||
                            (diff.hasMoreReactions &&
                                diff.reactionsUpdatedAt <= reactionsSinceTime)
                        ) {
                            throw new Error(
                                "Social pagination cursor did not advance",
                            );
                        }
                        commentsSinceTime = diff.commentsUpdatedAt;
                        reactionsSinceTime = diff.reactionsUpdatedAt;
                    }
                }
                if ((update.anonProfilesUpdatedAt ?? 0) > 0) {
                    try {
                        data.anonNames = Object.fromEntries(
                            await getAnonProfiles(album.id, album.key, signal),
                        );
                    } catch (error) {
                        signal.throwIfAborted();
                        failed = true;
                        log.warn("Could not refresh anonymous names", error);
                    }
                }
                socialByCollection[album.id] = data;
            } catch (error) {
                signal.throwIfAborted();
                failed = true;
                log.warn("Could not refresh album activity", error);
            }
        }
    };
    await Promise.all(
        Array.from({ length: Math.min(3, pending.length) }, worker),
    );
    signal.throwIfAborted();
    return { socialByCollection, failed };
};
