import bs58 from "bs58";

export function parseEnteAlbumUrl(input: string) {
    let url: URL;
    try {
        url = new URL(input.trim());
    } catch {
        throw new Error("That doesn't look like a valid URL.");
    }
    if (url.protocol !== "https:" && url.protocol !== "http:")
        throw new Error("Album links must use HTTP or HTTPS.");
    const accessToken = url.searchParams.get("t");
    if (!accessToken)
        throw new Error("Album link is missing the access token (?t=…).");
    const hash = url.hash.slice(1);
    if (!hash)
        throw new Error(
            "Album link is missing the decryption key (the #… at the end).",
        );
    let bytes: Uint8Array;
    try {
        if (hash.length < 50) bytes = bs58.decode(hash);
        else {
            if (!/^[0-9a-f]{64}$/i.test(hash))
                throw new Error("Expected a 64-character hexadecimal key.");
            bytes = Uint8Array.from(hash.match(/../g)!, (pair) =>
                parseInt(pair, 16),
            );
        }
    } catch (cause) {
        throw new Error("Album decryption key is malformed.", { cause });
    }
    if (bytes.length !== 32)
        throw new Error(
            `Album decryption key has wrong length: expected 32 bytes, got ${bytes.length}.`,
        );
    return { accessToken, collectionKey: btoa(String.fromCharCode(...bytes)) };
}
