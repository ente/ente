import assert from "node:assert/strict";
import { test } from "node:test";
import { abortable } from "../src/services/abortable.ts";
import { ModelOperationQueue } from "../src/services/llm/model-operation-queue.ts";

const deferred = () => {
    let resolve: () => void = () => undefined;
    const promise = new Promise<void>((done) => {
        resolve = done;
    });
    return { promise, resolve };
};
const tick = () => new Promise<void>((resolve) => setImmediate(resolve));

void test("cancelling queued dictation returns before indexing finishes without letting later work overtake it", async () => {
    const queue = new ModelOperationQueue();
    const indexer = deferred();
    const indexing = queue.run(() => indexer.promise);
    const abort = new AbortController();
    const voice = queue.run(() => {
        assert.fail("cancelled dictation must not request microphone access");
    }, abort.signal);
    const cancelled = assert.rejects(voice, { name: "AbortError" });
    let nextStarted = false;
    const next = queue.run(() => {
        nextStarted = true;
        return Promise.resolve();
    });
    abort.abort();
    await cancelled;
    await tick();
    assert.equal(nextStarted, false);
    indexer.resolve();
    await Promise.all([indexing, next]);
    assert.equal(nextStarted, true);
});

void test("cancellation at queue handoff prevents a late microphone start", async () => {
    const queue = new ModelOperationQueue();
    const abort = new AbortController();
    const voice = queue.run(() => {
        assert.fail("must recheck cancellation after the wait");
    }, abort.signal);
    abort.abort();
    await assert.rejects(voice, { name: "AbortError" });
    assert.equal(await queue.run(() => Promise.resolve("retry")), "retry");
});

void test("failed dictation releases model ownership only after capture and decoder cleanup finish", async () => {
    const queue = new ModelOperationQueue();
    const cleanedUp = deferred();
    const abort = new AbortController();
    const voice = queue.run(async () => {
        await cleanedUp.promise;
        throw new Error("failed");
    }, abort.signal);
    const failed = assert.rejects(voice, /failed/);
    await tick();
    let nextStarted = false;
    const next = queue.run(() => {
        nextStarted = true;
        return Promise.resolve();
    });
    abort.abort();
    await tick();
    assert.equal(nextStarted, false);
    cleanedUp.resolve();
    await Promise.all([failed, next]);
    assert.equal(nextStarted, true);
});

void test("abortable initialization stops waiting and observes a later failure", async () => {
    const abort = new AbortController();
    let reject: (error: Error) => void = () => undefined;
    const preparing = new Promise<void>((_, fail) => {
        reject = fail;
    });
    const waiting = abortable(preparing, abort.signal);
    abort.abort();
    await assert.rejects(waiting, { name: "AbortError" });
    reject(new Error("initialization failed after cancellation"));
    await tick();
    await assert.rejects(abortable(Promise.resolve(), abort.signal), {
        name: "AbortError",
    });
});
