import assert from "node:assert/strict";
import test from "node:test";
import {
    NotesLifecycleController,
    notesCollectionActivity,
} from "../src/services/notes-lifecycle.ts";
import type { NotesCollection } from "../src/services/notes.ts";

const folder: NotesCollection = {
    id: "notes",
    label: "Notes",
    status: "ready",
    indexingProgress: null,
    indexedDocumentCount: 3,
    lastUpdatedAtMs: 100,
    updateDueAtMs: 300_000,
    lastError: null,
    watcherError: null,
};

const activity = (
    controller: NotesLifecycleController,
    changes: Partial<NotesCollection> = {},
) =>
    notesCollectionActivity(
        { ...folder, ...changes },
        controller,
        false,
        true,
        true,
    );

void test("manual updates coalesce, precede automatic work, and survive cancellation", () => {
    const controller = new NotesLifecycleController();
    controller.ensureIndex("automatic", true);
    controller.ensureIndex(folder.id, true);
    assert.equal(activity(controller), "updateScheduled");
    for (let tap = 0; tap < 3; tap++) {
        assert.equal(controller.requestIndex(folder.id, true, false), "queued");
    }
    assert.equal(activity(controller), "updateRequested");
    controller.ensureIndex("lateAutomatic", true);
    assert.equal(controller.takeNextQueued(true, true), undefined);
    assert.deepEqual(controller.takeNextQueued(true, false), [folder.id, true]);
    assert.equal(controller.requestIndex(folder.id, true, false), "start");
    assert.equal(activity(controller), "starting");
    assert.equal(controller.requestIndex(folder.id, true, false), "ignored");
    controller.finishIndex(folder.id);
    assert.equal(controller.takeNextQueued(true, false), undefined);
    controller.requestIndex(folder.id, true, false);
    controller.queueIndex(folder.id, true);
    controller.queueIndex(folder.id, false);
    controller.finishIndex(folder.id);
    assert.deepEqual(controller.takeNextQueued(true, false), [folder.id, true]);
    controller.requestIndex(folder.id, true, false);
    controller.finishIndex(folder.id);
    assert.deepEqual(controller.takeNextQueued(false), ["automatic", false]);
    assert.deepEqual(controller.takeNextQueued(false), [
        "lateAutomatic",
        false,
    ]);
    assert.equal(controller.takeNextQueued(false), undefined);
});

void test("failed versions require Retry; newer changes resume automatically", () => {
    const controller = new NotesLifecycleController();
    const key = folder.updateDueAtMs!;
    controller.requestIndex(folder.id, true, false);
    controller.failIndex(folder.id, key);
    controller.finishIndex(folder.id);
    assert.equal(controller.ensureIndex(folder.id, false), "ignored");
    assert.equal(controller.ensureIndex(folder.id, false, key), "ignored");
    assert.equal(activity(controller), "failed");
    assert.equal(controller.requestIndex(folder.id, true, true), "queued");
    assert.equal(activity(controller, { status: "error" }), "updateRequested");
    assert.deepEqual(controller.takeNextQueued(true, false), [folder.id, true]);
    controller.requestIndex(folder.id, true, false);
    controller.failIndex(folder.id, key);
    controller.finishIndex(folder.id);

    const newer = { status: "error" as const, updateDueAtMs: key + 1 };
    assert.equal(activity(controller, newer), "updateScheduled");
    assert.equal(controller.ensureIndex(folder.id, true, key + 1), "queued");
    assert.equal(activity(controller, newer), "updateScheduled");
    assert.equal(controller.takeNextQueued(true, false), undefined);
    assert.equal(controller.requestIndex(folder.id, true, true), "queued");
    assert.equal(activity(controller, newer), "updateRequested");
    assert.deepEqual(controller.takeNextQueued(true, false), [folder.id, true]);
    controller.requestIndex(folder.id, true, false);
    controller.failIndex(folder.id, key + 1);
    controller.finishIndex(folder.id);
    assert.equal(controller.ensureIndex(folder.id, false, key + 1), "ignored");
    assert.equal(controller.ensureIndex(folder.id, false, key + 2), "start");
});

void test("unavailable sources drop automatic work but retain explicit requests", () => {
    for (const manual of [false, true]) {
        const controller = new NotesLifecycleController();
        controller.ensureIndex(folder.id, true, folder.updateDueAtMs!);
        if (manual) controller.requestIndex(folder.id, true, true);
        assert.equal(
            activity(controller, { status: "unavailable" }),
            manual ? "updateRequested" : null,
        );
        assert.equal(
            controller.discardQueuedAutomaticIndex(folder.id),
            !manual,
        );
        assert.deepEqual(
            controller.takeNextQueued(false),
            manual ? [folder.id, true] : undefined,
        );
    }

    const controller = new NotesLifecycleController();
    controller.requestIndex(folder.id, true, false);
    controller.failIndex(folder.id, folder.updateDueAtMs!);
    controller.finishIndex(folder.id);
    const updateDueAtMs = folder.updateDueAtMs! + 1;
    assert.equal(
        activity(controller, { status: "unavailable", updateDueAtMs }),
        null,
    );
    assert.equal(activity(controller, { updateDueAtMs }), "updateScheduled");
});

void test("current, initial, and actively indexing folders do not offer Update now", () => {
    const controller = new NotesLifecycleController();
    for (const changes of [
        { updateDueAtMs: null },
        { status: "pending" as const, lastUpdatedAtMs: null },
        { status: "error" as const },
        { status: "indexing" as const },
        { status: "updating" as const },
    ]) {
        assert.equal(activity(controller, changes), null);
    }
});
