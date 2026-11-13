import { decryptStreamChunk, initChunkDecryption } from "ente-base/crypto";
import type { SodiumStateAddress } from "ente-base/crypto/types";
import { saveAsFileAndRevokeObjectURL } from "ente-base/utils/web";

export interface DownloadProgress {
    loaded: number;
    total: number | null;
}

export const saveStreamedFile = async (
    response: Response,
    fileKey: string,
    fileName: string,
    decryptionHeader: string,
    onProgress?: (progress: DownloadProgress) => void,
): Promise<void> => {
    if (!response.body) throw new Error("Response body is empty");

    const totalHeader = response.headers.get("content-length");
    const total = totalHeader ? Number.parseInt(totalHeader, 10) : null;
    let loaded = 0;
    const body = response.body.pipeThrough(
        new TransformStream<Uint8Array, Uint8Array>({
            transform(chunk, controller) {
                loaded += chunk.length;
                onProgress?.({ loaded, total });
                controller.enqueue(chunk);
            },
        }),
    );
    const decrypted = decryptFileStream(body, decryptionHeader, fileKey);
    const blob = await new Response(decrypted).blob();
    saveAsFileAndRevokeObjectURL(URL.createObjectURL(blob), fileName);
};

const decryptFileStream = (
    stream: ReadableStream<Uint8Array>,
    decryptionHeader: string,
    key: string,
): ReadableStream<Uint8Array<ArrayBuffer>> => {
    let pullState: SodiumStateAddress;
    let buffer: Uint8Array<ArrayBuffer>;
    let buffered = 0;

    return stream.pipeThrough(
        new TransformStream<Uint8Array, Uint8Array<ArrayBuffer>>({
            async start() {
                const initialized = await initChunkDecryption(
                    decryptionHeader,
                    key,
                );
                pullState = initialized.pullState;
                buffer = new Uint8Array(initialized.decryptionChunkSize);
            },
            async transform(chunk, controller) {
                let offset = 0;
                while (offset < chunk.length) {
                    const count = Math.min(
                        buffer.length - buffered,
                        chunk.length - offset,
                    );
                    buffer.set(
                        chunk.subarray(offset, offset + count),
                        buffered,
                    );
                    buffered += count;
                    offset += count;
                    if (buffered === buffer.length) {
                        controller.enqueue(
                            await decryptStreamChunk(buffer, pullState),
                        );
                        buffered = 0;
                    }
                }
            },
            async flush(controller) {
                if (buffered > 0) {
                    controller.enqueue(
                        await decryptStreamChunk(
                            buffer.subarray(0, buffered),
                            pullState,
                        ),
                    );
                }
            },
        }),
    );
};
