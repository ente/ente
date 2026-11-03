import assert from "node:assert/strict";
import { test } from "node:test";
import type { MicrophoneFactory } from "../src/services/voice-microphone.ts";
import {
    DesktopDictation,
    type VoiceEvent,
    type VoiceOutcome,
    type VoiceTransport,
} from "../src/services/voice.ts";

const deferred = <T>() => {
    let resolve!: (value: T) => void;
    let reject!: (error: Error) => void;
    const promise = new Promise<T>((yes, no) => {
        resolve = yes;
        reject = no;
    });
    return { promise, resolve, reject };
};

function harness(microphone?: MicrophoneFactory) {
    const created = deferred<string>();
    const outcome = deferred<VoiceOutcome>();
    const calls: { command: string; args?: Record<string, unknown> }[] = [];
    let listener: ((event: VoiceEvent) => void) | undefined;
    let unlistened = false;
    const transport: VoiceTransport = {
        invoke: async <T>(command: string, args?: Record<string, unknown>) => {
            calls.push({ command, args });
            if (command === "voice_create") return (await created.promise) as T;
            if (command === "voice_run") return (await outcome.promise) as T;
            return undefined as T;
        },
        sendAudio: () => Promise.resolve(true),
        listen: (callback) => {
            listener = callback;
            return Promise.resolve(() => {
                unlistened = true;
            });
        },
    };
    return {
        session: new DesktopDictation(
            transport,
            microphone ??
                (() => ({
                    sampleRate: 48000,
                    prepare: () => Promise.resolve(),
                    start: () => Promise.resolve(),
                    finish: () => Promise.resolve(),
                    close: () => undefined,
                })),
        ),
        created,
        outcome,
        calls,
        capture: (id: string, running: boolean) =>
            listener?.({ type: "capture", id, running }),
        emit: (id: string) =>
            listener?.({
                type: "progress",
                id,
                percent: 30,
                status: "Downloading",
            }),
        unlistened: () => unlistened,
    };
}
const tick = () => new Promise<void>((resolve) => setImmediate(resolve));

void test("cancellation before or during native creation never starts capture", async () => {
    const beforeStart = harness();
    await beforeStart.session.cancel();
    assert.equal(await beforeStart.session.run(() => undefined), undefined);
    assert.equal(beforeStart.calls.length, 0);

    const h = harness();
    const run = h.session.run(() => assert.fail("cancelled event"));
    await tick();
    await h.session.cancel();
    h.created.resolve("first");
    assert.equal(await run, undefined);
    assert.deepEqual(
        h.calls.map((c) => c.command),
        ["voice_create", "voice_stop"],
    );
    assert.deepEqual(h.calls[1]?.args, { id: "first", discard: true });
    assert(h.unlistened());
});

void test("native failures stop the session and remove its listener", async () => {
    const h = harness();
    const run = h.session.run(() => undefined);
    h.created.resolve("failed");
    await tick();
    h.outcome.reject(new Error("Transcription failed"));
    await assert.rejects(run, /Transcription failed/);
    assert(h.unlistened());
    assert.deepEqual(h.calls.at(-1), {
        command: "voice_stop",
        args: { id: "failed", discard: true },
    });
});

void test("Stop drains audio and ignores callbacks from other attempts", async () => {
    const flushed = deferred<undefined>();
    let started = 0;
    const h = harness(() => ({
        sampleRate: 48000,
        prepare: () => Promise.resolve(),
        start: () => {
            started++;
            return Promise.resolve();
        },
        finish: () => flushed.promise,
        close: () => undefined,
    }));
    const seen: string[] = [];
    const run = h.session.run((e) => seen.push(e.id));
    h.created.resolve("stream");
    await tick();
    h.emit("old");
    h.emit("stream");
    assert.deepEqual(seen, ["stream"]);
    assert.equal(h.session.hasStarted, false);
    h.capture("old", true);
    h.capture("stream", true);
    h.capture("stream", true);
    await tick();
    assert.equal(started, 1);
    assert.equal(h.session.hasStarted, true);
    const stop = h.session.finish();
    assert.equal(h.session.finish(), stop);
    await tick();
    assert(!h.calls.some((c) => c.command === "voice_stop"));
    flushed.resolve(undefined);
    await stop;
    assert.deepEqual(h.calls.at(-1)?.args, { id: "stream", discard: false });
    assert.equal(h.unlistened(), false);
    h.outcome.resolve({ text: "including the tail", incomplete: false });
    assert.equal((await run)?.text, "including the tail");
    assert(h.unlistened());
    await assert.rejects(
        h.session.run(() => undefined),
        /already started/,
    );
});

void test("Cancel during a pending flush closes capture immediately and never finalizes", async () => {
    const flushed = deferred<undefined>();
    let closed = false;
    const h = harness(() => ({
        sampleRate: 48000,
        prepare: () => Promise.resolve(),
        start: () => Promise.resolve(),
        finish: () => flushed.promise,
        close: () => {
            closed = true;
        },
    }));
    let changes = 0;
    const run = h.session.run(() => changes++);
    h.created.resolve("stream");
    await tick();
    h.capture("stream", true);
    const stop = h.session.finish();
    await tick();
    await h.session.cancel();
    assert(closed);
    h.emit("stream");
    flushed.resolve(undefined);
    await stop;
    assert(
        !h.calls.some(
            (c) => c.command === "voice_stop" && c.args?.discard === false,
        ),
    );
    h.outcome.resolve({ text: "discarded", incomplete: false });
    assert.equal(await run, undefined);
    assert.equal(changes, 0);
    assert(h.unlistened());
});

void test("capture failure lets native decoding return an incomplete transcript", async () => {
    let fail!: (error: Error) => void;
    const h = harness((_, failed) => {
        fail = failed;
        return {
            sampleRate: 48000,
            prepare: () => Promise.resolve(),
            start: () => Promise.resolve(),
            finish: () => Promise.resolve(),
            close: () => undefined,
        };
    });
    const run = h.session.run(() => undefined);
    h.created.resolve("stream");
    await tick();
    fail(new Error("disconnected"));
    await tick();
    assert.equal(h.calls.at(-1)?.command, "voice_capture_failed");
    h.outcome.resolve({ text: "partial", incomplete: true });
    assert.deepEqual(await run, { text: "partial", incomplete: true });
});
