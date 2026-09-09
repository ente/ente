import { wrap, type Remote } from "comlink";
import { workerReady } from "ente-utils/worker";
import type { PasteWorker } from "./worker";

export class PasteClient {
    private constructor(
        private worker: Worker,
        private remote: Remote<PasteWorker>,
    ) {}

    static async init(apiOrigin: string) {
        const worker = new Worker(new URL("worker.ts", import.meta.url));
        const RemoteWorker = wrap<typeof PasteWorker>(worker);
        const remote = await workerReady(worker, new RemoteWorker(apiOrigin));
        return new PasteClient(worker, remote);
    }

    create = (pasteOrigin: string, text: string, password?: string) =>
        this.remote.create(pasteOrigin, text, password);

    open = (url: string) => this.remote.open(url);

    submitPassword = (password: string) => this.remote.submitPassword(password);

    terminate = () => this.worker.terminate();
}
