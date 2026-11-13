import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { describe, expect, test } from "vitest";
import { getAvailableFileActions } from "../src/utils/file-actions";

describe("getAvailableFileActions", () => {
    test("allows moving files between hidden albums", () => {
        expect(
            getAvailableFileActions({
                barMode: "hidden-albums",
                isInSearchMode: false,
                collectionSummary: undefined,
                hasOwnFiles: true,
                hasOnlyOwnFiles: true,
                showAddPerson: false,
                showEditLocation: false,
            }),
        ).toEqual([
            "sendLink",
            "download",
            "addToAlbum",
            "moveToAlbum",
            "unhide",
            "trash",
        ]);
    });

    test("does not allow moving unowned files between hidden albums", () => {
        expect(
            getAvailableFileActions({
                barMode: "hidden-albums",
                isInSearchMode: false,
                collectionSummary: undefined,
                hasOwnFiles: false,
                hasOnlyOwnFiles: false,
                showAddPerson: false,
                showEditLocation: false,
            }),
        ).toEqual(["download", "addToAlbum", "unhide"]);
    });

    test("allows trashing owned files in a mixed hidden-album selection", () => {
        expect(
            getAvailableFileActions({
                barMode: "hidden-albums",
                isInSearchMode: false,
                collectionSummary: undefined,
                hasOwnFiles: true,
                hasOnlyOwnFiles: false,
                showAddPerson: false,
                showEditLocation: false,
            }),
        ).toEqual(["download", "addToAlbum", "unhide", "trash"]);
    });

    test("uses shared actions for an incoming uncategorized collection", () => {
        const collectionSummary: CollectionSummary = {
            id: 1,
            type: "sharedIncoming",
            attributes: new Set([
                "sharedIncoming",
                "sharedIncomingAdmin",
                "uncategorized",
            ]),
            name: "Shared uncategorized",
            latestFile: undefined,
            coverFile: undefined,
            fileCount: 1,
            updationTime: undefined,
            sortPriority: 0,
        };

        expect(
            getAvailableFileActions({
                isInSearchMode: false,
                collectionSummary,
                hasOwnFiles: false,
                hasOnlyOwnFiles: false,
                showAddPerson: false,
                showEditLocation: false,
            }),
        ).toEqual(["favorite", "download", "addToAlbum", "removeFromAlbum"]);
    });
});
