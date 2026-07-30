/**
 * Compress the given {@link string} using "gzip" and return the resultant
 * bytes. See {@link gunzip} for the reverse operation.
 *
 * This is syntactic sugar to deal with the string/blob/stream/bytes
 * conversions, but it should not be taken as an abstraction layer. If your code
 * can directly use a ReadableStream, then then data -> stream -> data round
 * trip is unnecessary.
 */
export const gzip = async (
    string: string,
): Promise<Uint8Array<ArrayBuffer>> => {
    const compressedStream = new Blob([string])
        .stream()
        // This code only runs on the desktop app currently, so we can rely on
        // the existence of new web features the CompressionStream APIs.
        .pipeThrough(new CompressionStream("gzip"));
    return new Uint8Array(await new Response(compressedStream).arrayBuffer());
};

/**
 * Decompress the given "gzip" compressed {@link data} and return the resultant
 * string. See {@link gzip} for the reverse operation.
 */
export const gunzip = async (data: Uint8Array<ArrayBuffer>) => {
    const decompressedStream = new Blob([data])
        .stream()
        // This code only runs on the desktop app currently, so we can rely on
        // the existence of new web features the CompressionStream APIs.
        .pipeThrough(new DecompressionStream("gzip"));
    return new Response(decompressedStream).text();
};

/**
 * Decompress the given "gzip" compressed {@link data}, rejecting it if the
 * decompressed output exceeds {@link maxOutputBytes}.
 */
export const gunzipWithLimit = async (
    data: Uint8Array<ArrayBuffer>,
    maxOutputBytes: number,
) => {
    const reader = new Blob([data])
        .stream()
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
