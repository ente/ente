import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, test, vi } from "vitest";
import type { useGalleryPreferences } from "../src/components/gallery/hooks/use-gallery-preferences";
import type {
    GalleryDestination,
    NavigationAction,
} from "../src/components/gallery/navigation/navigation-state";
import { initialGalleryState } from "../src/components/gallery/reducer";
import { useAlbumActions } from "../src/components/gallery/sections/albums/use-album-actions";

vi.mock("@/utils/album-filters", () => import("../src/utils/album-filters"));

const goBack = (destination: GalleryDestination) => {
    const send = vi.fn<(action: NavigationAction) => void>();
    const preferences = {
        setAlbumOpenedFromOverview: vi.fn(),
        setAlbumFilter: vi.fn(),
        setAlbumSearchQuery: vi.fn(),
        albumOpenedFromOverview: undefined,
        albumSearchQuery: "",
    } as unknown as ReturnType<typeof useGalleryPreferences>;
    const Probe = () => {
        useAlbumActions({
            library: initialGalleryState,
            navigation: { destination, placeSelectionRevision: 0 },
            send,
            preferences,
            authenticateUser: () => Promise.resolve(true),
            remoteFilesPull: () => Promise.resolve(),
        }).backToAlbums();
        return null;
    };
    renderToStaticMarkup(<Probe />);
    return send.mock.calls.map(([action]) => action);
};

describe("Back from albums nested in Hidden and Archive", () => {
    test.each([
        ["hidden-albums", PseudoCollectionID.hiddenItems],
        ["archive-albums", PseudoCollectionID.archiveItems],
    ] as const)("%s album returns to its overview", (albumMode, overviewID) => {
        const [action] = goBack({
            section: "albums",
            albumMode,
            collectionID: 10,
        });
        expect(action).toMatchObject({
            type: "showCollectionSummary",
            collectionSummaryID: overviewID,
        });
    });

    test("the Archive overview itself still returns to the album groups", () => {
        const [action] = goBack({
            section: "albums",
            albumMode: "archive-albums",
            collectionID: PseudoCollectionID.archiveItems,
        });
        expect(action).toEqual({
            type: "showAlbumOverview",
            albumFilter: "ente",
        });
    });
});
