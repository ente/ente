import assert from "node:assert/strict";
import { test } from "vitest";

import { parseEnteAlbumUrl } from "./url";

const HEX_KEY =
    "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";

function withEnteEnv(
    env: Partial<
        Record<
            | "NEXT_PUBLIC_ENTE_API_ENDPOINT"
            | "NEXT_PUBLIC_ENTE_ALBUMS_ENDPOINT",
            string | undefined
        >
    >,
    fn: () => void,
) {
    const previousApi = process.env.NEXT_PUBLIC_ENTE_API_ENDPOINT;
    const previousAlbums = process.env.NEXT_PUBLIC_ENTE_ALBUMS_ENDPOINT;

    if (env.NEXT_PUBLIC_ENTE_API_ENDPOINT === undefined) {
        delete process.env.NEXT_PUBLIC_ENTE_API_ENDPOINT;
    } else {
        process.env.NEXT_PUBLIC_ENTE_API_ENDPOINT =
            env.NEXT_PUBLIC_ENTE_API_ENDPOINT;
    }

    if (env.NEXT_PUBLIC_ENTE_ALBUMS_ENDPOINT === undefined) {
        delete process.env.NEXT_PUBLIC_ENTE_ALBUMS_ENDPOINT;
    } else {
        process.env.NEXT_PUBLIC_ENTE_ALBUMS_ENDPOINT =
            env.NEXT_PUBLIC_ENTE_ALBUMS_ENDPOINT;
    }

    try {
        fn();
    } finally {
        if (previousApi === undefined) {
            delete process.env.NEXT_PUBLIC_ENTE_API_ENDPOINT;
        } else {
            process.env.NEXT_PUBLIC_ENTE_API_ENDPOINT = previousApi;
        }

        if (previousAlbums === undefined) {
            delete process.env.NEXT_PUBLIC_ENTE_ALBUMS_ENDPOINT;
        } else {
            process.env.NEXT_PUBLIC_ENTE_ALBUMS_ENDPOINT = previousAlbums;
        }
    }
}

for (const host of [
    "albums.ente.com",
    "albums.ente.io",
    "public-albums.ente.io",
]) {
    test(`uses official Ente origins for ${host} links`, () => {
        withEnteEnv(
            {
                NEXT_PUBLIC_ENTE_API_ENDPOINT: undefined,
                NEXT_PUBLIC_ENTE_ALBUMS_ENDPOINT: undefined,
            },
            () => {
                const parsed = parseEnteAlbumUrl(
                    `https://${host}/?t=token123#${HEX_KEY}`,
                );

                assert.equal(
                    parsed.albumsOrigin,
                    "https://public-albums.ente.io",
                );
                assert.deepEqual(parsed.apiOrigins, ["https://api.ente.io"]);
            },
        );
    });
}

test("prefers the sibling api host for self-hosted album domains", () => {
    withEnteEnv(
        {
            NEXT_PUBLIC_ENTE_API_ENDPOINT: undefined,
            NEXT_PUBLIC_ENTE_ALBUMS_ENDPOINT: undefined,
        },
        () => {
            const parsed = parseEnteAlbumUrl(
                `https://albums.photos.example.com/?t=token123#${HEX_KEY}`,
            );

            assert.equal(
                parsed.albumsOrigin,
                "https://albums.photos.example.com",
            );
            assert.deepEqual(parsed.apiOrigins, [
                "https://api.photos.example.com",
                "https://albums.photos.example.com",
                "https://api.ente.io",
            ]);
        },
    );
});

test("prefers configured api origin when the pasted album matches that deployment", () => {
    withEnteEnv(
        {
            NEXT_PUBLIC_ENTE_API_ENDPOINT: "https://museum.example.com/",
            NEXT_PUBLIC_ENTE_ALBUMS_ENDPOINT: "https://shares.example.com/",
        },
        () => {
            const parsed = parseEnteAlbumUrl(
                `https://shares.example.com/?t=token123#${HEX_KEY}`,
            );

            assert.equal(parsed.albumsOrigin, "https://shares.example.com");
            assert.deepEqual(parsed.apiOrigins, [
                "https://museum.example.com",
                "https://api.example.com",
                "https://shares.example.com",
                "https://api.ente.io",
            ]);
        },
    );
});
