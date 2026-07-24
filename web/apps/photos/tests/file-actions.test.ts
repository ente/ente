import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { getAvailableFileActions } from "ente-new/photos/utils/file-actions";
import { describe, expect, test } from "vitest";

describe("getAvailableFileActions", () => {
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
                hasOnlyOwnFiles: false,
                showAddPerson: false,
                showEditLocation: false,
            }),
        ).toEqual(["favorite", "download", "addToAlbum", "removeFromAlbum"]);
    });
});
