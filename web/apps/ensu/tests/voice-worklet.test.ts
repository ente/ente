import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

function worklet() {
    const messages: { pcm?: ArrayBuffer; error?: string; flushed?: boolean }[] =
        [];
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
                    postMessage: (message: (typeof messages)[number]) =>
                        messages.push(message),
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
