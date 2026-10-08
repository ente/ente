import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import {
    logoutSearch,
    searchDiscoverySuggestions,
    updateSearchCollectionsAndFiles,
} from "ente-new/photos/services/search";
import { searchDiscoveryLabels } from "ente-new/photos/services/search/discovery";
import { SearchWorker } from "ente-new/photos/services/search/worker";
import { afterEach, beforeEach, expect, test, vi } from "vitest";

vi.mock("comlink", () => ({ expose: vi.fn() }));
vi.mock("ente-base/log-web", () => ({
    logUnhandledErrorsAndRejectionsInWorker: vi.fn(),
}));
vi.mock("ente-accounts/services/user", () => ({
    ensureLocalUser: () => ({ id: 1 }),
}));
vi.mock("ente-new/photos/services/account-keys", () => ({
    ensureMasterKeyFromSession: vi.fn(),
}));
vi.mock("ente-new/photos/services/ml", () => ({ isMLSupported: false }));
vi.mock("ente-new/photos/services/user-entity", () => ({
    pullUserEntities: vi.fn().mockResolvedValue(undefined),
    savedLocationTags: () =>
        Promise.resolve([
            {
                name: "Home",
                centerPoint: { latitude: 12, longitude: 77 },
                radius: 1,
            },
            {
                name: "Empty place",
                centerPoint: { latitude: 50, longitude: 50 },
                radius: 1,
            },
        ]),
}));
vi.mock("ente-base/worker/comlink-worker", () => ({
    ComlinkWorker: class {
        remote = Promise.resolve(new SearchWorker());
        terminate = vi.fn();
    },
}));

const collection = (id: number, name: string) => ({ id, name }) as Collection;
const file = (id: number, collectionID: number, located = false) =>
    ({
        id,
        collectionID,
        ownerID: 1,
        metadata: {
            latitude: located ? 12 : 0,
            longitude: located ? 77 : 0,
            creationTime: 1,
        },
    }) as EnteFile;

beforeEach(() => {
    logoutSearch();
    vi.stubGlobal(
        "Worker",
        vi.fn(function () {
            return {};
        }),
    );
    vi.stubGlobal(
        "fetch",
        vi
            .fn()
            .mockResolvedValue({
                ok: true,
                json: () => Promise.resolve({ data: [] }),
            }),
    );
});

afterEach(() => vi.unstubAllGlobals());

test("ranks by file count then name, deduplicates labels, and omits zero matches", () => {
    expect(
        searchDiscoveryLabels([
            { type: "collection", label: "Zero", fileCount: 0 },
            { type: "collection", label: "Zoo", fileCount: 4 },
            { type: "collection", label: "Alpha", fileCount: 4 },
            { type: "collection", label: "alpha", fileCount: 2 },
            { type: "location", label: "ALPHA", fileCount: 9 },
            { type: "location", label: "Home", fileCount: 1 },
        ]),
    ).toEqual(["Alpha", "Zoo", "Home"]);
    expect(searchDiscoveryLabels([])).toEqual([]);
});

test("discovery consumes the same hidden-filtered library as global search", async () => {
    await updateSearchCollectionsAndFiles(
        [
            collection(1, "Hidden album"),
            collection(2, "Only hidden files"),
            collection(3, "Visible"),
            collection(4, "Empty"),
        ],
        [file(1, 1), file(2, 2), file(3, 3)],
        new Set([1]),
        new Set([1, 2]),
    );
    expect(await searchDiscoverySuggestions()).toEqual(["Visible"]);
    await updateSearchCollectionsAndFiles([], [], new Set(), new Set());
    expect(await searchDiscoverySuggestions()).toEqual([]);
});

test("saved places need searchable matching files and album counts use memberships", async () => {
    const worker = new SearchWorker();
    await worker.sync("test-key");
    const files = [file(1, 1, true), file(1, 2, true), file(2, 2)];
    worker.setCollectionsAndFiles({
        currentUserID: 1,
        collections: [collection(1, "One"), collection(2, "Two")],
        files: [files[0]!, files[2]!],
        collectionFiles: files,
    });
    expect(worker.discoverySuggestions()).toEqual(["Two", "One", "Home"]);
});
