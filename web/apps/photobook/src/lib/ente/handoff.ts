import { parseEnteAlbumUrl } from "./url";

export function parseAlbumHandoff(hash: string) {
    const params = new URLSearchParams(hash.replace(/^#/, ""));
    const albumUrl = params.get("album");
    if (!albumUrl)
        throw new Error(
            "This link doesn't include an album. Use a public album link to import your photos.",
        );
    parseEnteAlbumUrl(albumUrl);
    return {
        albumUrl,
        linkDeviceToken: params.get("deviceToken") ?? undefined,
    };
}
