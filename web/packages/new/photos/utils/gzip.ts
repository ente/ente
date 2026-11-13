export const gzip = async (
    string: string,
): Promise<Uint8Array<ArrayBuffer>> => {
    const compressedStream = new Blob([string])
        .stream()
        .pipeThrough(new CompressionStream("gzip"));
    return new Uint8Array(await new Response(compressedStream).arrayBuffer());
};

export const gunzip = async (data: Uint8Array<ArrayBuffer>) => {
    const decompressedStream = new Blob([data])
        .stream()
        .pipeThrough(new DecompressionStream("gzip"));
    return new Response(decompressedStream).text();
};

export const gunzipWithLimit = async (
    data: Uint8Array<ArrayBuffer>,
    maxOutputBytes: number,
) => {
    let inputOffset = 0;
    const compressedStream = new ReadableStream<Uint8Array<ArrayBuffer>>({
        pull(controller) {
            if (inputOffset >= data.byteLength) {
                controller.close();
                return;
            }
            controller.enqueue(data.subarray(inputOffset, inputOffset + 1024));
            inputOffset += 1024;
        },
    });
    const reader = compressedStream
        .pipeThrough(new DecompressionStream("gzip"))
        .getReader();
    const chunks: Uint8Array<ArrayBuffer>[] = [];
    let outputSize = 0;

    try {
        while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            outputSize += value.byteLength;
            if (outputSize > maxOutputBytes) {
                await reader.cancel();
                throw new Error("Decompressed data exceeds the allowed size");
            }
            chunks.push(value);
        }
    } finally {
        reader.releaseLock();
    }

    const output = new Uint8Array(outputSize);
    let offset = 0;
    for (const chunk of chunks) {
        output.set(chunk, offset);
        offset += chunk.byteLength;
    }
    return new TextDecoder("utf-8", { fatal: true }).decode(output);
};
