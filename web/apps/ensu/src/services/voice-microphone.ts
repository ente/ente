import { abortable } from "./abortable.ts";

export interface MicrophoneCapture {
    readonly sampleRate: number;
    prepare: (signal: AbortSignal) => Promise<void>;
    start: () => Promise<void>;
    finish: () => Promise<void>;
    close: () => void;
}

export type MicrophoneFactory = (
    send: (sequence: number, pcm: ArrayBuffer) => Promise<boolean>,
    failed: (error: Error) => void,
) => MicrophoneCapture;

const FLUSH_TIMEOUT_MS = 2000;

const timeout = async <T>(operation: Promise<T>, ms: number): Promise<T> => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
        return await Promise.race([
            operation,
            new Promise<never>((_, reject) => {
                timer = setTimeout(
                    () =>
                        reject(
                            new Error("Microphone audio delivery timed out."),
                        ),
                    ms,
                );
            }),
        ]);
    } finally {
        clearTimeout(timer);
    }
};

export const createMicrophone: MicrophoneFactory = (send, failed) =>
    new WebviewMicrophone(send, failed);

class WebviewMicrophone implements MicrophoneCapture {
    private context?: AudioContext;
    private stream?: MediaStream;
    private source?: MediaStreamAudioSourceNode;
    private node?: AudioWorkletNode;
    private closed = false;
    private started = false;
    private recording = false;
    private sequence = 0;
    private pending = Promise.resolve();
    private flushed?: () => void;
    private finishing?: Promise<void>;
    private failure?: Error;
    private detachAbort?: () => void;

    constructor(
        private send: Parameters<MicrophoneFactory>[0],
        private failed: Parameters<MicrophoneFactory>[1],
    ) {}

    private isClosed() {
        return this.closed;
    }

    get sampleRate() {
        return this.context?.sampleRate ?? 48000;
    }

    async prepare(signal: AbortSignal) {
        signal.throwIfAborted();
        if (
            typeof (navigator as { mediaDevices?: MediaDevices }).mediaDevices
                ?.getUserMedia !== "function" ||
            typeof globalThis.AudioWorkletNode !== "function"
        )
            throw new Error(
                "This system webview does not support microphone capture.",
            );
        const abort = () => this.close();
        signal.addEventListener("abort", abort, { once: true });
        this.detachAbort = () => signal.removeEventListener("abort", abort);
        try {
            await abortable(
                navigator.mediaDevices
                    .getUserMedia({
                        audio: {
                            echoCancellation: { ideal: false },
                            noiseSuppression: { ideal: false },
                            autoGainControl: { ideal: false },
                        },
                        video: false,
                    })
                    .catch((error: unknown) => {
                        if (
                            error &&
                            typeof error === "object" &&
                            "name" in error
                        ) {
                            if (
                                error.name === "NotFoundError" ||
                                error.name === "OverconstrainedError"
                            )
                                throw new Error(
                                    "No usable microphone was found. Connect a microphone and select it in your system sound settings.",
                                );
                            if (error.name === "NotAllowedError")
                                throw new Error(
                                    "Microphone access was denied. Allow Ensu to use your microphone in system settings and try again.",
                                );
                        }
                        throw error;
                    })
                    .then((stream) => {
                        if (this.isClosed()) {
                            stream.getTracks().forEach((track) => track.stop());
                            return;
                        }
                        this.stream = stream;
                        stream.getAudioTracks().forEach((track) => {
                            track.enabled = false;
                            track.onended = () =>
                                this.endInput("The microphone disconnected.");
                        });
                    }),
                signal,
            );
            signal.throwIfAborted();
            const context = new AudioContext({ sampleRate: 48000 });
            this.context = context;
            await abortable(context.suspend(), signal);
            await abortable(
                context.audioWorklet.addModule("/voice-capture-worklet.js"),
                signal,
            );
            signal.throwIfAborted();
            if (!this.stream?.getAudioTracks().length)
                throw new Error("No microphone audio track is available.");
            const node = new AudioWorkletNode(context, "ensu-voice-capture", {
                channelCount: 1,
                channelCountMode: "explicit",
                numberOfInputs: 1,
                numberOfOutputs: 1,
                outputChannelCount: [1],
            });
            this.node = node;
            node.onprocessorerror = () =>
                this.fail(new Error("Microphone audio processing failed."));
            node.port.onmessage = ({
                data,
            }: MessageEvent<
                { pcm: ArrayBuffer } | { flushed: true } | { error: string }
            >) => {
                if (this.isClosed()) return;
                if ("error" in data) {
                    this.fail(new Error(data.error));
                } else if ("flushed" in data) {
                    this.flushed?.();
                } else {
                    const sequence = this.sequence++;
                    this.pending = this.pending
                        .then(async () => {
                            if (this.isClosed()) return;
                            if (
                                !(await timeout(
                                    this.send(sequence, data.pcm),
                                    5000,
                                ))
                            ) {
                                this.close();
                                return;
                            }
                            if (!this.isClosed()) node.port.postMessage("ack");
                        })
                        .catch((error: unknown) => this.fail(error));
                }
            };
            this.source = context.createMediaStreamSource(this.stream);
            this.source.connect(node);
            node.connect(context.destination);
            context.onstatechange = () => {
                if (this.recording && context.state !== "running")
                    this.endInput("Microphone capture was interrupted.");
            };
        } catch (error) {
            this.close();
            throw error;
        }
    }

    async start() {
        if (this.isClosed() || this.started) return;
        this.started = true;
        this.stream?.getAudioTracks().forEach((track) => {
            track.enabled = true;
        });
        this.node?.port.postMessage("start");
        await timeout(this.context!.resume(), 5000);
        if (this.isClosed()) return;
        this.recording = true;
        if (this.context?.state !== "running")
            throw new Error("The microphone audio context could not start.");
    }

    finish() {
        return (this.finishing ??= this.drain());
    }

    private async drain() {
        try {
            if (!this.isClosed() && this.started) {
                try {
                    await timeout(
                        new Promise<void>((resolve) => {
                            this.flushed = resolve;
                            this.node!.port.postMessage("finish");
                        }),
                        FLUSH_TIMEOUT_MS,
                    );
                } catch (error) {
                    await timeout(this.pending, FLUSH_TIMEOUT_MS);
                    throw error;
                }
                await this.pending;
            }
            if (this.failure) throw this.failure;
        } finally {
            this.close();
        }
    }

    close() {
        if (this.isClosed()) return;
        this.closed = true;
        this.recording = false;
        this.detachAbort?.();
        this.flushed?.();
        this.stream?.getTracks().forEach((track) => {
            track.onended = null;
            track.stop();
        });
        this.node?.port.close();
        this.node?.disconnect();
        this.source?.disconnect();
        void this.context?.close().catch(() => undefined);
        if (this.failure) this.failed(this.failure);
    }

    private endInput(message: string) {
        if (this.isClosed() || this.failure) return;
        this.failure = new Error(message);
        if (this.started) void this.finish().catch(() => undefined);
        else this.close();
    }

    private fail(error: unknown) {
        if (this.isClosed()) return;
        this.failure ??=
            error instanceof Error ? error : new Error(String(error));
        this.close();
    }
}
