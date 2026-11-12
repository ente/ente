import { buildFeedItems, type FeedSocialData } from "@/services/feed";
import { fetchFeedData } from "@/services/feed-fetch";
import log from "ente-base/log";
import {
    useCallback,
    useEffect,
    useEffectEvent,
    useMemo,
    useState,
} from "react";
import type { GallerySectionProps } from "../types";

export const useFeed = (
    library: GallerySectionProps["library"],
    onRemotePull: GallerySectionProps["operations"]["onRemotePull"],
) => {
    const userID = library.user!.id;
    const [socialByCollection, setSocialByCollection] = useState<
        Record<number, FeedSocialData>
    >({});
    const [refreshing, setRefreshing] = useState(true);
    const [syncingLibrary, setSyncingLibrary] = useState(false);
    const [libraryFailed, setLibraryFailed] = useState(false);
    const [failed, setFailed] = useState(false);
    const [revision, setRevision] = useState(0);
    const [limit, setLimit] = useState(50);
    useEffect(() => {
        setLibraryFailed(false);
    }, [library.remotePullRevision]);
    const collections = useMemo(
        () =>
            library.collections.filter(
                (c) => !library.hiddenCollectionIDs.has(c.id),
            ),
        [library.collections, library.hiddenCollectionIDs],
    );

    const collectionIDs = collections
        .map((collection) => collection.id)
        .sort((a, b) => a - b)
        .join(",");
    const fetchSocialData = useEffectEvent((signal: AbortSignal) =>
        fetchFeedData(collections, signal),
    );

    useEffect(() => {
        if (syncingLibrary) return;
        const controller = new AbortController();
        const { signal } = controller;
        void (async () => {
            setRefreshing(true);
            setFailed(false);
            try {
                const result = await fetchSocialData(signal);
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
    }, [userID, collectionIDs, revision, syncingLibrary]);

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

    const refresh = useCallback(async () => {
        setSyncingLibrary(true);
        setLibraryFailed(false);
        try {
            await onRemotePull({
                silent: true,
                strict: true,
                source: "feed-refresh",
            });
        } catch (error) {
            log.warn("Could not refresh Feed library", error);
            setLibraryFailed(true);
        } finally {
            setRevision((value) => value + 1);
            setSyncingLibrary(false);
        }
    }, [onRemotePull]);
    const refreshSocial = useCallback(
        () => setRevision((value) => value + 1),
        [],
    );
    const loadMore = useCallback(
        () => setLimit((value) => Math.min(500, value + 50)),
        [],
    );
    return {
        items: items.slice(0, limit),
        hasMore: items.length > limit,
        loadMore,
        socialByCollection,
        refreshing: refreshing || syncingLibrary,
        failed: failed || libraryFailed,
        refresh,
        refreshSocial,
    };
};
