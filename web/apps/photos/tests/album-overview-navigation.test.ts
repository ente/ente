import type { LocalUser } from "ente-accounts/services/user";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import { describe, expect, test } from "vitest";
import {
    initialNavigationState,
    navigationReducer,
} from "../src/components/gallery/navigation/navigation-state";
import {
    galleryReducer,
    initialGalleryState,
} from "../src/components/gallery/reducer";
import {
    albumFiles,
    albumView,
} from "../src/components/gallery/sections/albums/album-files";

const mounted = (
    collections: Collection[] = [],
    collectionFiles: EnteFile[] = [],
) =>
    galleryReducer(initialGalleryState, {
        type: "mount",
        user: { id: 1 } as LocalUser,
        familyData: undefined,
        collections,
        collectionFiles,
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
    test("refreshes populated album summaries while keeping the group overview", () => {
        const album: Collection = {
            id: 10,
            name: "Original album",
            type: "album",
            owner: { id: 1 },
            key: "album-key",
            sharees: [],
            publicURLs: [],
            updationTime: 1,
        };
        const files: EnteFile[] = [1, 2, 3].map((id) => ({
            id,
            collectionID: album.id,
            ownerID: 1,
            key: "file-key",
            file: { decryptionHeader: "" },
            thumbnail: { decryptionHeader: "" },
            updationTime: id,
            metadata: {
                fileType: 0,
                title: `${id}.jpg`,
                creationTime: id,
                modificationTime: id,
            },
        }));
        let library = mounted([album], files.slice(0, 1));
        const navigation = navigationReducer(initialNavigationState, {
            type: "showAlbumOverview",
            albumFilter: "ente",
        });
        expect(library.normalCollectionSummaries.get(album.id)).toMatchObject({
            name: "Original album",
            fileCount: 1,
            coverFile: { id: 1 },
        });
        library = galleryReducer(library, {
            type: "setCollections",
            collections: [{ ...album, name: "Renamed album", updationTime: 2 }],
        });
        expect(library.normalCollectionSummaries.get(album.id)).toMatchObject({
            name: "Renamed album",
            fileCount: 1,
            coverFile: { id: 1 },
        });
        library = galleryReducer(library, {
            type: "setCollectionFiles",
            collectionFiles: files.slice(1),
        });
        expect(library.normalCollectionSummaries.get(album.id)).toMatchObject({
            name: "Renamed album",
            fileCount: 2,
            coverFile: { id: 3 },
        });
        library = galleryReducer(library, {
            type: "setTrashItems",
            trashItems: [{ file: files[0]!, updatedAt: 4, deleteBy: 5 }],
        });
        expect(
            library.normalCollectionSummaries.get(PseudoCollectionID.trash)
                ?.fileCount,
        ).toBe(1);
        library = galleryReducer(library, { type: "clearUnsyncedState" });
        const view = albumView(library, navigation.destination);
        expect(view).toEqual({ type: "album-overview", albumFilter: "ente" });
        expect(library.normalCollectionSummaries.get(album.id)).toMatchObject({
            name: "Renamed album",
            fileCount: 2,
            coverFile: { id: 3 },
        });
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
