import assert from "node:assert/strict";
import test from "node:test";
import { NotesIndexingIdleScheduler } from "../src/services/notes-indexing-idle.ts";

const makeClock = () => {
    let now = 0;
    let nextId = 0;
    const pending = new Map<number, { at: number; run: () => void }>();
    const callbacks: (() => void)[] = [];
    return {
        timers: {
            schedule: (run: () => void, delayMs: number) => {
                const id = ++nextId;
                pending.set(id, { at: now + delayMs, run });
                callbacks.push(run);
                return id;
            },
            cancel: (id: number) => {
                pending.delete(id);
            },
        },
        callbacks,
        advance: (elapsedMs: number) => {
            const end = now + elapsedMs;
            while (true) {
                const next = [...pending].sort(
                    ([, a], [, b]) => a.at - b.at,
                )[0];
                if (!next || next[1].at > end) break;
                const [id, task] = next;
                pending.delete(id);
                now = task.at;
                task.run();
            }
            now = end;
        },
    };
};

void test("indexing resumes once after the restored chat has 30 quiet seconds", () => {
    const clock = makeClock();
    let resumed = 0;
    const scheduler = new NotesIndexingIdleScheduler(
        () => resumed++,
        () => false,
        clock.timers,
    );
    scheduler.defer();
    clock.advance(29_999);
    assert.equal(resumed, 0);
    clock.advance(1);
    assert.equal(resumed, 1);
    clock.advance(60_000);
    assert.equal(resumed, 1);
});

void test("typing or sending restarts the pending quiet period", () => {
    const clock = makeClock();
    let resumed = 0;
    const scheduler = new NotesIndexingIdleScheduler(
        () => resumed++,
        () => false,
        clock.timers,
    );
    scheduler.defer();
    clock.advance(20_000);
    scheduler.activity();
    clock.advance(29_999);
    assert.equal(resumed, 0);
    clock.advance(1);
    assert.equal(resumed, 1);
});

void test("a busy chat defers indexing until a later idle check", () => {
    const clock = makeClock();
    let busy = true;
    let resumed = 0;
    const scheduler = new NotesIndexingIdleScheduler(
        () => resumed++,
        () => busy,
        clock.timers,
    );
    scheduler.defer();
    clock.advance(90_000);
    assert.equal(resumed, 0);
    busy = false;
    clock.advance(30_000);
    assert.equal(resumed, 1);
});

void test("reopening Notes resumes immediately and invalidates stale callbacks", () => {
    const clock = makeClock();
    let resumed = 0;
    const scheduler = new NotesIndexingIdleScheduler(
        () => resumed++,
        () => false,
        clock.timers,
    );
    scheduler.defer();
    const staleCallback = clock.callbacks[0];
    assert.ok(staleCallback);
    scheduler.resumeNow();
    assert.equal(resumed, 1);
    staleCallback();
    clock.advance(60_000);
    assert.equal(resumed, 1);
});

void test("unmount or another warmup cancels the previous pending resumption", () => {
    const clock = makeClock();
    let resumed = 0;
    const scheduler = new NotesIndexingIdleScheduler(
        () => resumed++,
        () => false,
        clock.timers,
    );
    scheduler.defer();
    scheduler.cancel();
    clock.advance(60_000);
    assert.equal(resumed, 0);
    scheduler.defer();
    clock.advance(30_000);
    assert.equal(resumed, 1);
});
