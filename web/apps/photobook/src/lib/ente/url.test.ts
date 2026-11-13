import { describe, expect, test } from "vitest";
import { parseEnteAlbumUrl } from "./url";

const base58 = "11111111111111111111111111111111";
const hex = "00".repeat(32);

describe("public album links", () => {
    test.each(["albums.ente.com", "albums.ente.io", "albums.example.org"])(
        "reads a link on %s without changing the configured API",
        (host) => {
            for (const path of ["/?t=token", "/token", "/token/"]) {
                expect(
                    parseEnteAlbumUrl(`https://${host}${path}#${base58}`),
                ).toEqual({
                    accessToken: "token",
                    collectionKey: btoa("\0".repeat(32)),
                });
            }
        },
    );
    test("prefers the query token when both formats are present", () => {
        expect(
            parseEnteAlbumUrl(`https://albums.ente.com/path?t=query#${base58}`)
                .accessToken,
        ).toBe("query");
    });
    test.each(["/?t=token", "/token"])(
        "accepts legacy hexadecimal keys with %s",
        (path) => {
            expect(
                parseEnteAlbumUrl(`https://albums.ente.com${path}#${hex}`),
            ).toEqual(
                parseEnteAlbumUrl(`https://albums.ente.com${path}#${base58}`),
            );
        },
    );
    test.each([
        "bad URL",
        `https://albums.ente.com/#${base58}`,
        "https://albums.ente.com/?t=token",
        "https://albums.ente.com/token",
        `javascript:alert(1)?t=token#${base58}`,
        "https://albums.ente.com/?t=token#111",
        `https://albums.ente.com/?t=token#${"0g".repeat(32)}`,
    ])("rejects an invalid link: %s", (url) => {
        expect(() => parseEnteAlbumUrl(url)).toThrow();
    });
});
