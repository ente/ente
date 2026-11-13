import type {
    CollectionSummary,
    CollectionSummaryAttribute,
} from "ente-new/photos/services/collection-summary";
import { describe, expect, test } from "vitest";
import {
    filterAlbumSummaries,
    matchesAlbumFilter,
    visibleAlbumFilters,
    type AlbumFilter,
} from "../src/utils/album-filters";

const album = (
    id: number,
    attributes: CollectionSummaryAttribute[] = [],
    fileCount = 1,
): CollectionSummary => ({
    id,
    type: "album",
    attributes: new Set(attributes),
    name: `Album ${id}`,
    fileCount,
    latestFile: undefined,
    coverFile: undefined,
    updationTime: undefined,
    sortPriority: 0,
});

describe("album filters shared by the dialog and sidebar", () => {
    test("Ente matches mobile membership, including shared, received, and empty albums", () => {
        const albums = [
            album(1),
            { ...album(2, ["userFavorites"]), type: "userFavorites" as const },
            album(3, ["sharedOutgoing", "shared"]),
            album(4, ["sharedIncoming"]),
            album(5, ["sharedViaLink"]),
            album(6, ["quickLink"]),
            album(7, [], 0),
            album(8, ["archived"], 0),
            album(9, ["system"]),
            album(10, ["shared"]),
            {
                ...album(11, ["userFavorites"], 0),
                type: "userFavorites" as const,
            },
            {
                ...album(12, ["sharedIncoming", "favorites"], 0),
                type: "sharedIncoming" as const,
            },
            album(13, ["sharedIncoming", "uncategorized"]),
            {
                ...album(
                    14,
                    ["system", "uncategorized", "sharedOutgoing", "shared"],
                    0,
                ),
                type: "uncategorized" as const,
            },
            album(15, ["sharedOutgoing", "shared", "archived"]),
            album(16, ["sharedIncoming", "shared", "archived"]),
        ];
        expect(
            albums
                .filter((cs) => matchesAlbumFilter(cs, "ente"))
                .map(({ id }) => id),
        ).toEqual([1, 2, 3, 4, 5, 7, 10, 12]);
        expect(matchesAlbumFilter(albums[13]!, "shared")).toBe(true);
        expect(matchesAlbumFilter(albums[12]!, "received")).toBe(true);
        expect(matchesAlbumFilter(albums[14]!, "shared")).toBe(false);
        expect(matchesAlbumFilter(albums[15]!, "received")).toBe(false);
    });

    test("separates outgoing sharing, incoming sharing, and quick links", () => {
        const albums = [
            album(1),
            album(2, ["sharedOutgoing", "shared"]),
            album(3, ["sharedIncoming", "sharedViaLink", "shared"]),
            album(4, ["sharedViaLink", "shared"]),
            album(5, ["quickLink", "sharedViaLink", "shared"]),
        ];
        const ids = (filter: AlbumFilter) =>
            albums
                .filter((cs) => matchesAlbumFilter(cs, filter))
                .map(({ id }) => id);
        expect(ids("ente")).toEqual([1, 2, 3, 4]);
        expect(ids("shared")).toEqual([2, 4]);
        expect(ids("received")).toEqual([3]);
        expect(albums.map(({ id }) => id)).toEqual([1, 2, 3, 4, 5]);
    });

    test("empty albums exclude shared, archived, system, and favorites collections", () => {
        expect(matchesAlbumFilter(album(1, [], 0), "empty-albums")).toBe(true);
        expect(
            matchesAlbumFilter(
                { ...album(2, [], 0), type: "folder" },
                "empty-albums",
            ),
        ).toBe(true);
        for (const attribute of ["shared", "archived", "system"] as const) {
            expect(
                matchesAlbumFilter(album(3, [attribute], 0), "empty-albums"),
            ).toBe(false);
        }
        expect(
            matchesAlbumFilter(
                { ...album(4, [], 0), type: "userFavorites" },
                "empty-albums",
            ),
        ).toBe(false);
        expect(matchesAlbumFilter(album(5), "empty-albums")).toBe(false);
    });

    test("shows available categories in pill order and requires three eligible empty albums", () => {
        const albums = [
            album(1, [], 0),
            album(2, [], 0),
            album(3, ["shared"], 0),
        ];
        expect(visibleAlbumFilters(albums).map(({ value }) => value)).toEqual([
            "ente",
        ]);
        albums.push(
            album(4, [], 0),
            album(5, ["sharedOutgoing"]),
            album(6, ["sharedIncoming"]),
            album(7, ["quickLink"]),
        );
        expect(visibleAlbumFilters(albums).map(({ value }) => value)).toEqual([
            "ente",
            "shared",
            "received",
            "empty-albums",
        ]);
        expect(visibleAlbumFilters([]).map(({ value }) => value)).toEqual([
            "ente",
        ]);
    });

    test("search shows only groups containing a matching album", () => {
        const albums = [
            { ...album(1), name: "Summer" },
            { ...album(2, ["sharedOutgoing"]), name: "Winter" },
            { ...album(3, ["sharedIncoming"]), name: "Winter" },
            { ...album(4, ["quickLink"]), name: "Holiday link" },
        ];
        const groups = (query: string) =>
            visibleAlbumFilters(albums, query).map(({ value }) => value);
        expect(groups("holiday")).toEqual([]);
        expect(groups("  WINTER  ")).toEqual(["ente", "shared", "received"]);
        expect(groups("summer")).toEqual(["ente"]);
        expect(groups("missing")).toEqual([]);
        expect(groups("   ")).toEqual(["ente", "shared", "received"]);
    });

    test("search preserves empty-group availability when only one empty album matches", () => {
        const albums = [album(1, [], 0), album(2, [], 0), album(3, [], 0)];
        expect(
            visibleAlbumFilters(albums, "Album 1").map(({ value }) => value),
        ).toEqual(["ente", "empty-albums"]);
        expect(
            visibleAlbumFilters(albums.slice(0, 2), "Album 1").map(
                ({ value }) => value,
            ),
        ).toEqual(["ente"]);
    });
});

describe("album overview search", () => {
    test("combines group membership and a trimmed case-insensitive name query", () => {
        const owned = { ...album(1), name: "Summer holiday" };
        const shared = {
            ...album(2, ["sharedOutgoing"]),
            name: "SUMMER with friends",
        };
        const received = {
            ...album(3, ["sharedIncoming"]),
            name: "Summer wedding",
        };
        expect(
            filterAlbumSummaries(
                [owned, shared, received],
                "shared",
                "  summer  ",
            ),
        ).toEqual([shared]);
        expect(
            filterAlbumSummaries(
                [owned, shared, received],
                "received",
                "SUMMER",
            ),
        ).toEqual([received]);
        expect(
            filterAlbumSummaries([owned, shared], "ente", "missing"),
        ).toEqual([]);
    });

    test("preserves the caller's shared sort order and excludes archived albums", () => {
        const albums = [album(3), album(1), album(2, ["archived"])];
        expect(
            filterAlbumSummaries(albums, "ente", "").map(({ id }) => id),
        ).toEqual([3, 1]);
        expect(albums.map(({ id }) => id)).toEqual([3, 1, 2]);
    });
});
