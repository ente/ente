import type { LocalUser } from "ente-accounts/services/user";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import { describe, expect, test } from "vitest";
import { albumFiles, albumView } from "../src/components/gallery/album-files";
import {
    initialNavigationState,
    navigationReducer,
} from "../src/components/gallery/navigation-state";
import {
    galleryReducer,
    initialGalleryState,
} from "../src/components/gallery/reducer";

const mounted = () =>
    galleryReducer(initialGalleryState, {
        type: "mount",
        user: { id: 1 } as LocalUser,
        familyData: undefined,
        collections: [],
        collectionFiles: [],
        trashItems: [],
    });

describe("album overview navigation", () => {
    test("opens a group without an active collection or stale photo search results", () => {
        const navigation = navigationReducer(
            { ...initialNavigationState, overlay: { section: "search" } },
            { type: "showAlbumOverview", albumFilter: "shared" },
        );
        const library = mounted();
        const view = albumView(library, navigation.destination);
        expect(view).toEqual({ type: "album-overview", albumFilter: "shared" });
        expect(navigation.destination.collectionID).toBeUndefined();
        expect(albumFiles(library, view)).toEqual([]);
        expect(navigation.overlay).toBeUndefined();
    });
    test("supports repeated group navigation, opening an album and returning Home", () => {
        const library = mounted();
        const summary: CollectionSummary = {
            id: 10,
            type: "album",
            name: "Test album",
            fileCount: 0,
            attributes: new Set(),
            sortPriority: 0,
            coverFile: undefined,
            latestFile: undefined,
            updationTime: undefined,
        };
        library.normalCollectionSummaries.set(summary.id, summary);
        let navigation = navigationReducer(initialNavigationState, {
            type: "showAlbumOverview",
            albumFilter: "ente",
        });
        navigation = navigationReducer(navigation, {
            type: "showAlbumOverview",
            albumFilter: "received",
        });
        navigation = navigationReducer(navigation, {
            type: "showCollectionSummary",
            collectionSummaryID: 10,
            library,
        });
        expect(albumView(library, navigation.destination).type).toBe("albums");
        expect(navigation.destination.collectionID).toBe(10);
        navigation = navigationReducer(navigation, { type: "showAll" });
        expect(navigation.destination.collectionID).toBe(
            PseudoCollectionID.all,
        );
    });
    test("keeps the group overview through collection refreshes", () => {
        let library = mounted();
        const navigation = navigationReducer(initialNavigationState, {
            type: "showAlbumOverview",
            albumFilter: "ente",
        });
        library = galleryReducer(library, {
            type: "setCollections",
            collections: [],
        });
        library = galleryReducer(library, {
            type: "setCollectionFiles",
            collectionFiles: [],
        });
        library = galleryReducer(library, {
            type: "setTrashItems",
            trashItems: [],
        });
        library = galleryReducer(library, { type: "clearUnsyncedState" });
        const view = albumView(library, navigation.destination);
        expect(view).toEqual({ type: "album-overview", albumFilter: "ente" });
        expect(albumFiles(library, view)).toEqual([]);
    });
    test("switches between the People overview and album groups", () => {
        let navigation = navigationReducer(initialNavigationState, {
            type: "showAlbumOverview",
            albumFilter: "ente",
        });
        navigation = navigationReducer(navigation, { type: "showPeople" });
        expect(navigation.destination.section).toBe("people");
        navigation = navigationReducer(navigation, {
            type: "showAlbumOverview",
            albumFilter: "shared",
        });
        expect(albumView(mounted(), navigation.destination)).toEqual({
            type: "album-overview",
            albumFilter: "shared",
        });
    });
});
