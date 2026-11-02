import { fetchFeedData } from "@/services/feed-fetch";
import { Window } from "happy-dom";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { useFeed } from "../src/components/gallery/sections/feed/use-feed";
import type { GallerySectionProps } from "../src/components/gallery/sections/types";
import type { FeedSocialData } from "../src/services/feed";

vi.mock("@/services/feed", () => import("../src/services/feed"));
vi.mock("@/services/feed-fetch", () => ({ fetchFeedData: vi.fn() }));
vi.mock("ente-base/log", () => ({ default: { warn: vi.fn() } }));

type Library = GallerySectionProps["library"];
let root: Root;
let library: Library;
let feed: ReturnType<typeof useFeed>;
const onRemotePull = vi.fn<GallerySectionProps["operations"]["onRemotePull"]>();
const pending = () => {
    let resolve!: () => void;
    let reject!: (error: Error) => void;
    const promise = new Promise<void>((res, rej) => {
        resolve = res;
        reject = rej;
    });
    return { promise, resolve, reject };
};
const social = (id: string, fileID = 1) => ({
    socialByCollection: {
        10: {
            comments: [
                {
                    id,
                    collectionID: 10,
                    fileID,
                    userID: 2,
                    text: id,
                    createdAt: 100,
                    updatedAt: 100,
                    isDeleted: false,
                },
            ],
            reactions: [],
            anonNames: {},
        } satisfies FeedSocialData,
    },
    failed: false,
});
const Harness = ({ value }: { value: Library }) => {
    feed = useFeed(value, onRemotePull);
    return null;
};
const render = async () => {
    await act(async () => {
        root.render(<Harness value={library} />);
        await Promise.resolve();
    });
};

beforeEach(() => {
    vi.resetAllMocks();
    const window = new Window();
    vi.stubGlobal("window", window);
    vi.stubGlobal("document", window.document);
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    root = createRoot(document.createElement("div"));
    library = {
        user: { id: 1 },
        collections: [{ id: 10, name: "Album", owner: { id: 1 } }],
        collectionFiles: [
            { id: 1, collectionID: 10, ownerID: 1, metadata: { fileType: 0 } },
        ],
        hiddenCollectionIDs: new Set(),
        hiddenFileIDs: new Set(),
        tempHiddenFileIDs: new Set(),
        tempDeletedFileIDs: new Set(),
    } as unknown as Library;
    onRemotePull.mockResolvedValue();
    vi.mocked(fetchFeedData).mockResolvedValue({
        socialByCollection: {},
        failed: false,
    });
});

afterEach(async () => {
    await act(async () => {
        root.unmount();
        await Promise.resolve();
    });
    vi.unstubAllGlobals();
});

test("refresh waits for library sync, fetches once and updates the Feed", async () => {
    await render();
    expect(feed.refreshing).toBe(false);
    vi.mocked(fetchFeedData)
        .mockClear()
        .mockResolvedValue(social("new-comment"));
    const pull = pending();
    onRemotePull.mockReturnValue(pull.promise);
    let refresh!: Promise<void>;
    await act(async () => {
        refresh = feed.refresh();
        await Promise.resolve();
    });
    expect(feed.refreshing).toBe(true);
    expect(fetchFeedData).not.toHaveBeenCalled();
    expect(onRemotePull).toHaveBeenCalledWith({
        silent: true,
        strict: true,
        source: "feed-refresh",
    });
    await act(async () => {
        pull.resolve();
        await refresh;
    });
    expect(fetchFeedData).toHaveBeenCalledOnce();
    expect(feed.items).toMatchObject([
        { type: "comment", commentID: "new-comment" },
    ]);
    expect(feed.refreshing).toBe(false);
    expect(feed.failed).toBe(false);
});

test("library updates during a pull do not cause duplicate social fetches", async () => {
    await render();
    vi.mocked(fetchFeedData)
        .mockClear()
        .mockResolvedValue(social("new-file-comment", 2));
    const pull = pending();
    onRemotePull.mockReturnValue(pull.promise);
    let refresh!: Promise<void>;
    await act(async () => {
        refresh = feed.refresh();
        await Promise.resolve();
    });
    library = {
        ...library,
        collections: [...library.collections],
        hiddenCollectionIDs: new Set(),
    };
    await render();
    library = {
        ...library,
        collectionFiles: [{ ...library.collectionFiles[0]!, id: 2 }],
        hiddenCollectionIDs: new Set(),
    };
    await render();
    expect(fetchFeedData).not.toHaveBeenCalled();
    await act(async () => {
        pull.resolve();
        await refresh;
    });
    expect(fetchFeedData).toHaveBeenCalledOnce();
    expect(fetchFeedData).toHaveBeenCalledWith(
        library.collections,
        expect.any(AbortSignal),
    );
    expect(feed.items).toMatchObject([
        { commentID: "new-file-comment", fileID: 2 },
    ]);
});

test("a failed library pull still fetches social activity and preserves the failure state", async () => {
    await render();
    vi.mocked(fetchFeedData)
        .mockClear()
        .mockResolvedValue(social("available-comment"));
    onRemotePull.mockRejectedValueOnce(new Error("Library unavailable"));
    await act(async () => {
        await feed.refresh();
    });
    expect(fetchFeedData).toHaveBeenCalledOnce();
    expect(feed.items).toMatchObject([{ commentID: "available-comment" }]);
    expect(feed.refreshing).toBe(false);
    expect(feed.failed).toBe(true);
    onRemotePull.mockResolvedValueOnce();
    vi.mocked(fetchFeedData)
        .mockClear()
        .mockResolvedValue(social("retried-comment"));
    await act(async () => {
        await feed.refresh();
    });
    expect(fetchFeedData).toHaveBeenCalledOnce();
    expect(feed.items).toMatchObject([{ commentID: "retried-comment" }]);
    expect(feed.failed).toBe(false);
});

test("social fetch failure reaches the Feed and a successful retry clears it", async () => {
    await render();
    vi.mocked(fetchFeedData).mockRejectedValueOnce(
        new Error("Social unavailable"),
    );
    await act(async () => {
        await feed.refresh();
    });
    expect(feed.failed).toBe(true);
    expect(feed.refreshing).toBe(false);
    vi.mocked(fetchFeedData).mockResolvedValueOnce(social("recovered"));
    await act(async () => {
        await feed.refresh();
    });
    expect(feed.items).toMatchObject([{ commentID: "recovered" }]);
    expect(feed.failed).toBe(false);
});
