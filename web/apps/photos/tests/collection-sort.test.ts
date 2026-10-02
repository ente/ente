import { CollectionPublicMagicMetadataData } from "ente-media/collection";
import { sortCollectionFiles, sortFiles } from "ente-media/collection-sort";
import type { EnteFile } from "ente-media/file";
import { describe, expect, test } from "vitest";

const photo = (id: number, title = `photo${id}.jpg`): EnteFile =>
    ({
        id,
        collectionID: 10,
        metadata: {
            title,
            creationTime: id * 1_000_000,
            modificationTime: id * 1_000_000,
        },
    }) as EnteFile;
const ids = (files: EnteFile[]) => files.map(({ id }) => id);

describe("album sorting", () => {
    test("preserves legacy date ordering without mutating the library", () => {
        const files = [photo(2), photo(1), photo(3)];
        expect(ids(sortCollectionFiles(files))).toEqual([3, 2, 1]);
        expect(ids(sortCollectionFiles(files, { asc: true }))).toEqual([
            1, 2, 3,
        ]);
        expect(ids(files)).toEqual([2, 1, 3]);
        expect(sortCollectionFiles([])).toEqual([]);
        expect(sortFiles(files)).toBe(files);
        expect(ids(files)).toEqual([3, 2, 1]);
    });
    test("uses edited dates and modification time like the existing sorter", () => {
        const files = [photo(1), photo(2), photo(3)];
        files[0]!.pubMagicMetadata = {
            data: { editedTime: 3_000_000 },
            version: 1,
            count: 1,
        };
        expect(ids(sortCollectionFiles(files))).toEqual([3, 1, 2]);
        expect(ids(sortCollectionFiles(files, { asc: true }))).toEqual([
            2, 1, 3,
        ]);
    });
    test("sorts filenames naturally, ignoring case and honoring renamed files", () => {
        const files = [
            photo(1, "IMG10.jpg"),
            photo(2, "img2.jpg"),
            photo(3, "z.jpg"),
        ];
        files[2]!.pubMagicMetadata = {
            version: 1,
            count: 1,
            data: { editedName: "img1.jpg" },
        };
        expect(
            ids(sortCollectionFiles(files, { sortBy: "name", asc: true })),
        ).toEqual([3, 2, 1]);
        expect(
            ids(sortCollectionFiles(files, { sortBy: "name", asc: false })),
        ).toEqual([1, 2, 3]);
    });
    test("equal filenames have a deterministic order across syncs", () => {
        const files = [photo(2, "a.jpg"), photo(1, "A.jpg")];
        expect(
            ids(sortCollectionFiles(files, { sortBy: "name", asc: true })),
        ).toEqual([1, 2]);
        expect(
            sortCollectionFiles([...files].reverse(), { sortBy: "name" }),
        ).toEqual(sortCollectionFiles(files, { sortBy: "name" }));
    });
    test("future sort modes fall back to legacy date ordering", () => {
        const metadata = { sortBy: "future-mode", asc: true };
        expect(
            ids(sortCollectionFiles([photo(3), photo(1), photo(2)], metadata)),
        ).toEqual([1, 2, 3]);
    });
    test("metadata round trips retain ordering and unrelated fields", () => {
        const metadata = {
            asc: true,
            sortBy: "name",
            caption: "Trip",
            coverID: 1,
            futureField: "preserve",
        };
        expect(
            JSON.parse(
                JSON.stringify(
                    CollectionPublicMagicMetadataData.parse(metadata),
                ),
            ),
        ).toEqual(metadata);
        expect(
            CollectionPublicMagicMetadataData.parse({ sortBy: null }),
        ).toMatchObject({ sortBy: undefined });
    });
});
