import type { LocalUser } from "ente-accounts/services/user";
import { CollectionSubType, type Collection } from "ente-media/collection";
import { ItemVisibility } from "ente-media/file-metadata";
import { describe, expect, test } from "vitest";
import { resolveLinksDestination } from "../src/components/gallery/link-selection";
import {
    initialNavigationState,
    navigationReducer,
    type GalleryNavigationState,
    type NavigationAction,
} from "../src/components/gallery/navigation-state";
import type { GalleryState } from "../src/components/gallery/reducer";
import {
    galleryReducer,
    initialGalleryState,
} from "../src/components/gallery/reducer";
import { visibleQuickLinks } from "../src/utils/quick-links";

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
const library = (collections = [link(1), link(2)]) =>
    galleryReducer(initialGalleryState, {
        type: "mount",
        user: { id: 1 } as LocalUser,
        familyData: undefined,
        collections,
        collectionFiles: [],
        trashItems: [],
    });

const mounted = (collections = [link(1), link(2)]) => ({
    library: library(collections),
    navigation: initialNavigationState,
});
const update = (
    state: ReturnType<typeof mounted>,
    action:
        | Exclude<NavigationAction, { type: "showCollectionSummary" }>
        | { type: "setCollections"; collections: Collection[] },
) =>
    action.type === "setCollections"
        ? { ...state, library: galleryReducer(state.library, action) }
        : { ...state, navigation: navigationReducer(state.navigation, action) };
const view = ({
    library,
    navigation,
}: {
    library: GalleryState;
    navigation: GalleryNavigationState;
}) =>
    navigation.destination.section === "links"
        ? {
              type: "links",
              selectedLinkID: resolveLinksDestination(
                  library,
                  navigation.destination,
              ).collectionID,
          }
        : { type: navigation.destination.section };

describe("quick link membership", () => {
    test("lists owned public quick links, including expired and empty links", () => {
        const expired = link(2);
        expired.publicURLs[0]!.validTill = 1;
        const collections = [
            link(1),
            expired,
            link(3, { owner: { id: 2 } }),
            link(4, { magicMetadata: undefined }),
            link(5, { sharees: [{ id: 2 }] }),
            link(6, { publicURLs: [] }),
            link(7),
        ];
        expect(
            visibleQuickLinks(collections, 1, new Set([7])).map(({ id }) => id),
        ).toEqual([2, 1]);
        expect(collections.map(({ id }) => id)).toEqual([1, 2, 3, 4, 5, 6, 7]);
    });
});

describe("Links navigation", () => {
    test("opens the overview and clears stale photo search state", () => {
        const state = update(
            {
                ...mounted(),
                navigation: {
                    ...initialNavigationState,
                    overlay: { section: "search" },
                },
            },
            { type: "showLinks" },
        );
        expect(view(state)).toEqual({
            type: "links",
            selectedLinkID: undefined,
        });
        expect(state.navigation.destination.collectionID).toBeUndefined();
        expect(state.navigation.overlay).toBeUndefined();
    });

    test("returns to the overview when the Links group is selected again", () => {
        let state = update(mounted(), { type: "selectLink", collectionID: 1 });
        state = update(state, { type: "showLinks" });
        state = update(state, {
            type: "setCollections",
            collections: [link(1), link(2), link(3)],
        });
        expect(view(state)).toEqual({
            type: "links",
            selectedLinkID: undefined,
        });
    });

    test("preserves selection when the list refreshes", () => {
        let state = update(mounted(), { type: "selectLink", collectionID: 1 });
        state = update(state, {
            type: "setCollections",
            collections: [link(1, { name: "Updated" }), link(2), link(3)],
        });
        expect(view(state)).toEqual({ type: "links", selectedLinkID: 1 });
        expect(state.library.normalCollectionSummaries.get(1)?.name).toBe(
            "Updated",
        );
    });

    test.each(["removed", "hidden", "unlinked", "shared"])(
        "reconciles a selected link that becomes %s",
        (change) => {
            let state = update(mounted(), {
                type: "selectLink",
                collectionID: 2,
            });
            const updated = link(2);
            if (change == "hidden")
                updated.magicMetadata!.data.visibility = ItemVisibility.hidden;
            if (change == "unlinked") updated.publicURLs = [];
            if (change == "shared") updated.sharees = [{ id: 2 }];
            state = update(state, {
                type: "setCollections",
                collections:
                    change == "removed" ? [link(1)] : [link(1), updated],
            });
            expect(view(state)).toEqual({
                type: "links",
                selectedLinkID: undefined,
            });
        },
    );

    test("keeps an empty Links view after removing the final link", () => {
        let state = update(mounted([link(1)]), { type: "showLinks" });
        state = update(state, { type: "setCollections", collections: [] });
        expect(view(state)).toEqual({
            type: "links",
            selectedLinkID: undefined,
        });
        state = update(state, {
            type: "setCollections",
            collections: [link(3)],
        });
        expect(view(state)).toEqual({
            type: "links",
            selectedLinkID: undefined,
        });
    });

    test("does not open a hidden link by an explicit ID", () => {
        const hidden = link(3);
        hidden.magicMetadata!.data.visibility = ItemVisibility.hidden;
        const state = update(mounted([link(1), hidden]), {
            type: "selectLink",
            collectionID: 3,
        });
        expect(view(state)).toEqual({
            type: "links",
            selectedLinkID: undefined,
        });
    });

    test("supports returning to Home and People", () => {
        let state = update(mounted(), { type: "showLinks" });
        state = update(state, { type: "showAll" });
        expect(view(state).type).toBe("albums");
        state = update(state, { type: "showLinks" });
        state = update(state, { type: "showPeople" });
        expect(view(state).type).toBe("people");
    });
});
