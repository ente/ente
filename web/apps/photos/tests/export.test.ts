import { tryParseTakeoutMetadataJSON } from "ente-gallery/services/upload/metadata-json";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import exportService, {
    getRenamedExportedCollections,
} from "../src/services/export";

const { writeFile } = vi.hoisted(() => ({
    writeFile: vi.fn<(path: string, contents: string) => Promise<void>>(),
}));

vi.mock("@/utils/native-fs", () => import("../src/utils/native-fs"));
vi.mock("ente-base/electron", () => ({
    ensureElectron: () => ({
        fs: { exists: vi.fn().mockResolvedValue(false), writeFile },
    }),
}));
vi.mock("ente-gallery/services/download", () => ({
    downloadManager: { fileStream: vi.fn() },
}));
vi.mock("ente-gallery/utils/native-stream", () => ({ writeStream: vi.fn() }));
vi.mock("ente-new/photos/services/collection", () => ({
    collectionUserFacingName: (collection: Collection) => collection.name,
}));
vi.mock("ente-new/photos/services/photos-fdb", () => ({}));

const file = {
    id: 1,
    collectionID: 2,
    metadata: {
        title: "photo.jpg",
        fileType: FileType.image,
        creationTime: 1_700_000_000_000_000,
        modificationTime: 1_700_000_000_000_000,
        latitude: 12,
        longitude: 34,
    },
} as EnteFile;

beforeEach(() => {
    vi.spyOn(exportService, "addFileExportedRecord").mockResolvedValue();
});
afterEach(() => {
    vi.restoreAllMocks();
    vi.clearAllMocks();
});

test.each(["A caption", "", undefined])(
    "exports caption %j as a description that imports",
    async (caption) => {
        await exportService.downloadAndSave("/export", "/export/Album", {
            ...file,
            pubMagicMetadata: { version: 1, count: 1, data: { caption } },
        });
        const [path, json] = writeFile.mock.calls[0]!;
        expect(path).toBe("/export/Album/metadata/photo.jpg.json");
        const metadata = JSON.parse(json) as Record<string, unknown>;
        expect(metadata.description).toBe(caption || undefined);
        expect(
            (await tryParseTakeoutMetadataJSON(new File([json], path)))
                ?.description,
        ).toBe(caption || undefined);
    },
);

test.each([
    [10, 20, { latitude: 10, longitude: 20 }],
    [0, 20, { latitude: 0, longitude: 20 }],
    [10, 0, { latitude: 10, longitude: 0 }],
    [0, 0, undefined],
    [undefined, 20, { latitude: 12, longitude: 34 }],
    [10, undefined, { latitude: 12, longitude: 34 }],
    [null, 20, { latitude: 12, longitude: 34 }],
    [10, null, { latitude: 12, longitude: 34 }],
    [undefined, undefined, { latitude: 12, longitude: 34 }],
    [NaN, 20, undefined],
] as const)(
    "exports location for edited coordinates %s, %s",
    async (lat, long, expected) => {
        await exportService.downloadAndSave("/export", "/export/Album", {
            ...file,
            pubMagicMetadata: { data: { lat, long } },
        } as EnteFile);
        const metadata = JSON.parse(writeFile.mock.calls[0]![1]) as Record<
            string,
            unknown
        >;
        expect(metadata.geoData).toEqual(expected);
    },
);

test.each([
    ["Project: Alpha", "Project_ Alpha", false],
    ["Project: Alpha", "Project_ Alpha(1)", false],
    ["Trip?", "Trip_", false],
    ["Architecture", "Architecture", false],
    ["New name", "Old name", true],
    ["Project: Beta", "Project_ Alpha", true],
])("album %j exported as %j is renamed: %s", (name, exportName, renamed) => {
    const collection = { id: 1, name } as Collection;
    const exportRecord = {
        collectionExportNames: { 1: exportName },
    } as unknown as Parameters<typeof getRenamedExportedCollections>[1];
    expect(getRenamedExportedCollections([collection], exportRecord)).toEqual(
        renamed ? [collection] : [],
    );
});
