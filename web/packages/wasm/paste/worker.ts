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
        const paste = await (
            await this.client
        ).create(pasteOrigin, text, password);
        try {
            return { url: paste.url, passwordRequired: paste.passwordRequired };
        } finally {
            paste.free();
        }
    }

    async open(url: string) {
        const paste = await (await this.client).open(url);
        try {
            return paste.passwordRequired
                ? { passwordRequired: true as const }
                : { passwordRequired: false as const, text: paste.text! };
        } finally {
            paste.free();
        }
    }

    submitPassword = async (password: string) =>
        (await this.client).submitPassword(password);
}

expose(PasteWorker);
