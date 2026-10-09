import type { NotesCollection } from "@/services/notes";

type NotesIndexRequest = "start" | "queued" | "ignored";

interface NotesIndexCompletion {
    clearedRemovalWait: boolean;
}

type NotesIndexActivity = "starting" | "queued" | "failed" | null;

export type NotesCollectionActivity =
    "starting" | "waitingForGeneration" | "waitingForModel" | "failed" | null;

export interface NotesCollectionView extends NotesCollection {
    activity: NotesCollectionActivity;
}

type NotesRemovalStart =
    { kind: "wait" } | { kind: "start"; queuedForce?: boolean };

export class NotesLifecycleController {
    private readonly active = new Set<string>();
    private readonly queued = new Map<string, boolean>();
    private readonly failed = new Set<string>();
    private readonly automaticRequestKeys = new Map<string, number>();
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
        if (this.disposed || this.removing.has(collectionId)) return "ignored";
        this.failed.delete(collectionId);
        if (
            blocked ||
            this.active.has(collectionId) ||
            this.queued.has(collectionId)
        ) {
            this.queueIndex(collectionId, force);
            return "queued";
        }
        this.active.add(collectionId);
        return "start";
    }

    ensureIndex(
        collectionId: string,
        blocked: boolean,
        requestKey?: number,
    ): NotesIndexRequest {
        if (
            this.disposed ||
            this.removing.has(collectionId) ||
            this.active.has(collectionId) ||
            this.queued.has(collectionId)
        ) {
            return "ignored";
        }
        if (
            this.failed.has(collectionId) &&
            (requestKey === undefined ||
                this.automaticRequestKeys.get(collectionId) === requestKey)
        ) {
            return "ignored";
        }
        if (requestKey !== undefined) {
            this.automaticRequestKeys.set(collectionId, requestKey);
            this.failed.delete(collectionId);
        }
        if (blocked) {
            this.queueIndex(collectionId, false);
            return "queued";
        }
        this.active.add(collectionId);
        return "start";
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
            this.active.has(collectionId) &&
            !this.removing.has(collectionId)
        );
    }

    finishIndex(collectionId: string): NotesIndexCompletion {
        this.active.delete(collectionId);
        const clearedRemovalWait = this.removalWaitCollection === collectionId;
        if (clearedRemovalWait) this.removalWaitCollection = null;
        return { clearedRemovalWait };
    }

    failIndex(collectionId: string) {
        this.queued.delete(collectionId);
        this.failed.add(collectionId);
    }

    indexActivity(collectionId: string): NotesIndexActivity {
        if (this.failed.has(collectionId)) return "failed";
        if (this.queued.has(collectionId)) return "queued";
        return this.active.has(collectionId) ? "starting" : null;
    }

    drainQueued(blocked: boolean) {
        if (this.disposed || blocked) return [] as [string, boolean][];
        const ready: [string, boolean][] = [];
        for (const [collectionId, force] of this.queued) {
            if (
                this.active.has(collectionId) ||
                this.removing.has(collectionId)
            ) {
                continue;
            }
            this.queued.delete(collectionId);
            ready.push([collectionId, force]);
        }
        return ready;
    }

    beginRemoval(collectionId: string): NotesRemovalStart {
        if (this.active.has(collectionId)) {
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
        this.automaticRequestKeys.delete(collectionId);
        if (this.removalWaitCollection === collectionId) {
            this.removalWaitCollection = null;
        }
    }

    isRemoving(collectionId: string) {
        return this.removing.has(collectionId);
    }

    hasActiveJobs() {
        return this.active.size > 0;
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
        this.active.clear();
        this.queued.clear();
        this.failed.clear();
        this.automaticRequestKeys.clear();
        this.removing.clear();
        this.cancelRefreshes();
    }
}
