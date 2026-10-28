import { transfer, wrap, type Remote } from "comlink";
import { workerReady } from "ente-utils/worker";
import type { PhotobookWorker } from "./worker";

export class PhotobookPdf {
    private constructor(
        private worker: Worker,
        private remote: Remote<PhotobookWorker>,
    ) {}

    static async create(
        profile: Uint8Array,
        widthMm: number,
        heightMm: number,
    ) {
        const worker = new Worker(new URL("worker.ts", import.meta.url));
        const RemoteWorker = wrap<typeof PhotobookWorker>(worker);
        const remote = await workerReady(worker, new RemoteWorker());
        try {
            await remote.initialize(profile, widthMm, heightMm, Date.now());
            return new PhotobookPdf(worker, remote);
        } catch (error) {
            worker.terminate();
            throw error;
        }
    }

    addPage(pixels: Uint8Array<ArrayBuffer>, width: number, height: number) {
        return this.remote.addPage(
            transfer(pixels, [pixels.buffer]),
            width,
            height,
        );
    }

    finish() {
        return this.remote.finish();
    }

    dispose() {
        this.worker.terminate();
    }
}
