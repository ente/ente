import { expose } from "comlink";
import type { PasteClient as WasmPasteClient } from "./pkg/ente_paste_wasm";

export class PasteWorker {
    private client: Promise<WasmPasteClient>;

    constructor(apiOrigin: string) {
        this.client = import("./pkg/ente_paste_wasm").then(
            ({ PasteClient }) => new PasteClient(apiOrigin),
        );
    }

    async create(pasteOrigin: string, text: string, password?: string) {
        return (await this.client).create(pasteOrigin, text, password);
    }

    async open(url: string) {
        return (await this.client).open(url);
    }

    submitPassword = async (password: string) =>
        (await this.client).submitPassword(password);
}

expose(PasteWorker);
