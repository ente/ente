import type { LocalUser } from "ente-accounts/services/user";
import {
    PseudoCollectionID,
    type CollectionSummary,
} from "ente-new/photos/services/collection-summary";
import { expect, test } from "vitest";
import {
    initialNavigationState,
    navigationReducer,
} from "../src/components/gallery/navigation/navigation-state";
import { initialGalleryState } from "../src/components/gallery/reducer";
import { resolveAlbumDestination } from "../src/components/gallery/sections/albums/album-files";

const archivedAlbumID = 7;

const summary = (id: number, archived = false): CollectionSummary => ({
    id,
    name: `Album ${id}`,
    type: "album",
    attributes: new Set(archived ? ["archived"] : []),
    fileCount: 0,
    latestFile: undefined,
    coverFile: undefined,
    updationTime: undefined,
    sortPriority: 0,
});

const library = {
    ...initialGalleryState,
    user: { id: 1 } as LocalUser,
    normalCollectionSummaries: new Map([
        [PseudoCollectionID.all, summary(PseudoCollectionID.all)],
        [archivedAlbumID, summary(archivedAlbumID, true)],
    ]),
    archivedCollectionSummaries: new Map([
        [
            PseudoCollectionID.archiveItems,
            summary(PseudoCollectionID.archiveItems),
        ],
        [archivedAlbumID, summary(archivedAlbumID, true)],
    ]),
};

test("an archived album selected outside Archive opens in Archive", () => {
    const { destination } = navigationReducer(initialNavigationState, {
        type: "showCollectionSummary",
        collectionSummaryID: archivedAlbumID,
        library,
    });

    expect(destination.albumMode).toBe("archive-albums");
    expect(resolveAlbumDestination(library, destination).collectionID).toBe(
        archivedAlbumID,
    );
});
