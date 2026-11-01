import type { LocalUser } from "ente-accounts/services/user";
import type { EnteFile } from "ente-media/file";
import { ItemVisibility } from "ente-media/file-metadata";
import {
    PseudoCollectionID,
    type CollectionSummary,
} from "ente-new/photos/services/collection-summary";
import type { PeopleState, Person } from "ente-new/photos/services/ml/people";
import { expect, test } from "vitest";
import {
    albumFiles,
    albumView,
    resolveAlbumDestination,
} from "../src/components/gallery/album-files";
import { homeDestination } from "../src/components/gallery/navigation-state";
import {
    derivePeopleFilteredFiles,
    derivePeopleView,
    resolvePeopleDestination,
} from "../src/components/gallery/people-files";
import {
    galleryReducer,
    initialGalleryState,
    type GalleryState,
} from "../src/components/gallery/reducer";

const file = (id: number, collectionID = 10): EnteFile =>
    ({
        id,
        collectionID,
        ownerID: 1,
        metadata: { creationTime: id, fileType: 0 },
    }) as EnteFile;
const library = (): GalleryState => ({
    ...initialGalleryState,
    user: { id: 1 } as LocalUser,
    collectionFiles: [file(1), file(2), file(3), file(4), file(1, 11)],
    hiddenFileIDs: new Set([2]),
    archivedFileIDs: new Set([3]),
    normalCollectionSummaries: new Map([
        [
            PseudoCollectionID.all,
            {
                id: PseudoCollectionID.all,
                attributes: new Set(),
            } as CollectionSummary,
        ],
    ]),
});

test("All Photos keeps visibility, deduplication, and optimistic deletion rules", () => {
    let state = library();
    state.collectionFiles[2]!.magicMetadata = {
        version: 1,
        count: 1,
        data: { visibility: ItemVisibility.archived },
    };
    const files = () =>
        albumFiles(state, albumView(state, homeDestination)).map(
            (file) => file.id,
        );
    expect(files()).toEqual([1, 4]);
    state = galleryReducer(state, {
        type: "markTempDeleted",
        files: [file(4)],
    });
    expect(files()).toEqual([1]);
    const trash = albumFiles(state, {
        type: "albums",
        activeCollectionSummaryID: PseudoCollectionID.trash,
        activeCollection: undefined,
        activeCollectionSummary: {
            id: PseudoCollectionID.trash,
        } as CollectionSummary,
    });
    expect(trash.map((file) => file.id)).toEqual([4]);
});

test("removing the album shown on a map falls back to the library map", () => {
    const destination = resolveAlbumDestination(library(), {
        section: "albums",
        albumMode: "albums",
        collectionID: 10,
        collectionMap: true,
    });
    expect(destination.section).toBe("places");
    expect(destination.collectionID).toBe(PseudoCollectionID.all);
});

test("People keeps a selected small cluster and filters hidden and duplicate files", () => {
    const small = { id: "small", fileIDs: [1, 2], name: undefined } as Person;
    const named = { id: "named", fileIDs: [4], name: "Named" } as Person;
    const people: PeopleState = {
        people: [small, named],
        visiblePeople: [named],
        personByFaceID: new Map(),
    };
    const selected = derivePeopleView(
        people,
        new Set(),
        new Set(),
        "small",
        undefined,
    );
    expect(selected.view.visiblePeople.map((person) => person.id)).toEqual([
        "named",
        "small",
    ]);
    const state = library();
    expect(
        derivePeopleFilteredFiles(
            state.collectionFiles,
            state.hiddenFileIDs,
            selected.view,
            1,
        ).map((file) => file.id),
    ).toEqual([1]);
    const next = derivePeopleView(
        people,
        new Set(),
        new Set(),
        "named",
        selected.extraVisiblePerson,
    );
    expect(next.view.visiblePeople.map((person) => person.id)).toContain(
        "small",
    );
    const removed = derivePeopleView(
        people,
        new Set([1, 2]),
        new Set(),
        "small",
        selected.extraVisiblePerson,
    );
    expect(removed.view.activePerson).toBeUndefined();
    expect(removed.extraVisiblePerson).toBeUndefined();
    expect(
        resolvePeopleDestination(
            {
                ...state,
                peopleState: people,
                tempDeletedFileIDs: new Set([1, 2]),
            },
            {
                section: "people",
                personID: "small",
                extraVisiblePersonID: "small",
            },
        ),
    ).toEqual({
        section: "people",
        personID: undefined,
        extraVisiblePersonID: undefined,
    });
});
