import type { LocalUser } from "ente-accounts/services/user";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { expect, test, vi } from "vitest";
import { createGalleryHistory } from "../src/components/gallery/navigation/gallery-history";
import {
    homeDestination,
    initialNavigationState,
    navigationReducer,
} from "../src/components/gallery/navigation/navigation-state";
import { initialGalleryState } from "../src/components/gallery/reducer";

const summaries = (ids: number[]) =>
    new Map(
        ids.map((id) => [
            id,
            {
                id,
                name: `Album ${id}`,
                type: "album",
                attributes: new Set(),
                fileCount: 0,
                latestFile: undefined,
                coverFile: undefined,
                updationTime: undefined,
                sortPriority: 0,
            } satisfies CollectionSummary,
        ]),
    );
const library = {
    ...initialGalleryState,
    user: { id: 1 } as LocalUser,
    normalCollectionSummaries: summaries([0, 1, 2, 4, 5]),
    hiddenCollectionSummaries: summaries([-4, 3]),
    archivedCollectionSummaries: summaries([-1, 4]),
};
library.normalCollectionSummaries.get(5)!.attributes.add("archived");
const album = (collectionID: number) => ({ ...homeDestination, collectionID });

test("Back and Forward select regular albums and Home without appending history", () => {
    const history = createGalleryHistory();
    let navigation = initialNavigationState;
    const entries = ["/gallery"];
    let index = 0;
    let asPath = entries[0]!;
    const push = vi.fn((href: string) => {
        entries.splice(++index, entries.length, href);
        asPath = href;
    });
    const render = () => {
        if (history.isRestoring(asPath, navigation.destination)) return;
        const id = navigation.destination.collectionID;
        const href = id === 0 ? "/gallery" : `/gallery?collection=${id}`;
        if (asPath !== href) push(href);
    };
    const navigate = (collectionSummaryID: number) => {
        navigation = navigationReducer(navigation, {
            type: "showCollectionSummary",
            collectionSummaryID,
            library,
        });
    };
    for (const id of [1, 2]) {
        navigate(id);
        render();
    }
    push.mockClear();
    for (const [step, id] of [
        [-1, 1],
        [-1, 0],
        [1, 1],
        [1, 2],
    ] as const) {
        const as = entries[(index += step)]!;
        history.restore(as, navigation.destination, library, navigate);
        render();
        asPath = as;
        render();
        render();
        expect(navigation.destination.collectionID).toBe(id);
    }
    expect(push).not.toHaveBeenCalled();
    expect(entries).toEqual([
        "/gallery",
        "/gallery?collection=1",
        "/gallery?collection=2",
    ]);
    navigate(1);
    render();
    expect(push).toHaveBeenCalledExactlyOnceWith("/gallery?collection=1");
});

test.each(["router", "selection"])(
    "URL writes wait for both updates when %s commits first",
    (first) => {
        const history = createGalleryHistory();
        const from = album(2);
        const navigate = vi.fn();
        history.restore("/gallery?collection=1", from, library, navigate);
        expect(navigate).toHaveBeenCalledExactlyOnceWith(1);
        expect(history.isRestoring("/gallery?collection=2", from)).toBe(true);
        expect(
            history.isRestoring(
                first === "router"
                    ? "/gallery?collection=1"
                    : "/gallery?collection=2",
                first === "selection" ? album(1) : from,
            ),
        ).toBe(true);
        expect(history.isRestoring("/gallery?collection=1", album(1))).toBe(
            true,
        );
        expect(history.isRestoring("/gallery?collection=1", album(1))).toBe(
            false,
        );
    },
);

test.each([
    "/credentials",
    "/gallery?collection=-4",
    "/gallery?collection=3",
    "/gallery?collection=-1",
    "/gallery?collection=4",
    "/gallery?collection=5",
    "/gallery?collection=-2",
    "/gallery?collection=999",
    "/gallery?collection=invalid",
    "/gallery?collection=1.5",
    "/gallery?collection=9007199254740992",
    "/gallery?collection=1&collection=2",
])("history leaves unsupported destination %s unchanged", (as) => {
    const history = createGalleryHistory();
    const navigate = vi.fn();
    history.restore(as, homeDestination, library, navigate);
    expect(navigate).not.toHaveBeenCalled();
    expect(history.isRestoring(as, homeDestination)).toBe(false);
});

test("explicit navigation supersedes an unfinished history update", () => {
    const history = createGalleryHistory();
    history.restore("/gallery?collection=1", album(2), library, vi.fn());
    expect(history.isRestoring("/gallery?collection=1", homeDestination)).toBe(
        false,
    );
});

test("a later unsupported history entry clears an unfinished update", () => {
    const history = createGalleryHistory();
    const from = album(2);
    history.restore("/gallery?collection=1", from, library, vi.fn());
    history.restore("/gallery?collection=-4", from, library, vi.fn());
    expect(history.isRestoring("/gallery?collection=-4", from)).toBe(false);
});
