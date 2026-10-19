import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, test, vi } from "vitest";
import {
    GalleryBarAndListHeader,
    type GalleryBarAndListHeaderProps,
} from "../src/components/Collections/GalleryBarAndListHeader";
import type { GalleryBarImplProps } from "../src/components/gallery/BarImpl";

const { renderBar } = vi.hoisted(() => ({
    renderBar: vi.fn<(props: GalleryBarImplProps) => null>(() => null),
}));

vi.mock("@/components/gallery/BarImpl", () => ({ GalleryBarImpl: renderBar }));
vi.mock("@/components/Collections/CollectionShare", () => ({
    CollectionShare: () => null,
}));
vi.mock("@/components/gallery/PeopleHeader", () => ({
    PeopleHeader: () => null,
}));
vi.mock("../src/components/Collections/AlbumCastDialog", () => ({
    AlbumCastDialog: () => null,
}));
vi.mock("../src/components/Collections/CollectionHeader", () => ({
    CollectionHeader: () => null,
}));
vi.mock("../src/components/Collections/CreateAlbumDialog", () => ({
    CreateAlbumDialog: () => null,
}));
vi.mock("@/utils/album-filters", () => import("../src/utils/album-filters"));
vi.mock("@/utils/people-sort", () => import("../src/utils/people-sort"));

const album = (
    id: number,
    name: string,
    attributes: CollectionSummary["attributes"] = new Set(),
): CollectionSummary => ({
    id,
    name,
    type: "album",
    attributes,
    fileCount: 1,
    latestFile: undefined,
    coverFile: undefined,
    updationTime: undefined,
    sortPriority: 0,
});

const renderSidebar = (
    mode: "hidden-albums" | "archive-albums",
    albumSearchQuery = "",
) => {
    const quickLink = album(1, "Trip link", new Set(["quickLink"]));
    if (mode == "archive-albums") quickLink.attributes.add("archived");
    const summaries = [
        quickLink,
        album(2, "Family"),
        album(3, "Hidden system album", new Set(["hideFromCollectionBar"])),
        album(PseudoCollectionID.hiddenItems, "Hidden items"),
        album(PseudoCollectionID.archiveItems, "Archive items"),
    ];
    const props = {
        mode,
        albumFilter: "ente",
        albumSearchQuery,
        barCollectionSummaries: new Map(summaries.map((cs) => [cs.id, cs])),
        uncategorizedCollectionSummaryID: 99,
        people: [],
        peopleSortBy: "name-asc",
        saveGroups: [],
        setActiveCollectionID: vi.fn(),
        mobileDrawerProps: { open: true, onClose: vi.fn() },
    } as unknown as GalleryBarAndListHeaderProps;
    renderToStaticMarkup(<GalleryBarAndListHeader {...props} />);
    return { props, bar: renderBar.mock.lastCall![0] };
};

beforeEach(() => vi.clearAllMocks());

describe.each(["hidden-albums", "archive-albums"] as const)(
    "%s quick links",
    (mode) => {
        test("lists quick links alongside albums while omitting system entries", () => {
            const { bar, props } = renderSidebar(mode);
            expect(bar.collectionSummaries.map(({ id }) => id)).toEqual([1, 2]);
            bar.onSelectCollectionID(1);
            expect(props.setActiveCollectionID).toHaveBeenCalledWith(1);
            expect(props.mobileDrawerProps.onClose).toHaveBeenCalledOnce();
        });

        test("finds quick links using the sidebar search", () => {
            const { bar } = renderSidebar(mode, "  TRIP  ");
            expect(bar.collectionSummaries.map(({ id }) => id)).toEqual([1]);
        });
    },
);
