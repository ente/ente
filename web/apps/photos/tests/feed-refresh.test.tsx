import { renderToStaticMarkup } from "react-dom/server";
import { expect, test, vi } from "vitest";
import { useFeed } from "../src/components/gallery/sections/feed/use-feed";
import type { GallerySectionProps } from "../src/components/gallery/sections/types";

vi.mock("@/services/feed", () => ({ buildFeedItems: () => [] }));
vi.mock("@/services/feed-fetch", () => ({ fetchFeedData: vi.fn() }));
vi.mock("ente-base/log", () => ({ default: { warn: vi.fn() } }));

test("refresh waits for library sync and handles library failures", async () => {
    let finishSync!: () => void;
    const onRemotePull = vi.fn(
        () =>
            new Promise<void>((resolve) => {
                finishSync = resolve;
            }),
    );
    let feed!: ReturnType<typeof useFeed>;
    const library = {
        user: { id: 1 },
        collections: [],
        hiddenCollectionIDs: new Set(),
        hiddenFileIDs: new Set(),
        tempHiddenFileIDs: new Set(),
        tempDeletedFileIDs: new Set(),
    } as unknown as GallerySectionProps["library"];
    const Harness = () => {
        feed = useFeed(library, onRemotePull);
        return null;
    };
    renderToStaticMarkup(<Harness />);
    let finished = false;
    const refresh = feed.refresh().then(() => {
        finished = true;
    });
    expect(onRemotePull).toHaveBeenCalledWith({
        silent: true,
        strict: true,
        source: "feed-refresh",
    });
    await Promise.resolve();
    expect(finished).toBe(false);
    finishSync();
    await refresh;
    expect(finished).toBe(true);
    onRemotePull.mockRejectedValueOnce(new Error("Offline"));
    await expect(feed.refresh()).resolves.toBeUndefined();
});
