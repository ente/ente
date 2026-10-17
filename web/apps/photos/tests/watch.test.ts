import type { FolderWatch } from "ente-base/types/ipc";
import { afterEach, beforeEach, expect, test, vi } from "vitest";

const { electron, state, uploadManager, watch } = vi.hoisted(() => {
    const watch: FolderWatch = {
        collectionMapping: "root",
        folderPath: "/photos/watched",
        syncedFiles: [],
        ignoredFiles: [],
    };
    const state: {
        files: string[];
        onGetWatches?: () => void;
        onAddFile?: (path: string, w: FolderWatch) => void;
    } = { files: [] };
    const electron = {
        watch: {
            get: () => {
                state.onGetWatches?.();
                return Promise.resolve([watch]);
            },
            onAddFile: (f: (path: string, w: FolderWatch) => void) =>
                (state.onAddFile = f),
            onRemoveFile: () => undefined,
            onRemoveDir: () => undefined,
        },
        fs: { findFiles: () => Promise.resolve([...state.files]) },
    };
    const uploadManager = {
        isUploadRunning: vi.fn(() => false),
        cancelRunningUpload: vi.fn(),
    };
    return { electron, state, uploadManager, watch };
});

vi.mock("ente-base/electron", () => ({ ensureElectron: () => electron }));
vi.mock("ente-base/log", () => ({
    default: { info: vi.fn(), debug: vi.fn(), error: vi.fn() },
}));
vi.mock("ente-new/photos/services/collection", () => ({
    removeFromOwnCollection: vi.fn(),
}));
vi.mock("ente-new/photos/services/file", () => ({
    computeAllCollectionFilesFromSaved: vi.fn(),
}));
vi.mock("../src/services/upload-manager", () => ({ uploadManager }));

beforeEach(() => {
    vi.useFakeTimers();
    state.files = [];
    state.onGetWatches = undefined;
    uploadManager.isUploadRunning.mockReturnValue(false);
});

afterEach(() => vi.useRealTimers());

const initWatcher = async (isUploadInProgress: () => boolean) => {
    vi.resetModules();
    const { default: watcher } = await import("../src/services/watch");
    const upload = vi.fn();
    watcher.init(upload, vi.fn(), isUploadInProgress);
    await vi.advanceTimersByTimeAsync(2000);
    return { watcher, upload };
};

const addFile = (path: string) => {
    state.files.push(path);
    state.onAddFile!(path, watch);
};

test("folder watch waits for an upload already in progress", async () => {
    let isUploadInProgress = true;
    const { watcher, upload } = await initWatcher(() => isUploadInProgress);

    addFile("/photos/watched/a.jpg");
    await vi.advanceTimersByTimeAsync(5000);

    expect(upload).not.toHaveBeenCalled();
    expect(watcher.isUploadRunning()).toBe(false);

    isUploadInProgress = false;
    await vi.advanceTimersByTimeAsync(2000);

    expect(upload).toHaveBeenCalledExactlyOnceWith("watched", [
        "/photos/watched/a.jpg",
    ]);
    expect(watcher.isUploadRunning()).toBe(true);
});

test("folder watch waits for uploads started outside the upload dialog", async () => {
    uploadManager.isUploadRunning.mockReturnValue(true);
    const { upload } = await initWatcher(() => false);

    addFile("/photos/watched/a.jpg");
    await vi.advanceTimersByTimeAsync(5000);

    expect(upload).not.toHaveBeenCalled();

    uploadManager.isUploadRunning.mockReturnValue(false);
    await vi.advanceTimersByTimeAsync(2000);

    expect(upload).toHaveBeenCalledExactlyOnceWith("watched", [
        "/photos/watched/a.jpg",
    ]);
});

test("folder watch rechecks the uploader after reading the watches", async () => {
    let isUploadInProgress = false;
    const { upload } = await initWatcher(() => isUploadInProgress);

    // A user upload starts while the watcher reads the watches.
    state.onGetWatches = () => {
        isUploadInProgress = true;
        state.onGetWatches = undefined;
    };
    addFile("/photos/watched/a.jpg");
    await vi.advanceTimersByTimeAsync(5000);

    expect(upload).not.toHaveBeenCalled();

    isUploadInProgress = false;
    await vi.advanceTimersByTimeAsync(2000);

    expect(upload).toHaveBeenCalledExactlyOnceWith("watched", [
        "/photos/watched/a.jpg",
    ]);
});
