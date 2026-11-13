import type { EnteFile } from "ente-media/file";
import { beforeEach, describe, expect, test, vi } from "vitest";
import {
    deleteSelectedLargeFiles,
    type LargeFileItem,
} from "../src/services/large-files";

const { moveToTrash } = vi.hoisted(() => ({ moveToTrash: vi.fn() }));
vi.mock("ente-new/photos/services/collection", () => ({ moveToTrash }));
vi.mock("ente-new/photos/services/photos-fdb", () => ({}));
vi.mock("ente-accounts/services/user", () => ({}));

const item = (id: number, isSelected: boolean): LargeFileItem => ({
    id: `lf_${id}`,
    file: { id } as EnteFile,
    size: 20 * 1024 * 1024,
    isSelected,
});

describe("deleteSelectedLargeFiles", () => {
    beforeEach(() => vi.resetAllMocks());

    test("trashes only selected files and waits for gallery refresh before completing", async () => {
        const selected = item(1, true);
        const onProgress = vi.fn();
        let finishRefresh!: () => void;
        const refresh = vi.fn(
            () =>
                new Promise<void>((resolve) => {
                    finishRefresh = resolve;
                }),
        );
        const deletion = deleteSelectedLargeFiles(
            [selected, item(2, false)],
            onProgress,
            refresh,
        );
        await vi.waitFor(() => expect(refresh).toHaveBeenCalledOnce());
        expect(moveToTrash).toHaveBeenCalledExactlyOnceWith([selected.file]);
        expect(onProgress.mock.calls).toEqual([[50]]);
        finishRefresh();
        await expect(deletion).resolves.toEqual(new Set([selected.id]));
        expect(onProgress.mock.calls).toEqual([[50], [100]]);
    });

    test("does nothing when no files are selected", async () => {
        const onProgress = vi.fn();
        const refresh = vi.fn();
        await expect(
            deleteSelectedLargeFiles([item(1, false)], onProgress, refresh),
        ).resolves.toEqual(new Set());
        expect(moveToTrash).not.toHaveBeenCalled();
        expect(refresh).not.toHaveBeenCalled();
        expect(onProgress).not.toHaveBeenCalled();
    });

    test("propagates trash failures without starting a refresh", async () => {
        const failure = new Error("Trash failed");
        moveToTrash.mockRejectedValue(failure);
        const refresh = vi.fn();
        const onProgress = vi.fn();
        await expect(
            deleteSelectedLargeFiles([item(1, true)], onProgress, refresh),
        ).rejects.toBe(failure);
        expect(refresh).not.toHaveBeenCalled();
        expect(onProgress).not.toHaveBeenCalled();
    });

    test("propagates refresh failures without reporting completion", async () => {
        const failure = new Error("Refresh failed");
        const refresh = vi.fn().mockRejectedValue(failure);
        const onProgress = vi.fn();
        await expect(
            deleteSelectedLargeFiles([item(1, true)], onProgress, refresh),
        ).rejects.toBe(failure);
        expect(onProgress.mock.calls).toEqual([[50]]);
    });
});
