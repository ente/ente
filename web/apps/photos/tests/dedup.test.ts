import type { EnteFile } from "ente-media/file";
import { beforeEach, describe, expect, test, vi } from "vitest";
import {
    removeSelectedDuplicateGroups,
    type DuplicateGroup,
} from "../src/services/dedup";

const { addToCollection, moveToTrash, savedNormalCollections } = vi.hoisted(
    () => ({
        addToCollection: vi.fn(),
        moveToTrash: vi.fn(),
        savedNormalCollections: vi.fn(),
    }),
);
vi.mock("ente-new/photos/services/collection", () => ({
    addToCollection,
    moveToTrash,
    savedNormalCollections,
}));
vi.mock("ente-new/photos/services/photos-fdb", () => ({}));
vi.mock("ente-accounts/services/user", () => ({}));

const duplicateGroup = (): DuplicateGroup => ({
    id: "group-1",
    items: [
        {
            file: { id: 1 } as EnteFile,
            collectionIDs: new Set([11, 12]),
            collectionName: "A",
        },
        {
            file: {
                id: 2,
                pubMagicMetadata: { data: { caption: "Keep this copy" } },
            } as EnteFile,
            collectionIDs: new Set([12]),
            collectionName: "B",
        },
        {
            file: { id: 3 } as EnteFile,
            collectionIDs: new Set([13]),
            collectionName: "C",
        },
    ],
    itemSize: 100,
    prunableCount: 2,
    prunableSize: 200,
    isSelected: true,
});

const collections = [{ id: 11 }, { id: 12 }, { id: 13 }];

describe("removeSelectedDuplicateGroups", () => {
    beforeEach(() => {
        vi.resetAllMocks();
        savedNormalCollections.mockResolvedValue(collections);
    });

    test("preserves album membership before trashing selected duplicates and awaits gallery refresh", async () => {
        const group = duplicateGroup();
        const untouched = {
            ...duplicateGroup(),
            id: "unselected",
            isSelected: false,
        };
        const progress = vi.fn();
        let finishRefresh!: () => void;
        const refresh = vi.fn(
            () =>
                new Promise<void>((resolve) => {
                    finishRefresh = resolve;
                }),
        );
        const removal = removeSelectedDuplicateGroups(
            [group, untouched],
            progress,
            refresh,
        );
        await vi.waitFor(() => expect(refresh).toHaveBeenCalledOnce());
        expect(addToCollection.mock.calls).toEqual([
            [collections[0], [group.items[1]!.file]],
            [collections[2], [group.items[1]!.file]],
        ]);
        expect(moveToTrash).toHaveBeenCalledExactlyOnceWith([
            group.items[0]!.file,
            group.items[2]!.file,
        ]);
        expect(addToCollection.mock.invocationCallOrder[1]).toBeLessThan(
            moveToTrash.mock.invocationCallOrder[0]!,
        );
        expect(moveToTrash.mock.invocationCallOrder[0]).toBeLessThan(
            refresh.mock.invocationCallOrder[0]!,
        );
        expect(progress.mock.calls).toEqual([[25], [50], [75]]);
        finishRefresh();
        await expect(removal).resolves.toEqual(new Set([group.id]));
        expect(progress).toHaveBeenLastCalledWith(100);
    });

    test("does not trash files when preserving album membership fails", async () => {
        const failure = new Error("Add failed");
        addToCollection.mockRejectedValue(failure);
        const refresh = vi.fn();
        await expect(
            removeSelectedDuplicateGroups([duplicateGroup()], vi.fn(), refresh),
        ).rejects.toBe(failure);
        expect(moveToTrash).not.toHaveBeenCalled();
        expect(refresh).not.toHaveBeenCalled();
    });

    test("does not refresh when trashing fails", async () => {
        const failure = new Error("Trash failed");
        moveToTrash.mockRejectedValue(failure);
        const refresh = vi.fn();
        await expect(
            removeSelectedDuplicateGroups([duplicateGroup()], vi.fn(), refresh),
        ).rejects.toBe(failure);
        expect(refresh).not.toHaveBeenCalled();
    });

    test("does not report completion when gallery refresh fails", async () => {
        const failure = new Error("Refresh failed");
        const refresh = vi.fn().mockRejectedValue(failure);
        const progress = vi.fn();
        await expect(
            removeSelectedDuplicateGroups(
                [duplicateGroup()],
                progress,
                refresh,
            ),
        ).rejects.toBe(failure);
        expect(progress).not.toHaveBeenCalledWith(100);
    });

    test("only refreshes when no groups are selected", async () => {
        const refresh = vi.fn();
        await expect(
            removeSelectedDuplicateGroups(
                [{ ...duplicateGroup(), isSelected: false }],
                vi.fn(),
                refresh,
            ),
        ).resolves.toEqual(new Set());
        expect(addToCollection).not.toHaveBeenCalled();
        expect(moveToTrash).not.toHaveBeenCalled();
        expect(refresh).toHaveBeenCalledOnce();
    });
});
