import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import { afterEach, describe, expect, test, vi } from "vitest";

const mocks = vi.hoisted(() => ({
    kv: new Map<string, unknown>(),
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
    setKV: (key: string, value: unknown) => {
        mocks.kv.set(key, value);
        return Promise.resolve();
    },
}));
vi.mock("ente-accounts/services/user", async (importOriginal) => ({
    ...(await importOriginal<typeof import("ente-accounts/services/user")>()),
    ensureLocalUser: () => ({ id: 1 }),
}));
vi.mock("ente-new/photos/services/photos-fdb", async (importOriginal) => ({
    ...(await importOriginal<
        typeof import("ente-new/photos/services/photos-fdb")
    >()),
    savedCollectionFiles: async () => {
        mocks.collectionFilesReadCount++;
        await mocks.collectionFilesReadGate;
        return mocks.collectionFiles;
    },
}));
vi.mock("ente-new/photos/services/trash", async (importOriginal) => ({
    ...(await importOriginal<
        typeof import("ente-new/photos/services/trash")
    >()),
    savedTrashItemFileIDs: () => Promise.resolve(new Set<number>()),
}));
vi.mock("ente-gallery/services/file-data", async (importOriginal) => ({
    ...(await importOriginal<
        typeof import("ente-gallery/services/file-data")
    >()),
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
vi.mock("ente-gallery/services/upload", async (importOriginal) => ({
    ...(await importOriginal<typeof import("ente-gallery/services/upload")>()),
    fileSystemUploadItemIfUnchanged: () => Promise.resolve({}),
}));
vi.mock("ente-gallery/utils/native-stream", async (importOriginal) => ({
    ...(await importOriginal<
        typeof import("ente-gallery/utils/native-stream")
    >()),
    initiateGenerateHLS: () => Promise.resolve(undefined),
}));
vi.mock("ente-new/photos/services/file", async (importOriginal) => ({
    ...(await importOriginal<typeof import("ente-new/photos/services/file")>()),
    updateFilePublicMagicMetadata: () => Promise.resolve(),
}));
vi.mock("ente-utils/promise", async (importOriginal) => ({
    ...(await importOriginal<typeof import("ente-utils/promise")>()),
    wait: () => new Promise<void>(() => undefined),
}));

const {
    hlsGenerationStatusSnapshot,
    initVideoProcessing,
    processedVideoFraction,
    processVideoNewUpload,
    resetVideoState,
    streamCandidateFiles,
    toggleHLSGeneration,
    videoPrunePermanentlyDeletedFileIDsIfNeeded,
    videoProcessingSyncIfNeeded,
} = await import("ente-gallery/services/video");

const MiB = 1024 * 1024;

const expectProcessedFraction = (processedFraction: number) =>
    vi.waitFor(() =>
        expect(hlsGenerationStatusSnapshot()).toMatchObject({
            enabled: true,
            processedFraction,
        }),
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

    test("calculates the processed fraction for all Desktop candidates", () => {
        expect(processedVideoFraction(new Set(), [])).toBe(1);
        expect(processedVideoFraction(new Set(), [file(1), file(2)])).toBe(0);
        expect(
            processedVideoFraction(new Set([1, 3]), [
                file(1),
                file(2),
                file(3),
                file(4),
            ]),
        ).toBe(0.5);

        const candidates = [
            file(1),
            file(2, { duration: 61 }),
            file(3, { fileSize: 500 * MiB + 1 }),
        ];
        expect(processedVideoFraction(new Set([1]), candidates)).toBe(1 / 3);
    });

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

        await vi.waitFor(() => expect(mocks.previewStatusPullCount).toBe(1));
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
        await vi.waitFor(() => expect(mocks.previewStatusPullCount).toBe(1));
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
        await initVideoProcessing();
        await expectProcessedFraction(2 / 3);

        mocks.collectionFiles = [file(2), file(3)];
        await videoPrunePermanentlyDeletedFileIDsIfNeeded(new Set([1]));
        await initVideoProcessing();
        await expectProcessedFraction(1 / 2);
    });

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

        await vi.waitFor(() => {
            expect(mocks.collectionFilesReadCount).toBe(2);
            expect(hlsGenerationStatusSnapshot()).toMatchObject({
                enabled: true,
                processedFraction: 0,
            });
        });
    });
});
