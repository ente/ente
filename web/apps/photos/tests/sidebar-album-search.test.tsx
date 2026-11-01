import { ThemeProvider } from "@mui/material";
import { photosTheme } from "ente-base/components/utils/theme";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import type { ComponentProps } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, test, vi } from "vitest";
import {
    AlbumsNavigation,
    type AlbumsNavigationProps,
} from "../src/components/gallery/AlbumsNavigation";
import { LinksNavigation } from "../src/components/gallery/LinksNavigation";
import {
    PhotosNavigationContext,
    type PhotosNavigationActions,
} from "../src/components/gallery/PhotosNavigationContext";
import { useAlbumNavigationData } from "../src/components/gallery/use-album-navigation-data";

const viewport = vi.hoisted(() => ({ scrollToEnd: false }));

vi.mock("react-window", async (importOriginal) => {
    const actual = await importOriginal<typeof import("react-window")>();
    const { createElement } = await import("react");
    return {
        ...actual,
        VariableSizeList: (
            props: ComponentProps<typeof actual.VariableSizeList>,
        ) => {
            let initialScrollOffset = 0;
            if (viewport.scrollToEnd) {
                if (typeof props.height != "number")
                    throw new Error(
                        "The test viewport must have a numeric height",
                    );
                for (let index = 0; index < props.itemCount; index++)
                    initialScrollOffset += props.itemSize(index);
                initialScrollOffset = Math.max(
                    0,
                    initialScrollOffset - props.height,
                );
            }
            return createElement(actual.VariableSizeList, {
                ...props,
                initialScrollOffset,
            });
        },
    };
});

vi.mock("@/components/CollectionsSortOptions", () => ({
    CollectionsSortOptions: () => null,
}));
vi.mock("@/components/PeopleSortOptions", () => ({
    PeopleSortOptions: () => null,
}));
vi.mock("@/utils/album-filters", () => import("../src/utils/album-filters"));
vi.mock("i18next", () => {
    const translations: Record<string, string> = {
        section_uncategorized: "Uncategorized",
        section_hidden: "Hidden",
        section_archive: "Archive",
        section_trash: "Trash",
    };
    return { t: (key: string) => translations[key] ?? key };
});
vi.mock("ente-new/photos/components/Tiles", () => ({
    ItemCard: () => null,
    PreviewItemTile: "div",
}));
vi.mock("react-virtualized-auto-sizer", () => ({
    default: ({
        children,
    }: {
        children: (size: { width: number; height: number }) => React.ReactNode;
    }) => children({ width: 300, height: 400 }),
}));

const owned: CollectionSummary = {
    id: 1,
    name: "Family",
    type: "album",
    attributes: new Set(),
    fileCount: 1,
    latestFile: undefined,
    coverFile: undefined,
    updationTime: undefined,
    sortPriority: 0,
};
const shared: CollectionSummary = {
    ...owned,
    id: 2,
    name: "Holiday album",
    attributes: new Set(["sharedOutgoing"]),
};
const link: CollectionSummary = {
    ...owned,
    id: 3,
    name: "Trip link",
    attributes: new Set(["quickLink", "sharedViaLink"]),
};
const albums = [owned, shared, link];

const renderSearch = (
    query: string,
    albumFilter: AlbumsNavigationProps["albumFilter"] = "ente",
    mode: AlbumsNavigationProps["mode"] | "links" = "albums",
    summaries = mode == "links" ? [link] : albums,
    scrollToEnd = false,
) => {
    const props: Omit<AlbumsNavigationProps, "mode"> = {
        albumExpansion: { value: albumFilter, onChange: vi.fn() },
        albumFilter,
        albumSearchQuery: query,
        collectionSummaries: [],
        visibleAlbumFilters: [],
        uncategorizedCollectionSummaryID: 99,
        activeCollectionID: undefined,
        collectionsSortBy: "updation-time-desc",
        collapsed: false,
        mobileDrawerProps: { open: false, onClose: vi.fn() },
        onAlbumSearchQueryChange: vi.fn(),
        onCreateAlbum: vi.fn(),
        onChangeCollectionsSortBy: vi.fn(),
    };
    const navigation: PhotosNavigationActions = {
        goHome: vi.fn(),
        changeMode: vi.fn(() => true),
        showLibraryMap: vi.fn(),
        showCollectionMap: vi.fn(),
        selectPlace: vi.fn(),
        showCollectionSummary: vi.fn(() => Promise.resolve(true)),
        selectCollection: vi.fn(),
        selectCollectionFromViewer: vi.fn(),
        openOverviewAlbum: vi.fn(),
        showAlbumOverview: vi.fn(),
        backToAlbums: vi.fn(),
        showLinksOverview: vi.fn(() => true),
        showPeople: vi.fn(() => true),
        selectPerson: vi.fn(),
        backToPeople: vi.fn(),
        selectSearchOption: vi.fn(),
        showCleanupView: vi.fn(),
    };
    const Sidebar = () => {
        const data = useAlbumNavigationData({
            ...props,
            mode: mode == "links" ? undefined : mode,
            collectionSummaries: new Map(summaries.map((cs) => [cs.id, cs])),
        });
        return (
            <ThemeProvider theme={photosTheme}>
                <PhotosNavigationContext.Provider value={navigation}>
                    {mode == "links" ? (
                        <LinksNavigation
                            {...props}
                            collectionSummaries={summaries.filter((cs) =>
                                cs.name
                                    .toLowerCase()
                                    .includes(query.trim().toLowerCase()),
                            )}
                            selectedLinkID={undefined}
                            searchQuery={query}
                            onSearchQueryChange={vi.fn()}
                        />
                    ) : (
                        <AlbumsNavigation
                            mode={mode}
                            {...props}
                            {...data}
                            collectionSummaries={
                                data.sidebarCollectionSummaries
                            }
                        />
                    )}
                </PhotosNavigationContext.Provider>
            </ThemeProvider>
        );
    };
    // SSR cannot dispatch scroll events; render the real virtualizer at the
    // requested scroll position using its initialScrollOffset instead.
    viewport.scrollToEnd = scrollToEnd;
    try {
        return renderToStaticMarkup(<Sidebar />);
    } finally {
        viewport.scrollToEnd = false;
    }
};

describe("sidebar album search across groups", () => {
    test("keeps shortcuts reachable at the end of a long expanded album group", () => {
        const manyAlbums = Array.from({ length: 100 }, (_, i) => ({
            ...owned,
            id: i + 10,
            name: `Album ${String(i).padStart(3, "0")}`,
        }));
        const html = renderSearch("", "ente", "albums", manyAlbums);
        expect(html).toContain('aria-label="Album 000"');
        expect(html).not.toContain('aria-label="Album 099"');
        for (const label of ["Uncategorized", "Hidden", "Archive", "Trash"])
            expect(html).not.toContain(`aria-label="${label}"`);

        const endHTML = renderSearch("", "ente", "albums", manyAlbums, true);
        expect(endHTML).not.toContain('aria-label="Album 000"');
        expect(endHTML).toContain('aria-label="Album 099"');
        for (const label of ["Uncategorized", "Hidden", "Archive", "Trash"])
            expect(endHTML).toContain(`aria-label="${label}"`);
    });

    test("reveals matching Shared albums while Ente is selected", () => {
        const html = renderSearch("holiday");
        expect(html).toContain('aria-label="shared_albums_title"');
        expect(html).toContain('aria-expanded="true"');
        expect(html).toContain("Holiday album");
        expect(html).not.toContain("no-matches.svg");
    });

    test("reveals matching Ente albums while Shared is selected", () => {
        const html = renderSearch("family", "shared");
        expect(html).toContain('aria-label="Ente"');
        expect(html).toContain("Family");
        expect(html).not.toContain('aria-label="shared_albums_title"');
        expect(html).not.toContain("no-matches.svg");
    });

    test("shows the empty state when neither albums nor shortcuts match", () => {
        const html = renderSearch("missing");
        expect(html).toContain("no-matches.svg");
        for (const label of ["Uncategorized", "Hidden", "Archive", "Trash"])
            expect(html).not.toContain(`aria-label="${label}"`);
    });

    test.each([
        ["  TRASH  ", "Trash"],
        ["hid", "Hidden"],
        ["uncat", "Uncategorized"],
        ["archive", "Archive"],
    ])("shows only the matching shortcut for %j", (query, match) => {
        const html = renderSearch(query);
        expect(html).not.toContain("no-matches.svg");
        for (const label of ["Uncategorized", "Hidden", "Archive", "Trash"])
            if (label == match) expect(html).toContain(`aria-label="${label}"`);
            else expect(html).not.toContain(`aria-label="${label}"`);
    });

    test.each(["", "   "])(
        "restores all group headings for query %j",
        (query) => {
            const html = renderSearch(query);
            expect(html).toContain('aria-label="Ente"');
            expect(html).toContain('aria-label="shared_albums_title"');
            expect(html).toContain("Family");
            expect(html).toContain("Holiday album");
            expect(html).not.toContain("no-matches.svg");
        },
    );
});

describe("Links sidebar search", () => {
    test("shows matching links outside album groups", () => {
        const html = renderSearch("  TRIP  ", "ente", "links");
        expect(html).toContain("Trip link");
        expect(html).toContain('aria-label="search_links"');
        expect(html).not.toContain('aria-label="filter_albums"');
        expect(html).not.toContain("no-matches.svg");
    });

    test("uses the illustrated empty state when no links match", () => {
        const html = renderSearch("missing", "ente", "links");
        expect(html).toContain("no-matches.svg");
        expect(html).not.toContain("Trip link");
        expect(html).not.toContain('aria-label="filter_albums"');
    });
});

describe("Hidden and Archive sidebars", () => {
    test.each(["hidden-albums", "archive-albums"] as const)(
        "%s retains its search field and album cards without shortcuts",
        (mode) => {
            const html = renderSearch("", "ente", mode);
            expect(html).toContain('aria-label="search_in_albums"');
            expect(html).toContain('aria-label="Family"');
            expect(html).toContain('aria-label="Holiday album"');
            const buttons = (html.match(/<button\b[^>]*>/g) ?? []).join("");
            for (const label of ["Uncategorized", "Hidden", "Archive", "Trash"])
                expect(buttons).not.toContain(`aria-label="${label}"`);
            if (mode == "hidden-albums")
                expect(html).toContain('role="group" aria-label="Hidden"');
        },
    );

    test("keeps the Hidden group available when there are no albums", () => {
        const html = renderSearch("", "ente", "hidden-albums", []);
        expect(html).toContain('role="group" aria-label="Hidden"');
        expect(html).toContain('aria-expanded="true"');
        expect(html).toContain(">Hidden<");
    });
});
