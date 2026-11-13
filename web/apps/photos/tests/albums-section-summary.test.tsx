import { AlbumContentHeader } from "@/components/collections/AlbumContentHeader";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { ItemVisibility } from "ente-media/file-metadata";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import type { ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, expect, test, vi } from "vitest";
import { GalleryMedia } from "../src/components/gallery/media/GalleryMedia";
import {
    galleryReducer,
    initialGalleryState,
    type GalleryState,
} from "../src/components/gallery/reducer";
import { AlbumsSection } from "../src/components/gallery/sections/albums/AlbumsSection";
import type { GallerySectionProps } from "../src/components/gallery/sections/types";

vi.mock("@/components/collections/AlbumContentHeader", () => ({
    AlbumContentHeader: vi.fn(() => null),
}));
vi.mock("@/components/collections/AlbumSlideshow", () => ({
    AlbumSlideshow: () => null,
}));
vi.mock("@/components/collections/CollectionMap", () => ({
    CollectionMap: () => null,
}));
vi.mock("@/components/collections/EditAlbumDetailsDialog", () => ({
    EditAlbumDetailsDialog: () => null,
}));
vi.mock("@/components/collections/CreateAlbumDialog", () => ({
    CreateAlbumDialog: () => null,
}));
vi.mock("@/components/gallery", () => ({ GalleryEmptyState: () => null }));
vi.mock("@/components/gallery/sections/albums/AlbumsOverview", () => ({
    AlbumsOverview: () => null,
}));
vi.mock("@/components/gallery/sections/albums/use-gallery-slideshow", () => ({
    useGallerySlideshow: () => ({
        slideshow: undefined,
        startSlideshow: vi.fn(),
        closeSlideshow: vi.fn(),
    }),
}));
vi.mock(
    "@/components/gallery/sections/albums/use-album-navigation-data",
    () =>
        import("../src/components/gallery/sections/albums/use-album-navigation-data"),
);
vi.mock("@/utils/album-filters", () => import("../src/utils/album-filters"));
vi.mock("@/services/upload-manager", () => ({ uploadManager: {} }));
vi.mock("../src/components/gallery/sections/albums/AlbumsNavigation", () => ({
    AlbumsNavigation: () => null,
}));
vi.mock("../src/components/gallery/media/GalleryMedia", () => ({
    GalleryMedia: vi.fn(
        ({ children }: { children?: (hasSelection: boolean) => ReactNode }) =>
            children?.(false),
    ),
}));
vi.mock("../src/components/gallery/navigation/GallerySectionLayout", () => ({
    GallerySectionLayout: ({ children }: { children: ReactNode }) => children,
}));
vi.mock("../src/components/gallery/navigation/PhotosNavigationContext", () => ({
    usePhotosNavigation: () => ({
        selectCollection: vi.fn(),
        showAlbumOverview: vi.fn(),
    }),
}));

beforeEach(() => vi.clearAllMocks());

const files: EnteFile[] = [1, 2].map((id) => ({
    id,
    collectionID: 10,
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

const openAlbum = (
    visibility: ItemVisibility = ItemVisibility.visible,
    collectionFiles: EnteFile[] = [],
) => {
    const album: Collection = {
        id: 10,
        name: "Album",
        type: "album",
        owner: { id: 1 },
        key: "album-key",
        sharees: [],
        publicURLs: [],
        updationTime: 1,
        magicMetadata: { version: 1, count: 1, data: { visibility } },
    };
    const state = galleryReducer(initialGalleryState, {
        type: "mount",
        user: { id: 1, email: "review@example.test", token: "test-token" },
        familyData: undefined,
        collections: [album],
        collectionFiles: [...collectionFiles],
        trashItems: [],
    });
    return state;
};

const headerSummary = (
    state: GalleryState,
    collectionID = 10,
    overlay?: GallerySectionProps["navigation"]["overlay"],
    isFirstLoad = false,
) => {
    const props: GallerySectionProps = {
        library: {
            ...state,
            isFirstLoad,
            searchIndexRevision: 0,
            remotePullRevision: 0,
        },
        operations: {
            dispatch: vi.fn(),
            peopleState: undefined,
            selectionDisabled: false,
            mutations: {
                setPublicLinkToast: vi.fn(),
                handleFavoriteFileOp: vi.fn(),
                onSendLinkError: vi.fn(),
                handleMarkTempDeleted: vi.fn(),
            },
            onAddSaveGroup: vi.fn(),
            onToggleFavorite: vi.fn(),
            onSendLink: vi.fn(),
            onFileVisibilityUpdate: vi.fn(),
            onMarkTempDeleted: vi.fn(),
            onRemotePull: vi.fn(),
            onRemoteFilesPull: vi.fn(),
            onVisualFeedback: vi.fn(),
            onAddFileToCollection: vi.fn(),
            setBlockingLoad: vi.fn(),
            onUpload: vi.fn(),
            saveGroups: [],
            setSectionActivity: vi.fn(),
        },
        navigation: {
            overlay,
            destination: {
                section: "albums",
                collectionID,
                albumMode: state.hiddenCollectionIDs.has(collectionID)
                    ? "hidden-albums"
                    : state.archivedCollectionIDs.has(collectionID)
                      ? "archive-albums"
                      : "albums",
            },
            retainPerson: vi.fn(),
            selectedPlace: undefined,
            placeSelectionRevision: 0,
        },
        preferences: {
            searchSortAsc: undefined,
            setSearchSortAsc: vi.fn(),
            albumFilter: "ente",
            setAlbumFilter: vi.fn(),
            albumSearchQuery: "",
            setAlbumSearchQuery: vi.fn(),
            albumOpenedFromOverview: undefined,
            setAlbumOpenedFromOverview: vi.fn(),
            peopleSortBy: "count-desc",
            setPeopleSortBy: vi.fn(),
            collectionsSortBy: "updation-time-desc",
            onChangeCollectionsSortBy: vi.fn(),
            albumExpansion: { value: "ente", onChange: vi.fn() },
        },
        presentation: {
            collapsed: false,
            mobile: false,
            mobileDrawerProps: { open: false, onClose: vi.fn() },
            reduceMotion: true,
            isFirstLoad: false,
            isOffline: false,
        },
    };
    renderToStaticMarkup(<AlbumsSection {...props} />);
    return vi.mocked(AlbumContentHeader).mock.lastCall![0].collectionSummary;
};

test("enables the date scrubber only for the normal All grid", () => {
    const state = openAlbum(ItemVisibility.visible, files);
    headerSummary(state, PseudoCollectionID.all, undefined, true);
    expect(vi.mocked(GalleryMedia).mock.lastCall![0]).toMatchObject({
        enableDateScrubber: false,
    });
    headerSummary(state, PseudoCollectionID.all);
    expect(vi.mocked(GalleryMedia).mock.lastCall![0]).toMatchObject({
        enableDateScrubber: true,
    });
    for (const id of [10, PseudoCollectionID.trash]) {
        headerSummary(state, id);
        expect(vi.mocked(GalleryMedia).mock.lastCall![0]).toMatchObject({
            enableDateScrubber: false,
        });
    }
    headerSummary(state, PseudoCollectionID.all, { section: "search" });
    expect(vi.mocked(GalleryMedia).mock.lastCall![0]).toMatchObject({
        enableDateScrubber: false,
    });
    headerSummary(openAlbum(ItemVisibility.hidden, files));
    expect(vi.mocked(GalleryMedia).mock.lastCall![0]).toMatchObject({
        enableDateScrubber: false,
    });
    headerSummary(openAlbum(ItemVisibility.archived, files));
    expect(vi.mocked(GalleryMedia).mock.lastCall![0]).toMatchObject({
        enableDateScrubber: false,
    });
});

test.each([
    ["normal", ItemVisibility.visible],
    ["hidden", ItemVisibility.hidden],
    ["archived", ItemVisibility.archived],
])("updates the %s album header after a file sync", (_, visibility) => {
    const before = openAlbum(visibility);
    const after = galleryReducer(before, {
        type: "setCollectionFiles",
        collectionFiles: [...files],
    });
    const summary = headerSummary(after);
    expect(summary?.fileCount).toBe(2);
    expect(summary?.coverFile?.id).toBe(2);
});

test("updates the header as a file uploads into an empty album", () => {
    const after = galleryReducer(openAlbum(), {
        type: "uploadFile",
        file: files[0]!,
    });
    const summary = headerSummary(after);
    expect(summary?.fileCount).toBe(1);
    expect(summary?.coverFile?.id).toBe(1);
});

test("clears the header count and cover when the last files are removed", () => {
    const after = galleryReducer(openAlbum(ItemVisibility.visible, files), {
        type: "setCollectionFiles",
        collectionFiles: [],
    });
    const summary = headerSummary(after);
    expect(summary?.fileCount).toBe(0);
    expect(summary?.coverFile).toBeUndefined();
});

test("updates the Trash header when trash items arrive after collections", () => {
    const after = galleryReducer(openAlbum(), {
        type: "setTrashItems",
        trashItems: [{ file: files[0]!, updatedAt: 1, deleteBy: 2 }],
    });
    expect(headerSummary(after, PseudoCollectionID.trash)?.fileCount).toBe(1);
});
