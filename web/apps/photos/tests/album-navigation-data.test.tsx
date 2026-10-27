import {
    PseudoCollectionID,
    type CollectionSummary,
} from "ente-new/photos/services/collection-summary";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, test, vi } from "vitest";
import { useAlbumNavigationData } from "../src/components/gallery/use-album-navigation-data";

vi.mock("@/utils/album-filters", () => import("../src/utils/album-filters"));

const album = (
    id: number,
    overrides: Partial<CollectionSummary> = {},
): CollectionSummary => ({
    id,
    name: `Album ${id}`,
    type: "album",
    attributes: new Set(),
    fileCount: 1,
    latestFile: undefined,
    coverFile: undefined,
    updationTime: id,
    sortPriority: 0,
    ...overrides,
});

const navigationData = (
    summaries: CollectionSummary[],
    options: Partial<Parameters<typeof useAlbumNavigationData>[0]> = {},
) => {
    let result: ReturnType<typeof useAlbumNavigationData>;
    const Gallery = () => {
        result = useAlbumNavigationData({
            mode: "albums",
            collectionSummaries: new Map(summaries.map((cs) => [cs.id, cs])),
            uncategorizedCollectionSummaryID: 99,
            albumFilter: "ente",
            albumSearchQuery: "",
            ...options,
        });
        return null;
    };
    renderToStaticMarkup(<Gallery />);
    return result!;
};

const ids = (summaries: CollectionSummary[]) => summaries.map(({ id }) => id);

describe("album navigation data", () => {
    test("keeps priority albums first and shares the remaining order with the overview", () => {
        const summaries = [
            album(1),
            album(2, { sortPriority: 7, attributes: new Set(["pinned"]) }),
            album(3),
        ];
        const data = navigationData(summaries);
        expect(data.collectionsSortBy).toBe("updation-time-desc");
        expect(ids(data.sidebarCollectionSummaries)).toEqual([2, 3, 1]);
        expect(ids(data.overviewAlbums)).toEqual([2, 3, 1]);
        expect(ids(summaries)).toEqual([1, 2, 3]);
    });

    test("searches across sidebar groups while the overview follows the selected group", () => {
        const data = navigationData(
            [
                album(1, { name: "Summer" }),
                album(2, {
                    name: "Summer with friends",
                    attributes: new Set(["sharedOutgoing"]),
                }),
                album(3, {
                    name: "Summer wedding",
                    attributes: new Set(["sharedIncoming"]),
                }),
                album(4, { name: "Winter" }),
            ],
            { albumFilter: "shared", albumSearchQuery: "  SUMMER  " },
        );
        expect(ids(data.sidebarCollectionSummaries)).toEqual([3, 2, 1]);
        expect(ids(data.overviewAlbums)).toEqual([2]);
        expect(data.visibleAlbumFilters.map(({ value }) => value)).toEqual([
            "ente",
            "shared",
            "received",
        ]);
    });

    test("excludes system entries but keeps another user's shared Uncategorized album", () => {
        const data = navigationData(
            [
                album(1),
                album(99, {
                    type: "uncategorized",
                    attributes: new Set(["system", "uncategorized"]),
                }),
                album(100, {
                    type: "uncategorized",
                    attributes: new Set([
                        "system",
                        "uncategorized",
                        "sharedIncoming",
                    ]),
                }),
                ...Object.values(PseudoCollectionID).map((id) =>
                    album(id, { attributes: new Set(["system"]) }),
                ),
            ],
            { albumFilter: "received" },
        );
        expect(ids(data.sidebarCollectionSummaries)).toEqual([100, 1]);
        expect(ids(data.overviewAlbums)).toEqual([100]);
    });

    test("keeps the empty-album group available when only one of three empty albums matches", () => {
        const data = navigationData(
            [1, 2, 3].map((id) => album(id, { fileCount: 0 })),
            { albumFilter: "empty-albums", albumSearchQuery: "Album 1" },
        );
        expect(ids(data.overviewAlbums)).toEqual([1]);
        expect(data.visibleAlbumFilters.map(({ value }) => value)).toEqual([
            "ente",
            "empty-albums",
        ]);
    });

    describe.each(["hidden-albums", "archive-albums"] as const)(
        "%s quick links",
        (mode) => {
            const summaries = () => {
                const quickLink = album(1, {
                    name: "Trip link",
                    attributes: new Set(["quickLink"]),
                });
                if (mode == "archive-albums")
                    quickLink.attributes.add("archived");
                return [
                    quickLink,
                    album(2, { name: "Family" }),
                    album(3, {
                        attributes: new Set(["hideFromCollectionBar"]),
                    }),
                    album(PseudoCollectionID.hiddenItems),
                    album(PseudoCollectionID.archiveItems),
                ];
            };

            test("lists quick links alongside albums while omitting system entries", () => {
                const data = navigationData(summaries(), { mode });
                expect(ids(data.sidebarCollectionSummaries)).toEqual([2, 1]);
            });

            test("finds quick links using the sidebar search", () => {
                const data = navigationData(summaries(), {
                    mode,
                    albumSearchQuery: "  TRIP  ",
                });
                expect(ids(data.sidebarCollectionSummaries)).toEqual([1]);
            });
        },
    );
});
