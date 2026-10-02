import { generateKey } from "ente-base/crypto";
import type { Collection } from "ente-media/collection";
import {
    decryptMagicMetadata,
    type RemoteMagicMetadata,
} from "ente-media/magic-metadata";
import { updateCollectionSortOrder } from "ente-new/photos/services/collection";
import { afterEach, beforeEach, expect, test, vi } from "vitest";

// Run the same crypto implementation directly in Node instead of a web worker.
vi.mock("ente-base/crypto", () => import("ente-base/crypto/libsodium"));

vi.mock("ente-base/http", async (importOriginal) => ({
    ...(await importOriginal<typeof import("ente-base/http")>()),
    authenticatedRequestHeaders: () => Promise.resolve({}),
}));
vi.mock("ente-base/origins", () => ({
    apiURL: (path: string) => Promise.resolve(`https://example.invalid${path}`),
}));

const fetchMock = vi.fn();
beforeEach(() => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock.mockResolvedValue(new Response(null, { status: 200 }));
});
afterEach(() => {
    vi.unstubAllGlobals();
    vi.clearAllMocks();
});

const album = async () =>
    ({
        id: 10,
        key: await generateKey(),
        pubMagicMetadata: {
            version: 7,
            count: 5,
            data: {
                caption: "Our trip",
                coverID: 2,
                layout: "grouped",
                sortBy: "name",
                futureField: "retain",
            },
        },
    }) as unknown as Collection;

async function savedMetadata(collection: Collection) {
    const [url, request] = fetchMock.mock.calls[0]! as [string, RequestInit];
    expect(url).toBe(
        "https://example.invalid/collections/public-magic-metadata",
    );
    expect(request.method).toBe("PUT");
    const payload = JSON.parse(request.body as string) as {
        id: number;
        magicMetadata: RemoteMagicMetadata;
    };
    expect(payload.id).toBe(collection.id);
    expect(payload.magicMetadata.version).toBe(7);
    return (await decryptMagicMetadata(payload.magicMetadata, collection.key))
        .data;
}

test("filename sorting is encrypted with the album key and preserves unrelated metadata", async () => {
    const collection = await album();
    await updateCollectionSortOrder(collection, true, "name");
    expect(await savedMetadata(collection)).toEqual({
        ...collection.pubMagicMetadata!.data,
        sortBy: "name",
        asc: true,
    });
});

test("legacy newest/oldest calls reset the mode to date", async () => {
    const collection = await album();
    await updateCollectionSortOrder(collection, false);
    expect(await savedMetadata(collection)).toEqual({
        ...collection.pubMagicMetadata!.data,
        sortBy: "date",
        asc: false,
    });
});

test("a rejected save propagates the error and leaves the local album unchanged", async () => {
    const collection = await album();
    const before = structuredClone(collection);
    fetchMock.mockResolvedValueOnce(new Response(null, { status: 409 }));
    await expect(
        updateCollectionSortOrder(collection, false, "name"),
    ).rejects.toThrow();
    expect(collection).toEqual(before);
});
