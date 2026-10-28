import { PhotobookPdf } from "ente-photobook-wasm";

export interface PdfXPageSize {
    widthMm: number;
    heightMm: number;
    widthPx: number;
    heightPx: number;
}

export async function createPdfWriter(size: PdfXPageSize) {
    const response = await fetch("/pdfx/FOGRA39L_coated.icc");
    if (!response.ok)
        throw new Error(
            `Failed to load the print colour profile: ${response.status}`,
        );
    const profile = new Uint8Array(await response.arrayBuffer());
    const writer = await PhotobookPdf.create(
        profile,
        size.widthMm,
        size.heightMm,
    );
    const chunks: Uint8Array<ArrayBuffer>[] = [];
    return {
        async addPage(canvas: HTMLCanvasElement) {
            const { data } = canvas
                .getContext("2d")!
                .getImageData(0, 0, canvas.width, canvas.height);
            const pixels = new Uint8Array(data.buffer);
            chunks.push(
                await writer.addPage(pixels, canvas.width, canvas.height),
            );
        },
        async finish() {
            chunks.push(await writer.finish());
            return new Blob(chunks, { type: "application/pdf" });
        },
        dispose() {
            writer.dispose();
        },
    };
}
