import type { EnteFile } from "ente-media/file";
import type { SearchSuggestion } from "ente-new/photos/services/search/types";
import { expect, test, vi } from "vitest";
import { createSearchResultsQueue } from "../src/components/gallery/search-results-queue";

const suggestion = (label: string): SearchSuggestion => ({
    type: "fileName",
    label,
    fileIDs: [],
});
const deferred = () => {
    let resolve: (files: EnteFile[]) => void;
    let reject: (error: unknown) => void;
    const promise = new Promise<EnteFile[]>((yes, no) => {
        resolve = yes;
        reject = no;
    });
    return { promise, resolve: resolve!, reject: reject! };
};

test("serializes searches and coalesces pending requests to the latest suggestion", async () => {
    const first = deferred();
    const latest: EnteFile[] = [];
    const search = vi
        .fn()
        .mockReturnValueOnce(first.promise)
        .mockResolvedValueOnce(latest);
    const result = vi.fn();
    const queue = createSearchResultsQueue(search, result, vi.fn());
    const a = suggestion("a"),
        b = suggestion("b"),
        c = suggestion("c");
    queue.enqueue(a);
    queue.enqueue(b);
    queue.enqueue(c);
    expect(search).toHaveBeenCalledExactlyOnceWith(a);
    first.resolve([]);
    await vi.waitFor(() => expect(search).toHaveBeenCalledTimes(2));
    expect(search).toHaveBeenLastCalledWith(c);
    expect(result).toHaveBeenCalledExactlyOnceWith(latest);
});

test.each(["clear", "unmount"])("ignores results after %s", async (action) => {
    const pending = deferred();
    const result = vi.fn();
    const queue = createSearchResultsQueue(
        () => pending.promise,
        result,
        vi.fn(),
    );
    queue.enqueue(suggestion("a"));
    if (action == "clear") queue.enqueue(undefined);
    else queue.dispose();
    pending.resolve([]);
    await Promise.resolve();
    expect(result).not.toHaveBeenCalled();
});

test("a failed request does not block a later search", async () => {
    const error = new Error("search failed");
    const search = vi
        .fn()
        .mockRejectedValueOnce(error)
        .mockResolvedValueOnce([]);
    const result = vi.fn(),
        failure = vi.fn();
    const queue = createSearchResultsQueue(search, result, failure);
    queue.enqueue(suggestion("a"));
    await vi.waitFor(() => expect(failure).toHaveBeenCalledWith(error));
    queue.enqueue(suggestion("b"));
    await vi.waitFor(() => expect(result).toHaveBeenCalledOnce());
});
