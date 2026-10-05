import type { FolderWatch } from "ente-base/types/ipc";
import { afterEach, expect, test, vi } from "vitest";
import watcher from "../src/services/watch";

const { electron, watch } = vi.hoisted(() => {
    const watch: FolderWatch = {
        collectionMapping: "root",
        folderPath: "/photos/watched",
        syncedFiles: [],
        ignoredFiles: [],
    };
    const listeners: { onAddFile?: (path: string, w: FolderWatch) => void } =
        {};
    const electron = {
        listeners,
        watch: {
            get: () => Promise.resolve([watch]),
            onAddFile: (f: (path: string, w: FolderWatch) => void) =>
                (listeners.onAddFile = f),
            onRemoveFile: () => undefined,
            onRemoveDir: () => undefined,
        },
        fs: { findFiles: () => Promise.resolve([]) },
    };
    return { electron, watch };
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
vi.mock("../src/services/upload-manager", () => ({
    uploadManager: { cancelRunningUpload: vi.fn() },
}));

afterEach(() => vi.useRealTimers());

test("folder watch waits for an upload already in progress", async () => {
    vi.useFakeTimers();
    let isUploadInProgress = true;
    const upload = vi.fn();
    watcher.init(upload, vi.fn(), () => isUploadInProgress);
    await vi.advanceTimersByTimeAsync(2000);

    electron.listeners.onAddFile!("/photos/watched/a.jpg", watch);
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
