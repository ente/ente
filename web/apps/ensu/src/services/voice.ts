import {
    createMicrophone,
    type MicrophoneCapture,
    type MicrophoneFactory,
} from "./voice-microphone.ts";

export interface VoiceOutcome {
    text: string;
    incomplete: boolean;
    warning?: string;
}

export type VoiceEvent =
    | { type: "capture"; id: string; running: boolean }
    | { type: "progress"; id: string; percent: number; status: string }
    | {
          type: "snapshot";
          id: string;
          phase:
              | "preparing"
              | "listening"
              | "countdown"
              | "finishing"
              | "ready"
              | "closed";
          text: string;
          hypothesis: string;
          level: number;
      };

export interface VoiceTransport {
    invoke: <T>(command: string, args?: Record<string, unknown>) => Promise<T>;
    sendAudio: (
        id: string,
        sequence: number,
        pcm: ArrayBuffer,
    ) => Promise<boolean>;
    listen: (onEvent: (event: VoiceEvent) => void) => Promise<() => void>;
}

export const voiceTransport = async (): Promise<VoiceTransport> => {
    const [{ invoke }, { listen }] = await Promise.all([
        import("@tauri-apps/api/core"),
        import("@tauri-apps/api/event"),
    ]);
    return {
        invoke,
        sendAudio: (id, sequence, pcm) =>
            invoke<boolean>("voice_feed", pcm, {
                headers: {
                    "x-voice-session": id,
                    "x-voice-sequence": String(sequence),
                },
            }),
        listen: (callback) =>
            listen<VoiceEvent>("voice-event", ({ payload }) =>
                callback(payload),
            ),
    };
};

export class DesktopDictation {
    private id?: string;
    private discarded = false;
    private ran = false;
    private capture?: MicrophoneCapture;
    private abort = new AbortController();
    private starting?: Promise<void>;
    private finishing?: Promise<void>;
    private captureFailure?: Error;
    constructor(
        private transport: VoiceTransport,
        private microphone: MicrophoneFactory = createMicrophone,
    ) {}

    private isCancelled() {
        return this.discarded;
    }

    get hasStarted() {
        return this.starting !== undefined;
    }

    async cancel() {
        this.discarded = true;
        this.abort.abort();
        this.capture?.close();
        if (this.id)
            await this.transport.invoke("voice_stop", {
                id: this.id,
                discard: true,
            });
    }

    finish() {
        return (this.finishing ??= this.drain());
    }

    private async drain() {
        if (!this.id || this.isCancelled()) return;
        try {
            await this.starting;
            await this.capture?.finish();
            if (!this.isCancelled())
                await this.transport.invoke("voice_stop", {
                    id: this.id,
                    discard: false,
                });
        } catch (error) {
            await this.captureFailed(error);
        }
    }

    private async captureFailed(error: unknown) {
        if (this.isCancelled() || this.captureFailure) return;
        this.captureFailure =
            error instanceof Error ? error : new Error(String(error));
        this.capture?.close();
        try {
            await this.transport.invoke("voice_capture_failed", {
                id: this.id,
                message: this.captureFailure.message,
            });
        } catch {
            await this.transport
                .invoke("voice_stop", { id: this.id, discard: true })
                .catch(() => undefined);
        }
    }

    async run(
        onEvent: (event: VoiceEvent) => void,
    ): Promise<VoiceOutcome | undefined> {
        if (this.ran) throw new Error("Voice session already started");
        this.ran = true;
        if (this.isCancelled()) return;
        const unlisten = await this.transport.listen((event) => {
            if (this.discarded || event.id !== this.id) return;
            if (event.type === "capture") {
                if (event.running) {
                    this.starting ??= this.capture!.start().catch(
                        (error: unknown) => this.captureFailed(error),
                    );
                } else {
                    this.capture?.close();
                }
            } else {
                onEvent(event);
            }
        });
        try {
            if (this.isCancelled()) return;
            this.id = await this.transport.invoke<string>("voice_create");
            if (this.isCancelled()) return;
            this.capture = this.microphone(
                (sequence, pcm) =>
                    this.transport.sendAudio(this.id!, sequence, pcm),
                (error) => {
                    void this.captureFailed(error);
                },
            );
            await this.capture.prepare(this.abort.signal);
            if (this.isCancelled()) return;
            const result = await this.transport.invoke<VoiceOutcome>(
                "voice_run",
                { id: this.id, sampleRate: this.capture.sampleRate },
            );
            return this.isCancelled() ? undefined : result;
        } catch (error) {
            if (!this.isCancelled()) throw this.captureFailure ?? error;
            return undefined;
        } finally {
            this.capture?.close();
            try {
                if (this.id)
                    await this.transport.invoke("voice_stop", {
                        id: this.id,
                        discard: true,
                    });
            } finally {
                unlisten();
            }
        }
    }
}

export interface VoiceAnchor {
    destination: string;
    revision: number;
    startUtf16: number;
    endUtf16: number;
}

export const insertVoiceText = async (args: {
    anchor: VoiceAnchor;
    destination: string;
    revision: number;
    text: string;
    voiceText: string;
    composing: boolean;
}) => {
    const { invoke } = await voiceTransport();
    return invoke<{ text: string; caretUtf16: number }>("voice_insert", args);
};
