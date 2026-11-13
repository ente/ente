import { expose } from "comlink";

export class FileLinkWorker {
    async prepareFileLinkPayload(fileKeyB64: string) {
        const wasm = await import("./pkg/ente_locker_wasm");
        return wasm.lockerPrepareFileLinkPayload(fileKeyB64);
    }
}

expose(FileLinkWorker);
