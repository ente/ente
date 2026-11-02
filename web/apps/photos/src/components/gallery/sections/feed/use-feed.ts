import { buildFeedItems, type FeedSocialData } from "@/services/feed";
import { fetchFeedData } from "@/services/feed-fetch";
import log from "ente-base/log";
import { useCallback, useEffect, useMemo, useState } from "react";
import type { GallerySectionProps } from "../types";

export const useFeed = (library: GallerySectionProps["library"]) => {
    const userID = library.user!.id;
    const [socialByCollection, setSocialByCollection] = useState<
        Record<number, FeedSocialData>
    >({});
    const [refreshing, setRefreshing] = useState(true);
    const [failed, setFailed] = useState(false);
    const [revision, setRevision] = useState(0);
    const [limit, setLimit] = useState(50);
    const collections = useMemo(
        () =>
            library.collections.filter(
                (c) => !library.hiddenCollectionIDs.has(c.id),
            ),
        [library.collections, library.hiddenCollectionIDs],
    );

    useEffect(() => {
        const controller = new AbortController();
        const { signal } = controller;
        void (async () => {
            setRefreshing(true);
            setFailed(false);
            try {
                const result = await fetchFeedData(collections, signal);
                signal.throwIfAborted();
                setSocialByCollection(result.socialByCollection);
                setFailed(result.failed);
            } catch (error) {
                if (signal.aborted) return;
                log.warn("Could not load Feed", error);
                setFailed(true);
            } finally {
                if (!signal.aborted) setRefreshing(false);
            }
        })();
        return () => controller.abort();
    }, [userID, collections, revision]);

    const items = useMemo(
        () =>
            buildFeedItems({
                userID,
                collections,
                files: library.collectionFiles,
                socialByCollection,
                hiddenCollectionIDs: library.hiddenCollectionIDs,
                excludedFileIDs: new Set([
                    ...library.hiddenFileIDs,
                    ...library.tempHiddenFileIDs,
                    ...library.tempDeletedFileIDs,
                ]),
            }),
        [
            userID,
            collections,
            library.collectionFiles,
            library.hiddenCollectionIDs,
            library.hiddenFileIDs,
            library.tempHiddenFileIDs,
            library.tempDeletedFileIDs,
            socialByCollection,
        ],
    );

    const refresh = useCallback(() => {
        setRevision((value) => value + 1);
    }, []);
    const loadMore = useCallback(
        () => setLimit((value) => Math.min(500, value + 50)),
        [],
    );
    return {
        items: items.slice(0, limit),
        hasMore: items.length > limit,
        loadMore,
        socialByCollection,
        refreshing,
        failed,
        refresh,
    };
};
