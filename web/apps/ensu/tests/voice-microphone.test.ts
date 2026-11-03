import assert from "node:assert/strict";
import { test } from "node:test";
import { createMicrophone } from "../src/services/voice-microphone.ts";

void test("microphone setup explains capture errors and cancels pending permission without leaking a stream", async () => {
    const navigator = Object.getOwnPropertyDescriptor(globalThis, "navigator");
    const worklet = Object.getOwnPropertyDescriptor(
        globalThis,
        "AudioWorkletNode",
    );
    let grant!: (stream: MediaStream) => void;
    const permission = new Promise<MediaStream>((resolve) => {
        grant = resolve;
    });
    let requestMicrophone = () => permission;
    Object.defineProperty(globalThis, "navigator", {
        configurable: true,
        value: {
            mediaDevices: {
                getUserMedia: (constraints: MediaStreamConstraints) => {
                    assert.deepEqual(constraints, {
                        audio: {
                            echoCancellation: { ideal: false },
                            noiseSuppression: { ideal: false },
                            autoGainControl: { ideal: false },
                        },
                        video: false,
                    });
                    return requestMicrophone();
                },
            },
        },
    });
    Object.defineProperty(globalThis, "AudioWorkletNode", {
        configurable: true,
        value: function () {
            throw new Error(
                "Worklet must not start before permission is granted",
            );
        },
    });
    try {
        for (const [name, message] of [
            ["OverconstrainedError", /No usable microphone/],
            ["NotFoundError", /No usable microphone/],
            ["NotAllowedError", /Microphone access was denied/],
            ["NotReadableError", /Hardware error/],
        ] as const) {
            requestMicrophone = () =>
                Promise.reject(
                    Object.assign(
                        new Error(
                            name === "OverconstrainedError"
                                ? "Invalid constraint"
                                : "Hardware error",
                        ),
                        { name },
                    ),
                );
            const capture = createMicrophone(
                () => assert.fail("must not send audio"),
                () => assert.fail("setup errors must reject prepare"),
            );
            await assert.rejects(
                capture.prepare(new AbortController().signal),
                { message },
            );
        }
        requestMicrophone = () => permission;
        let stopped = 0;
        const capture = createMicrophone(
            () => {
                assert.fail("must not send audio");
            },
            () => {
                assert.fail("cancel is not failure");
            },
        );
        const abort = new AbortController();
        const preparing = capture.prepare(abort.signal);
        abort.abort();
        await assert.rejects(preparing, { name: "AbortError" });
        grant({
            getTracks: () => [
                {
                    stop: () => {
                        stopped++;
                    },
                },
            ],
        } as unknown as MediaStream);
        await new Promise((resolve) => setImmediate(resolve));
        assert.equal(stopped, 1);
        capture.close();
        assert.equal(stopped, 1);
    } finally {
        if (navigator)
            Object.defineProperty(globalThis, "navigator", navigator);
        else Reflect.deleteProperty(globalThis, "navigator");
        if (worklet)
            Object.defineProperty(globalThis, "AudioWorkletNode", worklet);
        else Reflect.deleteProperty(globalThis, "AudioWorkletNode");
    }
});
