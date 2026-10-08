import type {
    SearchOption,
    SearchSuggestion,
} from "ente-new/photos/services/search/types";
import { afterEach, describe, expect, test, vi } from "vitest";
import {
    schedulePhotoSearch,
    searchCategories,
    searchCategoryForType,
} from "../src/services/search/search-dialog";

const option = {
    suggestion: { type: "noLocation", label: "No location" },
    fileCount: 4,
    previewFiles: [],
} satisfies SearchOption;

afterEach(() => vi.useRealTimers());

test("maps every search type to the ordered tabs", () => {
    const expected: Record<SearchSuggestion["type"], string> = {
        collection: "albums",
        person: "people",
        location: "places",
        city: "places",
        fileType: "photos",
        fileName: "photos",
        fileCaption: "photos",
        cameraMake: "photos",
        cameraModel: "photos",
        date: "photos",
        noLocation: "photos",
        clip: "photos",
        sidebarAction: "settings",
    };
    for (const type of Object.keys(expected) as SearchSuggestion["type"][])
        expect(searchCategoryForType(type)).toBe(expected[type]);
    expect(searchCategories).toEqual([
        "all",
        "albums",
        "people",
        "places",
        "photos",
        "settings",
    ]);
});

describe("debounced search lifecycle", () => {
    test("waits 250 ms and publishes the original rows and previews", async () => {
        vi.useFakeTimers();
        const search = vi.fn().mockResolvedValue([option]);
        const publish = vi.fn();
        schedulePhotoSearch("photo", search, publish);
        await vi.advanceTimersByTimeAsync(249);
        expect(search).not.toHaveBeenCalled();
        await vi.advanceTimersByTimeAsync(1);
        expect(search).toHaveBeenCalledExactlyOnceWith("photo");
        expect(publish).toHaveBeenCalledExactlyOnceWith({
            options: [option],
            failed: false,
        });
    });

    test("does not run a superseded debounce", async () => {
        vi.useFakeTimers();
        const search = vi.fn().mockResolvedValue([]);
        const publish = vi.fn();
        const cancel = schedulePhotoSearch("old", search, publish);
        cancel();
        schedulePhotoSearch("new", search, publish);
        await vi.advanceTimersByTimeAsync(250);
        expect(search).toHaveBeenCalledExactlyOnceWith("new");
    });

    test("ignores obsolete success and failure after cancellation or reopening", async () => {
        vi.useFakeTimers();
        for (const fails of [false, true]) {
            let resolve!: (options: SearchOption[]) => void;
            let reject!: (error: unknown) => void;
            const pending = new Promise<SearchOption[]>((res, rej) => {
                resolve = res;
                reject = rej;
            });
            const publish = vi.fn();
            const cancel = schedulePhotoSearch("old", () => pending, publish);
            await vi.advanceTimersByTimeAsync(250);
            cancel();
            schedulePhotoSearch("new", () => Promise.resolve([]), publish);
            await vi.advanceTimersByTimeAsync(250);
            if (fails) reject(new Error("obsolete"));
            else resolve([option]);
            await Promise.resolve();
            expect(publish).toHaveBeenCalledExactlyOnceWith({
                options: [],
                failed: false,
            });
        }
    });

    test("reports rejection even without an Error and supports a fresh retry", async () => {
        vi.useFakeTimers();
        const search = vi
            .fn()
            .mockRejectedValueOnce(undefined)
            .mockResolvedValueOnce([option]);
        const publish = vi.fn();
        schedulePhotoSearch("same", search, publish);
        await vi.advanceTimersByTimeAsync(250);
        expect(publish).toHaveBeenLastCalledWith({
            options: [],
            failed: true,
            error: undefined,
        });
        schedulePhotoSearch("same", search, publish);
        await vi.advanceTimersByTimeAsync(250);
        expect(publish).toHaveBeenLastCalledWith({
            options: [option],
            failed: false,
        });
    });
});
