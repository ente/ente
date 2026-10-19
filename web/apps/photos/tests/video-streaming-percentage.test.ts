import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import { setImmediate } from "node:timers/promises";
import { afterEach, describe, expect, test, vi } from "vitest";

const mocks = vi.hoisted(() => ({
    kv: new Map<string, unknown>(),
    generateHLSSaveGate: undefined as Promise<void> | undefined,
    collectionFiles: [] as EnteFile[],
    collectionFilesReadCount: 0,
    collectionFilesReadGate: undefined as Promise<void> | undefined,
    pulledFileIDs: new Set<number>(),
    previewStatusPullCount: 0,
    previewStatusPullGate: undefined as Promise<void> | undefined,
    previewStatusPullError: undefined as Error | undefined,
    assertionFailedCount: 0,
    fetchFileDataResult: new Promise<undefined>(() => undefined),
}));

vi.mock("ente-base/app", async (importOriginal) => ({
    ...(await importOriginal<typeof import("ente-base/app")>()),
    isDesktop: true,
}));
vi.mock("ente-base/assert", async (importOriginal) => ({
    ...(await importOriginal<typeof import("ente-base/assert")>()),
    assertionFailed: () => mocks.assertionFailedCount++,
}));
vi.mock("ente-base/electron", async (importOriginal) => ({
    ...(await importOriginal<typeof import("ente-base/electron")>()),
    ensureElectron: () => ({ fs: { statMtime: vi.fn() } }),
}));
vi.mock("ente-base/log", async (importOriginal) => {
    const original = await importOriginal<typeof import("ente-base/log")>();
    return {
        ...original,
        default: {
            ...original.default,
            debug: vi.fn(),
            error: vi.fn(),
            info: vi.fn(),
        },
    };
});
vi.mock("ente-base/origins", async (importOriginal) => ({
    ...(await importOriginal<typeof import("ente-base/origins")>()),
    apiURL: () => Promise.resolve("https://example.com"),
}));
vi.mock("ente-base/token", async (importOriginal) => ({
    ...(await importOriginal<typeof import("ente-base/token")>()),
    ensureAuthToken: () => Promise.resolve("token"),
}));
vi.mock("ente-base/kv", async (importOriginal) => ({
    ...(await importOriginal<typeof import("ente-base/kv")>()),
    getKV: (key: string) => Promise.resolve(mocks.kv.get(key)),
    getKVB: (key: string) => Promise.resolve(mocks.kv.get(key)),
    getKVN: (key: string) => Promise.resolve(mocks.kv.get(key)),
    setKV: async (key: string, value: unknown) => {
        if (key == "generateHLS") await mocks.generateHLSSaveGate;
        mocks.kv.set(key, value);
    },
}));
vi.mock("ente-accounts/services/user", () => ({
    ensureLocalUser: () => ({ id: 1 }),
}));
vi.mock("ente-new/photos/services/photos-fdb", () => ({
    savedCollectionFiles: async () => {
        mocks.collectionFilesReadCount++;
        await mocks.collectionFilesReadGate;
        return mocks.collectionFiles;
    },
}));
vi.mock("ente-new/photos/services/trash", () => ({
    savedTrashItemFileIDs: () => Promise.resolve(new Set<number>()),
}));
vi.mock("ente-gallery/services/file-data", () => ({
    syncUpdatedFileDataFileIDs: async (
        _type: string,
        _lastUpdatedAt: number,
        onPage: (page: {
            fileIDs: Set<number>;
            lastUpdatedAt: number;
        }) => Promise<void>,
    ) => {
        mocks.previewStatusPullCount++;
        await mocks.previewStatusPullGate;
        if (mocks.previewStatusPullError) throw mocks.previewStatusPullError;
        return onPage({ fileIDs: mocks.pulledFileIDs, lastUpdatedAt: 1 });
    },
    fetchFileData: () => mocks.fetchFileDataResult,
}));
vi.mock("ente-gallery/services/upload", () => ({
    fileSystemUploadItemIfUnchanged: () => Promise.resolve({}),
}));
vi.mock("ente-gallery/utils/native-stream", () => ({
    initiateGenerateHLS: () => Promise.resolve(undefined),
}));
vi.mock("ente-new/photos/services/file", () => ({
    updateFilePublicMagicMetadata: () => Promise.resolve(),
}));
vi.mock("ente-utils/promise", async (importOriginal) => ({
    ...(await importOriginal<typeof import("ente-utils/promise")>()),
    wait: () => new Promise<void>(() => undefined),
}));

const {
    hlsGenerationStatusSnapshot,
    initVideoProcessing,
    processVideoNewUpload,
    resetVideoState,
    streamCandidateFiles,
    toggleHLSGeneration,
    videoPrunePermanentlyDeletedFileIDsIfNeeded,
    videoProcessingSyncIfNeeded,
} = await import("ente-gallery/services/video");

const MiB = 1024 * 1024;

const expectProcessedFraction = (processedFraction: number) =>
    vi.waitFor(
        () =>
            expect(hlsGenerationStatusSnapshot()).toMatchObject({
                enabled: true,
                processedFraction,
            }),
        { interval: 5 },
    );

const file = (
    id: number,
    overrides: {
        ownerID?: number;
        fileType?: FileType;
        sv?: number;
        fileSize?: number;
        duration?: number;
    } = {},
) =>
    ({
        id,
        ownerID: overrides.ownerID ?? 1,
        metadata: {
            fileType: overrides.fileType ?? FileType.video,
            duration: overrides.duration ?? 30,
        },
        info: { fileSize: overrides.fileSize ?? 10 * MiB },
        ...(overrides.sv == undefined
            ? {}
            : { pubMagicMetadata: { data: { sv: overrides.sv } } }),
    }) as EnteFile;

describe("video streaming percentage", () => {
    afterEach(() => {
        resetVideoState();
        mocks.kv.clear();
        mocks.generateHLSSaveGate = undefined;
        mocks.collectionFiles = [];
        mocks.collectionFilesReadCount = 0;
        mocks.collectionFilesReadGate = undefined;
        mocks.pulledFileIDs = new Set();
        mocks.previewStatusPullCount = 0;
        mocks.previewStatusPullGate = undefined;
        mocks.previewStatusPullError = undefined;
        mocks.assertionFailedCount = 0;
        mocks.fetchFileDataResult = new Promise<undefined>(() => undefined);
    });

    test.each([
        { ids: [], files: [], fraction: 1 },
        { ids: [], files: [file(1), file(2)], fraction: 0 },
        {
            ids: [1, 3],
            files: [file(1), file(2), file(3), file(4)],
            fraction: 0.5,
        },
        {
            ids: [1],
            files: [
                file(1),
                file(2, { duration: 61 }),
                file(3, { fileSize: 500 * MiB + 1 }),
            ],
            fraction: 1 / 3,
        },
        { ids: [1], files: [file(1), file(1), file(2)], fraction: 0.5 },
        { ids: [3], files: [], fraction: 1 },
        { ids: [1, 3], files: [file(1), file(2)], fraction: 0.5 },
    ])(
        "publishes the expected fraction: $fraction",
        async ({ ids, files, fraction }) => {
            mocks.kv.set("generateHLS", true);
            mocks.kv.set("videoPreviewProcessedFileIDs", ids);
            mocks.collectionFiles = files;
            await initVideoProcessing();
            await expectProcessedFraction(fraction);
        },
    );

    test("reuses Desktop's backfill population", () => {
        const candidates = streamCandidateFiles(
            [
                file(1),
                file(1),
                file(2, { ownerID: 2 }),
                file(3),
                file(4, { fileType: FileType.image }),
                file(5, { sv: 1 }),
                file(6, { duration: 600 }),
                file(7, { fileSize: 600 * MiB }),
            ],
            new Set([3]),
            1,
        );

        expect(candidates.map(({ id }) => id)).toEqual([1, 6, 7]);
    });

    test("syncs previews before calculating when enabled", async () => {
        mocks.collectionFiles = [file(1)];
        mocks.pulledFileIDs = new Set([1]);
        const previewStatusPull = Promise.withResolvers<undefined>();
        mocks.previewStatusPullGate = previewStatusPull.promise;

        await videoProcessingSyncIfNeeded();
        const toggle = toggleHLSGeneration();

        await vi.waitFor(() => expect(mocks.previewStatusPullCount).toBe(1), {
            interval: 5,
        });
        expect(hlsGenerationStatusSnapshot()).toEqual({ enabled: true });
        expect(mocks.collectionFilesReadCount).toBe(0);

        previewStatusPull.resolve(undefined);
        await toggle;

        await expectProcessedFraction(1);
    });

    test("does not start a stale enable operation after disabling", async () => {
        const previewStatusPull = Promise.withResolvers<undefined>();
        mocks.previewStatusPullGate = previewStatusPull.promise;

        const enable = toggleHLSGeneration();
        await vi.waitFor(() => expect(mocks.previewStatusPullCount).toBe(1), {
            interval: 5,
        });
        await toggleHLSGeneration();
        previewStatusPull.resolve(undefined);
        await enable;

        expect(hlsGenerationStatusSnapshot()).toEqual({ enabled: false });
        expect(mocks.assertionFailedCount).toBe(0);
    });

    test("calculates locally when the preview sync fails", async () => {
        mocks.collectionFiles = [file(1)];
        mocks.previewStatusPullError = new Error("offline");

        await toggleHLSGeneration();

        await expectProcessedFraction(0);
    });

    test("refreshes newly synced files when the preview sync fails", async () => {
        await toggleHLSGeneration();
        await expectProcessedFraction(1);
        mocks.collectionFiles = [file(1)];
        mocks.previewStatusPullError = new Error("offline");

        await videoProcessingSyncIfNeeded();

        await expectProcessedFraction(0);
    });

    test("does not start a stale sync operation after disabling", async () => {
        mocks.kv.set("generateHLS", true);
        await initVideoProcessing();
        await expectProcessedFraction(1);
        const previewStatusPull = Promise.withResolvers<undefined>();
        mocks.previewStatusPullGate = previewStatusPull.promise;
        const sync = videoProcessingSyncIfNeeded();
        await toggleHLSGeneration();

        previewStatusPull.resolve(undefined);
        await sync;

        expect(hlsGenerationStatusSnapshot()).toEqual({ enabled: false });
        expect(mocks.assertionFailedCount).toBe(0);
    });

    test("includes unsynced uploads in the fraction", async () => {
        await toggleHLSGeneration();

        processVideoNewUpload(file(1), {} as never);

        await expectProcessedFraction(0);
    });

    test("updates completed videos without rescanning the library", async () => {
        await toggleHLSGeneration();
        await expectProcessedFraction(1);
        await new Promise<void>(queueMicrotask);
        mocks.fetchFileDataResult = Promise.resolve({} as never);

        processVideoNewUpload(file(1), {} as never);

        await expectProcessedFraction(1);
        expect(mocks.collectionFilesReadCount).toBe(1);
    });

    test("retires unsynced uploads after they enter the saved index", async () => {
        await toggleHLSGeneration();
        processVideoNewUpload(file(1), {} as never);
        await expectProcessedFraction(0);

        mocks.collectionFiles = [file(1), file(2), file(3)];
        mocks.kv.set("videoPreviewProcessedFileIDs", [1, 2]);
        await videoProcessingSyncIfNeeded();
        await expectProcessedFraction(2 / 3);

        mocks.collectionFiles = [file(2), file(3)];
        await videoPrunePermanentlyDeletedFileIDsIfNeeded(new Set([1]));
        await videoProcessingSyncIfNeeded();
        await expectProcessedFraction(1 / 2);
    });

    test.each([false, true])(
        "prunes uploads deleted before entering the saved index (processed: %s)",
        async (processed) => {
            await toggleHLSGeneration();
            processVideoNewUpload(file(1), {} as never);
            await expectProcessedFraction(0);
            if (processed) {
                mocks.kv.set("videoPreviewProcessedFileIDs", [1]);
            }

            await videoPrunePermanentlyDeletedFileIDsIfNeeded(new Set([1]));

            await expectProcessedFraction(1);
            expect(mocks.kv.get("videoPreviewProcessedFileIDs") ?? []).toEqual(
                [],
            );
            await videoProcessingSyncIfNeeded();
            await setImmediate();
            await expectProcessedFraction(1);
        },
    );

    test("excludes files locally marked as not requiring a stream", async () => {
        mocks.collectionFiles = [file(1), file(2), file(3)];
        mocks.kv.set("videoPreviewProcessedFileIDs", [2]);
        mocks.fetchFileDataResult = Promise.resolve(undefined);
        await toggleHLSGeneration();
        await expectProcessedFraction(1 / 3);

        processVideoNewUpload(file(1), {} as never);

        await expectProcessedFraction(1 / 2);
    });

    test("coalesces overlapping fraction refresh requests", async () => {
        mocks.kv.set("generateHLS", true);
        mocks.collectionFiles = [file(1)];
        const collectionFilesRead = Promise.withResolvers<undefined>();
        mocks.collectionFilesReadGate = collectionFilesRead.promise;

        await initVideoProcessing();
        await initVideoProcessing();
        await initVideoProcessing();

        expect(mocks.collectionFilesReadCount).toBe(1);

        collectionFilesRead.resolve(undefined);

        await vi.waitFor(
            () => {
                expect(mocks.collectionFilesReadCount).toBe(2);
                expect(hlsGenerationStatusSnapshot()).toMatchObject({
                    enabled: true,
                    processedFraction: 0,
                });
            },
            { interval: 5 },
        );
    });
    test("discards a refresh after generation is disabled", async () => {
        mocks.kv.set("generateHLS", true);
        mocks.collectionFiles = [file(1)];
        const gate = Promise.withResolvers<undefined>();
        mocks.collectionFilesReadGate = gate.promise;
        await initVideoProcessing();
        await toggleHLSGeneration();
        gate.resolve(undefined);
        await setImmediate();
        expect(hlsGenerationStatusSnapshot()).toEqual({ enabled: false });
    });

    test("keeps the snapshot disabled when processing finishes after disabling", async () => {
        const processing = Promise.withResolvers<undefined>();
        mocks.fetchFileDataResult = processing.promise;
        await toggleHLSGeneration();
        processVideoNewUpload(file(1), {} as never);
        await expectProcessedFraction(0);

        const collectionRead = Promise.withResolvers<undefined>();
        mocks.collectionFilesReadGate = collectionRead.promise;
        await initVideoProcessing();
        const save = Promise.withResolvers<undefined>();
        mocks.generateHLSSaveGate = save.promise;
        const disable = toggleHLSGeneration();

        collectionRead.resolve(undefined);
        await expectProcessedFraction(0);
        save.resolve(undefined);
        await disable;
        expect(hlsGenerationStatusSnapshot()).toEqual({ enabled: false });

        processing.resolve({} as never);
        await vi.waitFor(
            () =>
                expect(mocks.kv.get("videoPreviewProcessedFileIDs")).toEqual([
                    1,
                ]),
            { interval: 5 },
        );
        expect(hlsGenerationStatusSnapshot()).toEqual({ enabled: false });
    });

    test("does not publish an old account refresh after reset", async () => {
        mocks.kv.set("generateHLS", true);
        mocks.collectionFiles = [file(1)];
        const gate = Promise.withResolvers<undefined>();
        mocks.collectionFilesReadGate = gate.promise;
        await initVideoProcessing();
        resetVideoState();
        gate.resolve(undefined);
        await setImmediate();
        expect(hlsGenerationStatusSnapshot()).toBeUndefined();
    });

    test("includes completion recorded during an overlapping refresh", async () => {
        mocks.kv.set("generateHLS", true);
        mocks.collectionFiles = [file(1), file(2)];
        mocks.kv.set("videoPreviewProcessedFileIDs", [1]);
        const gate = Promise.withResolvers<undefined>();
        mocks.collectionFilesReadGate = gate.promise;
        await initVideoProcessing();
        mocks.kv.set("videoPreviewProcessedFileIDs", [1, 2]);
        await initVideoProcessing();
        gate.resolve(undefined);
        await expectProcessedFraction(1);
        expect(mocks.collectionFilesReadCount).toBe(2);
    });

    test("can refresh again after a storage failure", async () => {
        mocks.kv.set("generateHLS", true);
        mocks.collectionFiles = [file(1)];
        const gate = Promise.withResolvers<undefined>();
        mocks.collectionFilesReadGate = gate.promise;
        await initVideoProcessing();
        gate.reject(new Error("storage read failed"));
        await setImmediate();
        mocks.collectionFilesReadGate = undefined;
        await initVideoProcessing();
        await expectProcessedFraction(0);
    });
});
