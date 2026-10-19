import type { LlmProvider } from "@/services/llm/provider";
import {
    addNotesCollection,
    indexNotesCollection,
    listenForNotesStateChanged,
    listNotesCollections,
    notesErrorMessage,
    removeNotesCollection,
    selectNotesFolder,
    type NotesCollection,
} from "@/services/notes";
import {
    NotesLifecycleController,
    type NotesCollectionActivity,
    type NotesCollectionView,
} from "@/services/notes-lifecycle";
import { tauriCommandError } from "@/services/tauri-error";
import log from "ente-base/log";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

const NOTES_INDEX_RERUN_YIELD_MS = 25;
const NOTES_REMOVE_WAIT_ERROR =
    "Wait for indexing to finish, then remove this folder.";

interface UseNotesCollectionsOptions {
    isTauriRuntime: boolean;
    isGenerating: boolean;
    isIndexingPaused: boolean;
    isIndexingBlocked: () => boolean;
    modelReady: boolean;
    ensureProvider: () => Promise<LlmProvider>;
    cancelIndexing: () => void;
    confirmRemoval: (label: string, remove: () => Promise<void>) => void;
}

export const useNotesCollections = ({
    isTauriRuntime,
    isGenerating,
    isIndexingPaused,
    isIndexingBlocked,
    modelReady,
    ensureProvider,
    cancelIndexing,
    confirmRemoval,
}: UseNotesCollectionsOptions) => {
    const [collections, setCollections] = useState<NotesCollection[]>([]);
    const [loading, setLoading] = useState(false);
    const [loaded, setLoaded] = useState(false);
    const [operationError, setOperationError] = useState<string | null>(null);
    const [listError, setListError] = useState<string | null>(null);
    const [subscriptionError, setSubscriptionError] = useState<string | null>(
        null,
    );
    const [syncAttempt, setSyncAttempt] = useState(0);
    const [lifecycleRevision, setLifecycleRevision] = useState(0);
    const controllerRef = useRef<NotesLifecycleController | null>(null);
    if (!controllerRef.current) {
        controllerRef.current = new NotesLifecycleController();
    }
    const controller = controllerRef.current;
    const lifecycleChanged = useCallback(
        () => setLifecycleRevision((revision) => revision + 1),
        [],
    );

    useEffect(() => {
        controller.activate();
        return () => {
            if (controller.hasActiveJobs()) cancelIndexing();
            controller.dispose();
        };
    }, [cancelIndexing, controller]);

    const refresh = useCallback(async () => {
        if (!isTauriRuntime) return false;
        const request = controller.beginRefresh();
        setLoading(true);
        try {
            while (controller.isRefreshCurrent(request)) {
                const mutation = controller.refreshMutationSnapshot();
                try {
                    const next = await listNotesCollections();
                    if (!controller.isRefreshCurrent(request)) return false;
                    if (!controller.canApplyRefresh(request, mutation)) {
                        continue;
                    }
                    setCollections(next);
                    setLoaded(true);
                    setListError(null);
                    return true;
                } catch (error) {
                    if (!controller.isRefreshCurrent(request)) return false;
                    if (!controller.canApplyRefresh(request, mutation)) {
                        continue;
                    }
                    setListError(notesErrorMessage(error));
                    log.error("Failed to refresh Your Notes", error);
                    return false;
                }
            }
        } finally {
            if (controller.isRefreshCurrent(request)) setLoading(false);
        }
        return false;
    }, [controller, isTauriRuntime]);

    const replaceCollection = useCallback(
        (collection: NotesCollection) => {
            controller.markMutation();
            setCollections((current) => {
                const exists = current.some(
                    (item) => item.id === collection.id,
                );
                return exists
                    ? current.map((item) =>
                          item.id === collection.id ? collection : item,
                      )
                    : [...current, collection];
            });
        },
        [controller],
    );

    const updateCollection = useCallback(
        (collection: NotesCollection) => {
            controller.markMutation();
            setCollections((current) =>
                current.map((item) =>
                    item.id === collection.id ? collection : item,
                ),
            );
        },
        [controller],
    );

    const startIndex = useCallback(
        (
            collectionId: string,
            force = false,
            automatic = false,
            automaticRequestKey?: number,
        ) => {
            const blocked = !modelReady || isIndexingBlocked();
            const request = automatic
                ? controller.ensureIndex(
                      collectionId,
                      blocked,
                      automaticRequestKey,
                  )
                : controller.requestIndex(collectionId, force, blocked);
            if (request === "ignored") return;
            lifecycleChanged();
            if (request === "queued") {
                log.info("Your Notes indexing queued", { collectionId });
                return;
            }
            setOperationError(null);
            log.info("Your Notes indexing started", {
                collectionId,
                automatic,
                force,
            });

            const ownsIndex = () => controller.canContinueIndex(collectionId);
            const canStartIndex = () => ownsIndex() && !isIndexingBlocked();
            void ensureProvider()
                .then((provider) =>
                    provider.withKnowledgeRetrieval(async (retrievalEpoch) => {
                        let needsRerun = true;
                        let bypassQuietPeriod = force;
                        while (needsRerun && ownsIndex()) {
                            if (isIndexingBlocked()) {
                                controller.queueIndex(
                                    collectionId,
                                    bypassQuietPeriod,
                                );
                                lifecycleChanged();
                                return;
                            }
                            const result = await indexNotesCollection(
                                collectionId,
                                bypassQuietPeriod,
                                retrievalEpoch,
                            );
                            if (!ownsIndex()) {
                                return;
                            }
                            bypassQuietPeriod = false;
                            replaceCollection(result.collection);
                            needsRerun = result.needsRerun;
                            if (needsRerun) {
                                await new Promise<void>((resolve) =>
                                    window.setTimeout(
                                        resolve,
                                        NOTES_INDEX_RERUN_YIELD_MS,
                                    ),
                                );
                            }
                        }
                    }, canStartIndex),
                )
                .catch((error: unknown) => {
                    if (controller.isRemoving(collectionId)) return;
                    const { name } = tauriCommandError(error);
                    if (name === "cancelled") {
                        controller.queueIndex(collectionId, force);
                        log.info(
                            "Your Notes indexing queued after cancellation",
                            { collectionId },
                        );
                    } else if (name !== "not_due") {
                        controller.failIndex(collectionId);
                        setOperationError(notesErrorMessage(error));
                        log.error("Failed to index Your Notes", error);
                    }
                    void refresh();
                })
                .finally(() => {
                    const completion = controller.finishIndex(collectionId);
                    lifecycleChanged();
                    if (completion.clearedRemovalWait) {
                        setOperationError((current) =>
                            current === NOTES_REMOVE_WAIT_ERROR
                                ? null
                                : current,
                        );
                    }
                });
        },
        [
            controller,
            ensureProvider,
            isIndexingBlocked,
            lifecycleChanged,
            modelReady,
            refresh,
            replaceCollection,
        ],
    );

    const runIndex = useCallback(
        (collectionId: string, force = false) =>
            startIndex(collectionId, force),
        [startIndex],
    );

    useEffect(() => {
        const blocked = !modelReady || isIndexingBlocked();
        const queued = controller.drainQueued(blocked);
        if (queued.length > 0) {
            lifecycleChanged();
            for (const [collectionId, force] of queued) {
                startIndex(collectionId, force);
            }
        }
    }, [
        controller,
        isGenerating,
        isIndexingPaused,
        isIndexingBlocked,
        lifecycleChanged,
        lifecycleRevision,
        modelReady,
        startIndex,
    ]);

    useEffect(() => {
        if (!isTauriRuntime) return;
        let disposed = false;
        let unlisten: (() => void) | undefined;
        const initialRefresh = refresh();
        const refreshAfterSubscription = async () => {
            await initialRefresh;
            if (!disposed) await refresh();
        };
        void listenForNotesStateChanged((collection) => {
            if (!disposed) updateCollection(collection);
        })
            .then(async (listener) => {
                if (disposed) {
                    listener();
                    return;
                }
                unlisten = listener;
                setSubscriptionError(null);
                await refreshAfterSubscription();
            })
            .catch((error: unknown) => {
                if (disposed) return;
                setSubscriptionError(notesErrorMessage(error));
                log.error("Failed to listen for Your Notes updates", error);
            });
        return () => {
            disposed = true;
            controller.cancelRefreshes();
            unlisten?.();
        };
    }, [controller, isTauriRuntime, refresh, syncAttempt, updateCollection]);

    useEffect(() => {
        if (!isTauriRuntime || !modelReady) return;
        const timeouts: number[] = [];
        const now = Date.now();
        for (const collection of collections) {
            if (
                collection.updateDueAtMs != null &&
                (collection.status === "ready" ||
                    collection.status === "pending")
            ) {
                timeouts.push(
                    window.setTimeout(
                        () =>
                            startIndex(
                                collection.id,
                                false,
                                true,
                                collection.updateDueAtMs ?? undefined,
                            ),
                        Math.max(0, collection.updateDueAtMs - now),
                    ),
                );
            }
        }
        return () => {
            for (const timeout of timeouts) window.clearTimeout(timeout);
        };
    }, [collections, isTauriRuntime, modelReady, startIndex]);

    useEffect(() => {
        if (!isTauriRuntime || !modelReady) return;
        for (const collection of collections) {
            if (
                collection.status === "pending" &&
                collection.updateDueAtMs == null
            ) {
                startIndex(collection.id, false, true);
            }
        }
    }, [
        collections,
        isTauriRuntime,
        lifecycleRevision,
        modelReady,
        startIndex,
    ]);

    const retry = useCallback(() => {
        setOperationError(null);
        setSyncAttempt((attempt) => attempt + 1);
    }, []);

    const addFolder = useCallback(
        async (onAdded?: (collection: NotesCollection) => void) => {
            setOperationError(null);
            try {
                if (!loaded && !(await refresh())) return;
                const sourceRoot = await selectNotesFolder();
                if (!sourceRoot) return;
                const collection = await addNotesCollection(sourceRoot);
                onAdded?.(collection);
                replaceCollection(collection);
                runIndex(collection.id);
            } catch (error) {
                setOperationError(notesErrorMessage(error));
                log.error("Failed to add Notes folder", error);
            }
        },
        [loaded, refresh, replaceCollection, runIndex],
    );

    const removeCollection = useCallback(
        (collectionId: string, label: string) => {
            confirmRemoval(label, async () => {
                const removal = controller.beginRemoval(collectionId);
                if (removal.kind === "wait") {
                    setOperationError(NOTES_REMOVE_WAIT_ERROR);
                    return;
                }
                setOperationError(null);
                try {
                    await removeNotesCollection(collectionId);
                    controller.markMutation();
                    controller.finishRemoval(collectionId);
                    setCollections((current) =>
                        current.filter((item) => item.id !== collectionId),
                    );
                } catch (error) {
                    controller.cancelRemoval(collectionId);
                    setOperationError(notesErrorMessage(error));
                    log.error("Failed to remove Notes collection", error);
                    void refresh();
                    if (removal.queuedForce !== undefined) {
                        startIndex(collectionId, removal.queuedForce);
                    }
                }
            });
        },
        [confirmRemoval, controller, refresh, startIndex],
    );

    const collectionViews = useMemo<NotesCollectionView[]>(
        () =>
            collections.map((collection) => {
                const lifecycleActivity = controller.indexActivity(
                    collection.id,
                );
                let activity: NotesCollectionActivity;
                if (
                    collection.status === "indexing" ||
                    collection.status === "updating"
                ) {
                    activity = null;
                } else if (lifecycleActivity === "failed") {
                    activity = "failed";
                } else if (lifecycleActivity === "starting") {
                    activity = "starting";
                } else if (lifecycleActivity === "queued") {
                    activity = !modelReady
                        ? "waitingForModel"
                        : isIndexingPaused
                          ? "waitingForChat"
                          : isGenerating || isIndexingBlocked()
                            ? "waitingForGeneration"
                            : "starting";
                } else if (collection.updateDueAtMs != null) {
                    activity = null;
                } else if (collection.status !== "pending") {
                    activity = null;
                } else if (!modelReady) {
                    activity = "waitingForModel";
                } else if (isIndexingPaused) {
                    activity = "waitingForChat";
                } else if (isGenerating || isIndexingBlocked()) {
                    activity = "waitingForGeneration";
                } else {
                    activity = "starting";
                }
                return { ...collection, activity };
            }),
        [
            collections,
            controller,
            isGenerating,
            isIndexingPaused,
            isIndexingBlocked,
            lifecycleRevision,
            modelReady,
        ],
    );

    return {
        collections: collectionViews,
        loading,
        loaded,
        error: subscriptionError ?? listError ?? operationError,
        retry,
        addFolder,
        removeCollection,
        runIndex,
    };
};
