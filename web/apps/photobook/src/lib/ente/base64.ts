// Standard base64 (with + / = padding) helpers. The ente-wasm API accepts and
// returns base64 strings, so most of our code stays in that encoding.

export function base64ToBytes(b64: string): Uint8Array {
    const bin = atob(b64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return bytes;
}

export function bytesToBase64(bytes: Uint8Array): string {
    // String.fromCharCode.apply blows the stack on large arrays, so chunk.
    let bin = "";
    const chunkSize = 0x8000;
    for (let i = 0; i < bytes.length; i += chunkSize) {
        const chunk = bytes.subarray(i, i + chunkSize);
        bin += String.fromCharCode(...chunk);
    }
    return btoa(bin);
}
