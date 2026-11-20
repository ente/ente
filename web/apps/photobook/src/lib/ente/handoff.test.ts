import { describe, expect, test } from "vitest";
import { parseAlbumHandoff } from "./handoff";

describe("album handoff", () => {
    test.each([
        "https://albums.ente.com/album-token",
        "https://albums.ente.com/?t=album-token",
        "https://photos.example.org/album-token",
    ])("preserves the complete public link from %s", (base) => {
        const albumUrl = `${base}#${"00".repeat(32)}`;
        const fragment = new URLSearchParams({
            album: albumUrl,
            deviceToken: "device-admission",
        });
        const url = new URL(`https://photobook.ente.com/import#${fragment}`);
        expect(url.search).toBe("");
        expect(parseAlbumHandoff(url.hash)).toEqual({
            albumUrl,
            linkDeviceToken: "device-admission",
        });
    });
    test("allows an owner to open a link without an existing device token", () => {
        const albumUrl = `https://albums.ente.com/album#${"00".repeat(32)}`;
        expect(
            parseAlbumHandoff(
                new URLSearchParams({ album: albumUrl }).toString(),
            ),
        ).toEqual({ albumUrl, linkDeviceToken: undefined });
    });
    test.each([
        "",
        "#album=bad-url",
        "#album=https%3A%2F%2Falbums.ente.com%2Ftoken",
    ])("rejects missing or incomplete album credentials: %s", (hash) => {
        expect(() => parseAlbumHandoff(hash)).toThrow();
    });
});
