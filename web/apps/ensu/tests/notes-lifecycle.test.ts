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

void test("detected updates can be requested while a reply is running", () => {
    const controller = new NotesLifecycleController();
    assert.equal(
        notesCollectionActivity(folder, controller, true, true, true),
        "updateScheduled",
    );
    for (let tap = 0; tap < 3; tap++) {
        assert.equal(controller.requestIndex(folder.id, true, true), "queued");
    }
    assert.equal(
        notesCollectionActivity(folder, controller, false, true, true),
        "updateRequested",
    );
    assert.equal(controller.takeNextQueued(true, true), undefined);
    assert.deepEqual(controller.takeNextQueued(true, false), [folder.id, true]);
    assert.equal(controller.takeNextQueued(true, false), undefined);
    assert.equal(controller.requestIndex(folder.id, true, false), "start");
    assert.equal(
        notesCollectionActivity(folder, controller, true, true, false),
        "starting",
    );
    controller.finishIndex(folder.id);
    assert.equal(
        notesCollectionActivity(
            { ...folder, updateDueAtMs: null },
            controller,
            true,
            false,
            false,
        ),
        null,
    );
});

void test("manual updates stay queued and run before waiting automatic folders", () => {
    const controller = new NotesLifecycleController();
    assert.equal(controller.ensureIndex("running", false), "start");
    assert.equal(controller.ensureIndex("automatic", false), "queued");
    assert.equal(controller.ensureIndex(folder.id, false), "queued");
    assert.equal(controller.requestIndex(folder.id, true, false), "queued");
    assert.equal(
        notesCollectionActivity(folder, controller, true, false, false),
        "updateRequested",
    );
    assert.equal(controller.takeNextQueued(false), undefined);
    controller.finishIndex("running");
    assert.equal(controller.ensureIndex("lateAutomatic", false), "queued");
    assert.deepEqual(controller.takeNextQueued(false), [folder.id, true]);
    assert.equal(controller.requestIndex(folder.id, true, false), "start");
    assert.equal(controller.takeNextQueued(false), undefined);
    controller.finishIndex(folder.id);
    assert.deepEqual(controller.takeNextQueued(false), ["automatic", false]);
});

void test("cancellation preserves manual intent without starting a duplicate", () => {
    const controller = new NotesLifecycleController();
    assert.equal(controller.requestIndex(folder.id, true, false), "start");
    controller.queueIndex(folder.id, true);
    controller.queueIndex(folder.id, false);
    assert.equal(controller.takeNextQueued(false), undefined);
    controller.finishIndex(folder.id);
    assert.deepEqual(controller.takeNextQueued(true, false), [folder.id, true]);
});

void test("failure requires a retry and retry can still bypass the idle delay", () => {
    for (const manual of [false, true]) {
        const controller = new NotesLifecycleController();
        if (manual) controller.requestIndex(folder.id, true, false);
        else controller.ensureIndex(folder.id, false);
        controller.failIndex(folder.id);
        controller.finishIndex(folder.id);
        assert.equal(controller.ensureIndex(folder.id, false), "ignored");
        assert.equal(
            notesCollectionActivity(folder, controller, true, true, false),
            "failed",
        );
        controller.requestIndex(folder.id, true, true);
        assert.equal(
            notesCollectionActivity(
                { ...folder, status: "error" },
                controller,
                true,
                true,
                true,
            ),
            "updateRequested",
        );
        assert.deepEqual(controller.takeNextQueued(true, false), [
            folder.id,
            true,
        ]);
    }
});

void test("initial indexing and unavailable folders do not offer Update now", () => {
    const controller = new NotesLifecycleController();
    for (const collection of [
        { ...folder, status: "pending" as const, lastUpdatedAtMs: null },
        { ...folder, status: "unavailable" as const },
        { ...folder, status: "error" as const },
        { ...folder, status: "updating" as const },
    ]) {
        assert.notEqual(
            notesCollectionActivity(collection, controller, true, false, false),
            "updateScheduled",
        );
    }
});
