import type { LocalUser } from "ente-accounts/services/user";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import { describe, expect, test } from "vitest";
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
        const state = galleryReducer(
            {
                ...mounted(),
                isInSearchMode: true,
                isRecomputingSearchResults: true,
            },
            { type: "showAlbumOverview", albumFilter: "shared" },
        );
        expect(state.view).toEqual({
            type: "album-overview",
            albumFilter: "shared",
        });
        expect(state.selectedCollectionSummaryID).toBeUndefined();
        expect(state.filteredFiles).toEqual([]);
        expect(state.isInSearchMode).toBe(false);
        expect(state.isRecomputingSearchResults).toBe(false);
        expect(state.searchResults).toBeUndefined();
    });

    test("supports repeated group navigation, opening an album and returning Home", () => {
        const start = mounted();
        const favorite: CollectionSummary = {
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
        start.normalCollectionSummaries.set(favorite.id, favorite);
        let state = galleryReducer(start, {
            type: "showAlbumOverview",
            albumFilter: "ente",
        });
        state = galleryReducer(state, {
            type: "showAlbumOverview",
            albumFilter: "received",
        });
        state = galleryReducer(state, {
            type: "showCollectionSummary",
            collectionSummaryID: favorite.id,
        });
        expect(state.view?.type).toBe("albums");
        expect(state.selectedCollectionSummaryID).toBe(favorite.id);
        state = galleryReducer(state, { type: "showAll" });
        expect(
            state.view?.type == "albums" &&
                state.view.activeCollectionSummaryID,
        ).toBe(PseudoCollectionID.all);
    });

    test("keeps the group overview through collection refreshes", () => {
        let state = galleryReducer(mounted(), {
            type: "showAlbumOverview",
            albumFilter: "ente",
        });
        state = galleryReducer(state, {
            type: "setCollections",
            collections: [],
        });
        state = galleryReducer(state, {
            type: "setCollectionFiles",
            collectionFiles: [],
        });
        state = galleryReducer(state, {
            type: "setTrashItems",
            trashItems: [],
        });
        state = galleryReducer(state, { type: "clearUnsyncedState" });
        expect(state.view).toEqual({
            type: "album-overview",
            albumFilter: "ente",
        });
        expect(state.filteredFiles).toEqual([]);
    });

    test("switches between the People overview and album groups", () => {
        let state = galleryReducer(mounted(), {
            type: "showAlbumOverview",
            albumFilter: "ente",
        });
        state = galleryReducer(state, { type: "showPeople" });
        expect(state.view?.type).toBe("people");
        state = galleryReducer(state, {
            type: "showAlbumOverview",
            albumFilter: "shared",
        });
        expect(state.view).toEqual({
            type: "album-overview",
            albumFilter: "shared",
        });
        expect(state.filteredFiles).toEqual([]);
    });
});
