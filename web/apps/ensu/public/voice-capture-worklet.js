class VoiceCaptureProcessor extends AudioWorkletProcessor {
    constructor() {
        super();
        this.active = false;
        this.outstanding = 0;
        this.capacity = Math.round(sampleRate / 10);
        this.buffer = new ArrayBuffer(this.capacity * 2);
        this.view = new DataView(this.buffer);
        this.length = 0;
        this.port.onmessage = ({ data }) => {
            if (data === "start") this.active = true;
            if (data === "ack")
                this.outstanding = Math.max(0, this.outstanding - 1);
            if (data === "finish") {
                this.active = false;
                this.flush();
                this.port.postMessage({ flushed: true });
            }
        };
    }

    flush() {
        if (!this.length) return;
        if (this.active && this.outstanding >= 20) {
            this.active = false;
            this.length = 0;
            this.port.postMessage({
                error: "Microphone audio delivery could not keep up.",
            });
            return;
        }
        const pcm = this.buffer.slice(0, this.length * 2);
        this.port.postMessage({ pcm }, [pcm]);
        this.outstanding++;
        this.length = 0;
    }

    process(inputs) {
        if (!this.active) return true;
        const samples = inputs[0]?.[0];
        if (!samples) return true;
        for (const sample of samples) {
            const value = Number.isFinite(sample)
                ? Math.max(-1, Math.min(1, sample))
                : 0;
            this.view.setInt16(
                this.length++ * 2,
                Math.round(value * (value < 0 ? 32768 : 32767)),
                true,
            );
            if (this.length === this.capacity) {
                this.flush();
                if (!this.active) break;
            }
        }
        return true;
    }
}

registerProcessor("ensu-voice-capture", VoiceCaptureProcessor);
