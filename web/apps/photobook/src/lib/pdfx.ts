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
    const chunks: Blob[] = [];
    return {
        async addPage(canvas: HTMLCanvasElement) {
            const { data, width, height } = canvas
                .getContext("2d")!
                .getImageData(0, 0, canvas.width, canvas.height);
            canvas.width = 0;
            const pixels = new Uint8Array(data.buffer);
            const chunk = await writer.addPage(pixels, width, height);
            chunks.push(new Blob([chunk]));
        },
        async finish() {
            return new Blob([...chunks, await writer.finish()], {
                type: "application/pdf",
            });
        },
        dispose() {
            writer.dispose();
        },
    };
}
