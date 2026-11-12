import { expose, transfer } from "comlink";
import { ensureArrayBufferBacked } from "ente-utils/bytes";
import type { PdfX4Writer } from "./pkg/ente_photobook_wasm";

export class PhotobookWorker {
    private writer: PdfX4Writer | undefined;

    async initialize(
        profile: Uint8Array,
        widthMm: number,
        heightMm: number,
        createdAt: number,
    ) {
        const { PdfX4Writer } = await import("./pkg/ente_photobook_wasm");
        this.writer = new PdfX4Writer(
            profile,
            "FOGRA39",
            widthMm,
            heightMm,
            createdAt,
        );
    }

    addPage(pixels: Uint8Array, width: number, height: number) {
        const chunk = ensureArrayBufferBacked(
            this.writer!.addPage(pixels, width, height),
        );
        return transfer(chunk, [chunk.buffer]);
    }

    finish() {
        const chunk = ensureArrayBufferBacked(this.writer!.finish());
        this.writer = undefined;
        return transfer(chunk, [chunk.buffer]);
    }
}

expose(PhotobookWorker);
