import type { NotesCollection } from "@/services/notes";

type NotesIndexRequest = "start" | "queued" | "ignored";

interface NotesIndexCompletion {
    clearedRemovalWait: boolean;
}

type NotesIndexActivity = "starting" | "queued" | "failed" | null;

export type NotesCollectionActivity =
    | "starting"
    | "updateScheduled"
    | "updateRequested"
    | "waitingForGeneration"
    | "waitingForModel"
    | "waitingForChat"
    | "failed"
    | null;

export interface NotesCollectionView extends NotesCollection {
    activity: NotesCollectionActivity;
}

type NotesRemovalStart =
    { kind: "wait" } | { kind: "start"; queuedForce?: boolean };

export class NotesLifecycleController {
    private activeCollectionId: string | null = null;
    private readonly queued = new Map<string, boolean>();
    private readonly failed = new Map<string, number | undefined>();
    private readonly removing = new Set<string>();
    private removalWaitCollection: string | null = null;
    private mutation = 0;
    private refreshRequest = 0;
    private disposed = false;

    requestIndex(
        collectionId: string,
        force: boolean,
        blocked: boolean,
    ): NotesIndexRequest {
        if (
            this.disposed ||
            this.removing.has(collectionId) ||
            this.activeCollectionId === collectionId
        ) {
            return "ignored";
        }
        this.failed.delete(collectionId);
        if (blocked || this.hasActiveJobs() || this.queued.has(collectionId)) {
            this.queueIndex(collectionId, force);
            return "queued";
        }
        this.activeCollectionId = collectionId;
        return "start";
    }

    ensureIndex(
        collectionId: string,
        blocked: boolean,
        requestKey?: number,
    ): NotesIndexRequest {
        if (
            (this.failed.has(collectionId) &&
                !this.hasNewerUpdate(collectionId, requestKey)) ||
            this.queued.has(collectionId)
        ) {
            return "ignored";
        }
        return this.requestIndex(
            collectionId,
            false,
            blocked || this.queued.size > 0,
        );
    }

    queueIndex(collectionId: string, force: boolean) {
        if (this.disposed || this.removing.has(collectionId)) return;
        this.failed.delete(collectionId);
        this.queued.set(
            collectionId,
            force || (this.queued.get(collectionId) ?? false),
        );
    }

    canContinueIndex(collectionId: string) {
        return (
            !this.disposed &&
            this.activeCollectionId === collectionId &&
            !this.removing.has(collectionId)
        );
    }

    finishIndex(collectionId: string): NotesIndexCompletion {
        if (this.activeCollectionId === collectionId)
            this.activeCollectionId = null;
        const clearedRemovalWait = this.removalWaitCollection === collectionId;
        if (clearedRemovalWait) this.removalWaitCollection = null;
        return { clearedRemovalWait };
    }

    failIndex(collectionId: string, requestKey?: number) {
        this.queued.delete(collectionId);
        this.failed.set(collectionId, requestKey);
    }

    hasNewerUpdate(collectionId: string, requestKey?: number) {
        return (
            this.failed.has(collectionId) &&
            requestKey !== undefined &&
            requestKey !== this.failed.get(collectionId)
        );
    }

    indexActivity(
        collectionId: string,
        requestKey?: number,
    ): NotesIndexActivity {
        if (
            this.failed.has(collectionId) &&
            !this.hasNewerUpdate(collectionId, requestKey)
        )
            return "failed";
        if (this.queued.has(collectionId)) return "queued";
        return this.activeCollectionId === collectionId ? "starting" : null;
    }

    isManualUpdateRequested(collectionId: string) {
        return this.queued.get(collectionId) === true;
    }

    discardQueuedAutomaticIndex(collectionId: string) {
        if (this.queued.get(collectionId) !== false) return false;
        return this.queued.delete(collectionId);
    }

    takeNextQueued(blocked: boolean, manualBlocked = blocked) {
        if (this.disposed || this.hasActiveJobs()) return;
        let next: [string, boolean] | undefined;
        for (const request of this.queued) {
            const [collectionId, force] = request;
            if (
                (force ? manualBlocked : blocked) ||
                this.removing.has(collectionId)
            ) {
                continue;
            }
            next ??= request;
            if (force) {
                next = request;
                break;
            }
        }
        if (next) this.queued.delete(next[0]);
        return next;
    }

    beginRemoval(collectionId: string): NotesRemovalStart {
        if (this.activeCollectionId === collectionId) {
            this.removalWaitCollection = collectionId;
            return { kind: "wait" };
        }
        const queuedForce = this.queued.get(collectionId);
        this.queued.delete(collectionId);
        this.removing.add(collectionId);
        return { kind: "start", queuedForce };
    }

    cancelRemoval(collectionId: string) {
        this.removing.delete(collectionId);
    }

    finishRemoval(collectionId: string) {
        this.removing.delete(collectionId);
        this.failed.delete(collectionId);
        if (this.removalWaitCollection === collectionId) {
            this.removalWaitCollection = null;
        }
    }

    isRemoving(collectionId: string) {
        return this.removing.has(collectionId);
    }

    hasActiveJobs() {
        return this.activeCollectionId !== null;
    }

    markMutation() {
        this.mutation += 1;
    }

    beginRefresh() {
        this.refreshRequest += 1;
        return this.refreshRequest;
    }

    refreshMutationSnapshot() {
        return this.mutation;
    }

    isRefreshCurrent(request: number) {
        return !this.disposed && request === this.refreshRequest;
    }

    canApplyRefresh(request: number, mutation: number) {
        return this.isRefreshCurrent(request) && mutation === this.mutation;
    }

    cancelRefreshes() {
        this.refreshRequest += 1;
    }

    activate() {
        this.disposed = false;
    }

    dispose() {
        this.disposed = true;
        this.activeCollectionId = null;
        this.queued.clear();
        this.failed.clear();
        this.removing.clear();
        this.cancelRefreshes();
    }
}

export const notesCollectionActivity = (
    collection: NotesCollection,
    controller: NotesLifecycleController,
    modelReady: boolean,
    indexingPaused: boolean,
    chatBusy: boolean,
): NotesCollectionActivity => {
    if (collection.status === "indexing" || collection.status === "updating") {
        return null;
    }
    const requestKey = collection.updateDueAtMs ?? undefined;
    const activity = controller.indexActivity(collection.id, requestKey);
    if (activity === "failed" || activity === "starting") return activity;
    if (controller.isManualUpdateRequested(collection.id)) {
        return "updateRequested";
    }
    if (collection.status === "unavailable") return null;
    if (
        collection.updateDueAtMs != null &&
        (collection.status === "ready" ||
            (collection.status === "pending" &&
                collection.lastUpdatedAtMs != null) ||
            ((activity === "queued" ||
                controller.hasNewerUpdate(collection.id, requestKey)) &&
                collection.lastUpdatedAtMs != null))
    ) {
        return "updateScheduled";
    }
    if (activity !== "queued" && collection.updateDueAtMs != null) return null;
    if (activity !== "queued" && collection.status !== "pending") return null;
    if (!modelReady) return "waitingForModel";
    if (chatBusy) return "waitingForGeneration";
    if (indexingPaused) return "waitingForChat";
    return "starting";
};
