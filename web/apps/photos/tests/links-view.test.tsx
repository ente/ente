import type { LocalUser } from "ente-accounts/services/user";
import { CollectionSubType, type Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { ItemVisibility } from "ente-media/file-metadata";
import type { ComponentProps, ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, expect, test, vi } from "vitest";
import {
    galleryReducer,
    initialGalleryState,
} from "../src/components/gallery/reducer";
import { AlbumsOverview } from "../src/components/gallery/sections/albums/AlbumsOverview";
import { LinksView } from "../src/components/gallery/sections/links/LinksView";
import { PublicLinkDetails } from "../src/components/gallery/sections/links/PublicLinkDetails";

vi.mock("@/utils/quick-links", () => import("../src/utils/quick-links"));
vi.mock("../src/components/gallery/sections/albums/AlbumsOverview", () => ({
    AlbumsOverview: vi.fn(() => null),
}));
vi.mock("../src/components/gallery/sections/links/PublicLinkDetails", () => ({
    PublicLinkDetails: vi.fn(() => null),
}));

vi.mock("../src/components/gallery/sections/links/LinksNavigation", () => ({
    LinksNavigation: vi.fn(() => null),
}));
vi.mock("../src/components/gallery/navigation/GallerySectionLayout", () => ({
    GallerySectionLayout: ({
        navigation,
        children,
    }: {
        navigation: ReactNode;
        children: ReactNode;
    }) => (
        <>
            {navigation}
            {children}
        </>
    ),
}));
beforeEach(() => vi.clearAllMocks());

const link = (id: number, overrides: Partial<Collection> = {}): Collection => ({
    id,
    name: `Link ${id}`,
    type: "album",
    owner: { id: 1 },
    key: "test-key",
    sharees: [],
    updationTime: id,
    magicMetadata: {
        version: 1,
        count: 1,
        data: { subType: CollectionSubType.quicklink },
    },
    publicURLs: [
        {
            url: `https://albums.ente.com/?t=${id}`,
            validTill: 0,
            deviceLimit: 0,
            enableDownload: true,
            enableCollect: false,
            enableComment: false,
            enableJoin: false,
            passwordEnabled: false,
        },
    ],
    ...overrides,
});

const file = (id: number, collectionID = 1): EnteFile => ({
    id,
    collectionID,
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
});

const props = (
    collections = [link(1), link(2)],
    collectionFiles: EnteFile[] = [],
): ComponentProps<typeof LinksView> => {
    const user = { id: 1 } as LocalUser;
    const state = galleryReducer(initialGalleryState, {
        type: "mount",
        user,
        familyData: undefined,
        collections,
        collectionFiles,
        trashItems: [],
    });
    return {
        presentation: {
            collapsed: false,
            mobile: false,
            mobileDrawerProps: { open: false, onClose: vi.fn() },
            reduceMotion: true,
            isFirstLoad: false,
            isOffline: false,
        },
        onSearchQueryChange: vi.fn(),
        onChangeSortBy: vi.fn(),
        user,
        collections,
        collectionFiles: state.collectionFiles,
        collectionSummaries: state.normalCollectionSummaries,
        hiddenCollectionIDs: state.hiddenCollectionIDs,
        hiddenFileIDs: state.hiddenFileIDs,
        tempDeletedFileIDs: state.tempDeletedFileIDs,
        tempHiddenFileIDs: state.tempHiddenFileIDs,
        uncategorizedCollectionSummaryID:
            state.uncategorizedCollectionSummaryID,
        selectedLinkID: undefined,
        searchQuery: "",
        sortBy: "updation-time-desc",
        setBlockingLoad: vi.fn(),
        onRemotePull: vi.fn().mockResolvedValue(undefined),
    };
};

test("derives the overview from library data with shared sorting and search", () => {
    const input = props([
        link(1, { name: "Summer Alpha" }),
        link(2, { name: "Summer Beta" }),
        link(3, { name: "Winter" }),
        link(4, { name: "Summer regular album", magicMetadata: undefined }),
        link(5, { name: "Summer removed link", publicURLs: [] }),
    ]);
    const summaries = new Map(input.collectionSummaries);
    summaries.set(2, { ...summaries.get(2)!, sortPriority: 7 });

    renderToStaticMarkup(
        <LinksView
            {...input}
            collectionSummaries={summaries}
            searchQuery="  SUMMER  "
            sortBy="name-asc"
        />,
    );

    const overview = vi.mocked(AlbumsOverview).mock.calls[0]![0];
    expect(overview.albums.map(({ id }) => id)).toEqual([2, 1]);
    expect(overview.filter).toBe("links");
    expect(overview.searchQuery).toBe("  SUMMER  ");
    expect(overview.sortBy).toBe("name-asc");
    expect(overview.onRemotePull).toBe(input.onRemotePull);
    expect(PublicLinkDetails).not.toHaveBeenCalled();
    expect(summaries.get(2)?.sortPriority).toBe(7);
    expect(input.collections.map(({ id }) => id)).toEqual([1, 2, 3, 4, 5]);
});

test.each([0, 17])(
    "filters detail files and uses the summary count of %i and its cover",
    (fileCount) => {
        const archived = file(6);
        archived.magicMetadata = {
            version: 1,
            count: 1,
            data: { visibility: ItemVisibility.archived },
        };
        const input = props(undefined, [
            file(1),
            file(2),
            file(3),
            file(4),
            file(5, 2),
            archived,
        ]);
        const coverFile = file(7);
        const summaries = new Map(input.collectionSummaries);
        summaries.set(1, { ...summaries.get(1)!, fileCount, coverFile });

        renderToStaticMarkup(
            <LinksView
                {...input}
                selectedLinkID={1}
                collectionSummaries={summaries}
                hiddenFileIDs={new Set([2])}
                tempDeletedFileIDs={new Set([3])}
                tempHiddenFileIDs={new Set([4])}
            />,
        );

        const details = vi.mocked(PublicLinkDetails).mock.calls[0]![0];
        expect(details.collection.id).toBe(1);
        expect(details.files.map(({ id }) => id).sort()).toEqual([1, 6]);
        expect(details.fileCount).toBe(fileCount);
        expect(details.coverFile).toBe(coverFile);
        expect(details.user).toBe(input.user);
        expect(details.setBlockingLoad).toBe(input.setBlockingLoad);
        expect(details.onRemotePull).toBe(input.onRemotePull);
        expect(AlbumsOverview).not.toHaveBeenCalled();
    },
);

test("uses the filtered detail file count when no summary exists", () => {
    const input = props(undefined, [file(1), file(2), file(3, 2)]);
    renderToStaticMarkup(
        <LinksView
            {...input}
            selectedLinkID={1}
            collectionSummaries={new Map()}
        />,
    );
    const details = vi.mocked(PublicLinkDetails).mock.calls[0]![0];
    expect(details.fileCount).toBe(2);
    expect(details.coverFile).toBeUndefined();
});

test.each(["removed", "unlinked", "hidden", "shared", "other-owner"])(
    "returns to the overview when the selected link is %s",
    (change) => {
        const updated = link(1);
        if (change == "unlinked") updated.publicURLs = [];
        if (change == "shared") updated.sharees = [{ id: 2 }];
        if (change == "other-owner") updated.owner.id = 2;
        const input = props(
            change == "removed" ? [link(2)] : [updated, link(2)],
        );
        renderToStaticMarkup(
            <LinksView
                {...input}
                selectedLinkID={1}
                hiddenCollectionIDs={new Set(change == "hidden" ? [1] : [])}
            />,
        );
        const overview = vi.mocked(AlbumsOverview).mock.calls[0]![0];
        expect(overview.albums.map(({ id }) => id)).toEqual([2]);
        expect(PublicLinkDetails).not.toHaveBeenCalled();
    },
);
