import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test, type TestContext } from "node:test";
import vm from "node:vm";
import { createMicrophone } from "../src/services/voice-microphone.ts";

interface WorkletMessage {
    pcm?: ArrayBuffer;
    error?: string;
    flushed?: boolean;
}

function worklet(deliver?: (message: WorkletMessage) => void) {
    const messages: WorkletMessage[] = [];
    let Processor!: new () => {
        port: { onmessage: (e: { data: string }) => void };
        process: (inputs: Float32Array[][]) => boolean;
    };
    vm.runInNewContext(
        readFileSync(
            new URL("../public/voice-capture-worklet.js", import.meta.url),
            "utf8",
        ),
        {
            sampleRate: 48000,
            AudioWorkletProcessor: class {
                port = {
                    postMessage: (message: WorkletMessage) => {
                        messages.push(message);
                        deliver?.(message);
                    },
                };
            },
            registerProcessor: (_: string, ctor: typeof Processor) => {
                Processor = ctor;
            },
        },
    );
    const processor = new Processor();
    return {
        messages,
        command: (data: string) => processor.port.onmessage({ data }),
        feed: (samples: Float32Array) => processor.process([[samples]]),
    };
}

function mockAudioInput(t: TestContext, respondsToFinish = true) {
    const track = { onended: () => assert.fail(), stop: () => undefined };
    const getTracks = () => [track];
    let receive!: (event: { data: WorkletMessage }) => void;
    const w = worklet((data) => receive({ data }));
    const audioNode = { connect: () => undefined, disconnect: () => undefined };
    const globals = {
        navigator: {
            mediaDevices: {
                getUserMedia: () =>
                    Promise.resolve({ getTracks, getAudioTracks: getTracks }),
            },
        },
        AudioContext: class {
            state = "running";
            audioWorklet = { addModule: () => Promise.resolve() };
            suspend = () => Promise.resolve();
            resume = () => Promise.resolve();
            close = () => Promise.resolve();
            createMediaStreamSource = () => audioNode;
        },
        AudioWorkletNode: class {
            connect = audioNode.connect;
            disconnect = audioNode.disconnect;
            port = {
                set onmessage(listener: typeof receive) {
                    receive = listener;
                },
                postMessage: (command: string) => {
                    if (command !== "finish" || respondsToFinish)
                        w.command(command);
                },
                close: () => undefined,
            };
        },
    };
    for (const [key, value] of Object.entries(globals)) {
        const original = Object.getOwnPropertyDescriptor(globalThis, key);
        Object.defineProperty(globalThis, key, { configurable: true, value });
        t.after(() => {
            if (original) Object.defineProperty(globalThis, key, original);
            else Reflect.deleteProperty(globalThis, key);
        });
    }
    return { track, feed: w.feed };
}

void test("microphone disconnect reports immediately during preparation and drains captured samples while recording", async (t) => {
    const { track, feed } = mockAudioInput(t);
    const failure = "The microphone disconnected.";
    const failures: string[] = [];
    const failed = (error: Error) => failures.push(error.message);
    const signal = new AbortController().signal;
    const preparing = createMicrophone(() => assert.fail(), failed);
    await preparing.prepare(signal);
    track.onended();
    assert.deepEqual(failures, [failure]);

    const received: number[] = [];
    let acknowledge!: () => void;
    const firstSend = new Promise<void>((resolve) => {
        acknowledge = resolve;
    });
    let report!: (error: Error) => void;
    const reported = new Promise<Error>((resolve) => {
        report = resolve;
    });
    const recording = createMicrophone(
        async (sequence, pcm) => {
            assert.equal(sequence, received.length);
            if (sequence === 0) await firstSend;
            received.push(pcm.byteLength / 2);
            return true;
        },
        (error) => {
            failed(error);
            report(error);
        },
    );
    await recording.prepare(signal);
    await recording.start();
    feed(new Float32Array(20 * 4800 + 1200));
    await new Promise<void>((resolve) => setImmediate(resolve));
    track.onended();
    assert.deepEqual(failures, [failure]);
    acknowledge();
    assert.equal((await reported).message, failure);
    assert.deepEqual(received, [...Array<number>(20).fill(4800), 1200]);
    assert.deepEqual(failures, [failure, failure]);
});

void test("a worklet that misses the flush deadline gets one bounded wait for queued sends", async (t) => {
    const { track, feed } = mockAudioInput(t, false);
    t.mock.timers.enable({ apis: ["setTimeout"] });
    const tick = () => new Promise<void>((resolve) => setImmediate(resolve));
    const sends: number[] = [];
    const failures: string[] = [];
    let acknowledge!: (accepted: boolean) => void;
    const capture = createMicrophone(
        (sequence) => {
            sends.push(sequence);
            return new Promise((resolve) => {
                acknowledge = resolve;
            });
        },
        (error) => failures.push(error.message),
    );
    await capture.prepare(new AbortController().signal);
    await capture.start();
    feed(new Float32Array(3 * 4800));
    track.onended();
    await tick();
    t.mock.timers.tick(2000);
    await tick();
    acknowledge(true);
    await tick();
    assert.deepEqual(sends, [0, 1]);

    t.mock.timers.tick(2000);
    await tick();
    assert.deepEqual(failures, ["The microphone disconnected."]);
});

void test("worklet preserves final partial PCM, clips samples, and encodes little-endian", () => {
    const w = worklet();
    w.feed(new Float32Array([1]));
    assert.equal(w.messages.length, 0);
    w.command("start");
    w.feed(new Float32Array([-1, 1, 0.5, -0.5, NaN, Infinity, 2]));
    assert.equal(w.messages.length, 0);
    w.command("finish");
    const pcm = new DataView(w.messages[0]!.pcm!);
    assert.deepEqual(
        Array.from({ length: pcm.byteLength / 2 }, (_, i) =>
            pcm.getInt16(i * 2, true),
        ),
        [-32768, 32767, 16384, -16384, 0, 0, 32767],
    );
    assert.equal(w.messages[1]!.flushed, true);
    w.feed(new Float32Array(4800));
    assert.equal(w.messages.length, 2);
});

void test("worklet bounds unacknowledged audio and permits sustained acknowledged capture", () => {
    for (const acknowledge of [false, true]) {
        const w = worklet();
        w.command("start");
        for (let i = 0; i < 50; i++) {
            w.feed(new Float32Array(4800));
            if (acknowledge) w.command("ack");
        }
        assert.equal(
            w.messages.filter((m) => m.pcm).length,
            acknowledge ? 50 : 20,
        );
        assert.equal(
            w.messages.filter((m) => m.error).length,
            acknowledge ? 0 : 1,
        );
    }
});
