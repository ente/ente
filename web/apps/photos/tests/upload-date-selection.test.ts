import type { CryptoWorker } from "ente-base/crypto/worker";
import {
    metadataJSONMapKeyForJSON,
    type ParsedMetadataJSON,
} from "ente-gallery/services/upload/metadata-json";
import { upload } from "ente-gallery/services/upload/upload-service";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import type { ParsedMetadata } from "ente-media/file-metadata";
import * as fileMetadata from "ente-media/file-metadata";
import { afterEach, describe, expect, test, vi } from "vitest";

const fixture = vi.hoisted((): { embedded: ParsedMetadata } => ({
    embedded: {},
}));
vi.mock("ente-base/crypto", () => ({
    decryptBox: vi.fn(),
    decryptMetadataJSON: vi.fn(),
    encryptMetadataJSON: vi.fn(),
}));
vi.mock("ente-base/log", () => ({
    default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));
vi.mock("ente-gallery/services/exif", () => ({
    extractExif: () => Promise.resolve(fixture.embedded),
    extractRawExif: vi.fn(),
    parseExif: vi.fn(),
}));
vi.mock("ente-gallery/services/ffmpeg", () => ({
    extractVideoMetadata: vi.fn(),
    determineVideoDuration: vi.fn(),
}));
vi.mock("ente-gallery/services/upload/thumbnail", () => ({
    fallbackThumbnail: vi.fn(),
    generateThumbnailNative: vi.fn(),
    generateThumbnailWeb: vi.fn(),
}));
vi.mock("ente-gallery/utils/detect-type", () => ({
    detectFileTypeInfoFromChunk: () =>
        Promise.resolve({ fileType: 0, extension: "jpg" }),
    isFileTypeNotSupportedError: () => false,
}));
vi.mock("ente-gallery/utils/native-stream", () => ({
    readStream: () =>
        Promise.resolve({
            response: new Response(new Uint8Array([1, 2, 3])),
            size: 3,
            lastModifiedMs: Date.parse("2026-11-12T00:06:00Z"),
        }),
}));
vi.mock("ente-new/photos/services/collection", () => ({
    addToCollection: vi.fn(),
}));
vi.mock("ente-media/live-photo", () => ({ encodeLivePhoto: vi.fn() }));

const createdMs = Date.parse("2024-06-29T09:50:00Z");
const modifiedUs = Date.parse("2026-11-12T00:06:00Z") * 1000;
const metadataDate = {
    timestamp: Date.parse("2020-01-01T00:00:00Z") * 1000,
    dateTime: "2020-01-01T00:00:00",
    offset: "Z",
};

afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
});

async function selectedMetadata({
    name = "sample.jpg",
    embedded = {},
    sidecar,
    live = false,
}: {
    name?: string;
    embedded?: ParsedMetadata;
    sidecar?: ParsedMetadataJSON;
    live?: boolean;
}) {
    fixture.embedded = embedded;
    const statBirthtime = vi.fn().mockResolvedValue(createdMs);
    vi.stubGlobal("electron", { fs: { statBirthtime } });
    const hashSpy = vi.spyOn(fileMetadata, "metadataHash");
    const existing = {
        id: 1,
        collectionID: 1,
        metadata: {
            title: name,
            fileType: live ? 2 : 0,
            creationTime: modifiedUs,
            modificationTime: modifiedUs,
            hash: live ? "hash:hash" : "hash",
        },
    } as EnteFile;
    const metadataMap = new Map<string, ParsedMetadataJSON>();
    if (sidecar)
        metadataMap.set(
            metadataJSONMapKeyForJSON(undefined, 1, name + ".json"),
            sidecar,
        );
    const worker = {
        chunkHashInit: vi.fn().mockResolvedValue({}),
        chunkHashUpdate: vi.fn().mockResolvedValue(undefined),
        chunkHashFinal: vi.fn().mockResolvedValue("hash"),
    } as unknown as CryptoWorker;
    const result = await upload(
        {
            localID: 1,
            collectionID: 1,
            collection: { id: 1, key: "collection-key" } as Collection,
            fileName: name,
            isLivePhoto: live,
            pathPrefix: undefined,
            ...(live
                ? {
                      livePhotoAssets: {
                          image: "/photos/" + name,
                          video: "/photos/live.mov",
                      },
                  }
                : { uploadItem: "/photos/" + name }),
        },
        undefined,
        [existing],
        metadataMap,
        worker,
        {
            isCFUploadProxyDisabled: false,
            deferMultipartChecksums: false,
            isInternalUser: false,
            abortIfCancelled: vi.fn(),
            updateUploadProgress: vi.fn(),
        },
    );
    expect(result.type).toBe("alreadyUploaded");
    const selected = hashSpy.mock.calls
        .map(([value]) => value)
        .find((value) => value !== existing.metadata);
    expect(selected).toBeDefined();
    expect(selected!.modificationTime).toBe(modifiedUs);
    return { selected: selected!, statBirthtime };
}

describe("upload creation date selection", () => {
    test.each([
        {
            label: "sidecar",
            embedded: { creationTime: createdMs * 1000 },
            sidecar: { creationDate: metadataDate },
        },
        { label: "embedded", embedded: { creationDate: metadataDate } },
    ])(
        "uses $label metadata before filename and native dates",
        async ({ embedded, sidecar }) => {
            const { selected, statBirthtime } = await selectedMetadata({
                name: "2022-01-02.jpg",
                embedded,
                sidecar,
            });
            expect(selected.creationTime).toBe(metadataDate.timestamp);
            expect(statBirthtime).not.toHaveBeenCalled();
        },
    );

    test("uses the filename before reading filesystem dates", async () => {
        const { selected, statBirthtime } = await selectedMetadata({
            name: "2022-01-02.jpg",
        });
        expect(selected.creationTime).toBe(
            new Date(2022, 0, 2).getTime() * 1000,
        );
        expect(statBirthtime).not.toHaveBeenCalled();
    });

    test("uses Created when other date sources are absent", async () => {
        const { selected, statBirthtime } = await selectedMetadata({});
        expect(selected.creationTime).toBe(createdMs * 1000);
        expect(statBirthtime).toHaveBeenCalledExactlyOnceWith(
            "/photos/sample.jpg",
        );
    });

    test("uses the image component's Created date for a Live Photo", async () => {
        const { selected, statBirthtime } = await selectedMetadata({
            name: "live.heic",
            live: true,
        });
        expect(selected.creationTime).toBe(createdMs * 1000);
        expect(statBirthtime).toHaveBeenCalledExactlyOnceWith(
            "/photos/live.heic",
        );
    });
});
