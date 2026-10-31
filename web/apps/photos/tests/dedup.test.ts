import type { EnteFile } from "ente-media/file";
import { beforeEach, describe, expect, test, vi } from "vitest";
import {
    deduceDuplicates,
    removeSelectedDuplicateGroups,
    type DuplicateGroup,
} from "../src/services/dedup";
const {
    executeDuplicateRemoval,
    savedNormalCollections,
    savedCollectionFiles,
    forgetPendingFavoriteFileIDs,
    session,
} = vi.hoisted(() => ({
    executeDuplicateRemoval:
        vi.fn<typeof import("ente-photos-wasm").executeDuplicateRemoval>(),
    savedNormalCollections: vi.fn(),
    savedCollectionFiles: vi.fn(),
    forgetPendingFavoriteFileIDs: vi.fn(),
    session: {},
}));
vi.mock("ente-photos-wasm", async (importOriginal) => ({
    ...(await importOriginal<typeof import("ente-photos-wasm")>()),
    executeDuplicateRemoval,
}));
vi.mock("../src/services/authenticated-session", () => ({
    ensureAuthenticatedSession: () => Promise.resolve(session),
}));
vi.mock("ente-new/photos/services/collection", () => ({
    savedNormalCollections,
    forgetPendingFavoriteFileIDs,
    createCollectionNameByID: (collections: { id: number; name: string }[]) =>
        new Map(collections.map(({ id, name }) => [id, name])),
}));
vi.mock("ente-new/photos/services/photos-fdb", () => ({
    savedCollectionFiles,
}));
vi.mock("ente-accounts/services/user", () => ({
    ensureLocalUser: () => ({ id: 1 }),
}));
const file = (
    id: number,
    collectionID: number,
    hash: string | undefined,
    size: number | undefined = 100,
) =>
    ({
        id,
        collectionID,
        ownerID: 1,
        metadata: { fileType: 0, hash },
        info: { fileSize: size },
    }) as EnteFile;

describe("deduceDuplicates through Rust WASM", () => {
    beforeEach(() => {
        vi.resetAllMocks();
        executeDuplicateRemoval.mockResolvedValue({ trashIds: [1] });
        savedNormalCollections.mockResolvedValue([
            { id: 11, owner: { id: 1 }, name: "B" },
            { id: 12, owner: { id: 1 }, name: "A" },
            { id: 13, owner: { id: 2 }, name: "Shared" },
        ]);
    });

    test("groups owned files once across albums, excluding shared files and hidden albums", async () => {
        const first = file(1, 11, "hash");
        const second = file(2, 12, "hash");
        savedCollectionFiles.mockResolvedValue([
            first,
            { ...first, collectionID: 12 },
            second,
            { ...file(3, 11, "hash"), ownerID: 2 },
            file(4, 13, "hash"),
            file(5, 99, "hash"),
            file(6, 11, undefined),
            file(7, 11, "unique"),
        ]);
        const groups = await deduceDuplicates();
        expect(groups).toEqual([
            {
                id: expect.any(String) as string,
                items: [
                    {
                        file: second,
                        collectionIDs: new Set([12]),
                        collectionName: "A",
                    },
                    {
                        file: first,
                        collectionIDs: new Set([11, 12]),
                        collectionName: "B",
                    },
                ],
                itemSize: 100,
                prunableCount: 1,
                prunableSize: 100,
                isSelected: true,
            },
        ]);
        await removeSelectedDuplicateGroups(groups, vi.fn(), vi.fn());
        expect(executeDuplicateRemoval.mock.calls[0]![1].groups).toEqual([
            [
                expect.objectContaining({ fileId: 2, collectionIds: [12] }),
                expect.objectContaining({ fileId: 1, collectionIds: [11, 12] }),
            ],
        ]);
    });

    test("matches legacy Live Photo hashes despite different ZIP sizes and skips groups without sizes", async () => {
        const legacy = file(1, 11, undefined, 0);
        legacy.metadata = {
            ...legacy.metadata,
            fileType: 2,
            imageHash: "image",
            videoHash: "video",
        };
        savedCollectionFiles.mockResolvedValue([
            legacy,
            file(2, 12, "image:video", 150),
            file(3, 11, "image:video", 200),
            file(4, 11, "unknown-size", 0),
            { ...file(5, 11, "unknown-size"), info: undefined },
        ]);
        const groups = await deduceDuplicates();
        expect(groups).toHaveLength(1);
        expect(groups[0]).toMatchObject({
            itemSize: 150,
            prunableCount: 2,
            prunableSize: 300,
        });
        expect(groups[0]!.items.map(({ file }) => file.id)).toEqual([2, 1, 3]);
    });

    test("ignores a single file linked to multiple albums and empty libraries", async () => {
        savedCollectionFiles.mockResolvedValue([
            file(1, 11, "hash"),
            file(1, 12, "hash"),
            file(1, 12, "hash"),
        ]);
        expect(await deduceDuplicates()).toEqual([]);
        savedCollectionFiles.mockResolvedValue([]);
        expect(await deduceDuplicates()).toEqual([]);
    });
});

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

const collections = [
    { id: 11, key: "album-11" },
    { id: 12, key: "album-12" },
    { id: 13, key: "album-13" },
];

describe("removeSelectedDuplicateGroups", () => {
    beforeEach(() => {
        vi.resetAllMocks();
        savedNormalCollections.mockResolvedValue(collections);
        executeDuplicateRemoval.mockResolvedValue({ trashIds: [1, 3] });
    });
    test.each([123, 0])(
        "normalizes numeric caption %s before Rust planning",
        async (caption) => {
            const group = duplicateGroup();
            Object.assign(group.items[1]!.file.pubMagicMetadata!.data, {
                caption,
            });
            const refresh = vi.fn();
            await expect(
                removeSelectedDuplicateGroups([group], vi.fn(), refresh),
            ).resolves.toEqual(new Set([group.id]));
            expect(
                executeDuplicateRemoval.mock.calls[0]![1].groups[0]![1],
            ).toMatchObject({ fileId: 2, caption: String(caption) });
            expect(refresh).toHaveBeenCalledOnce();
        },
    );
    test("passes only selected groups and their files, saved album keys, and the shared session to Rust", async () => {
        const group = duplicateGroup();
        for (const item of group.items)
            Object.assign(item.file, {
                collectionID: [...item.collectionIDs][0],
                key: `file-${item.file.id}`,
            });
        const refresh = vi.fn();
        await removeSelectedDuplicateGroups(
            [
                group,
                { ...duplicateGroup(), id: "untouched", isSelected: false },
            ],
            vi.fn(),
            refresh,
        );
        expect(executeDuplicateRemoval).toHaveBeenCalledExactlyOnceWith(
            session,
            {
                groups: [
                    [
                        {
                            fileId: 1,
                            collectionIds: [11, 12],
                            caption: undefined,
                            editedName: undefined,
                            editedTime: undefined,
                        },
                        {
                            fileId: 2,
                            collectionIds: [12],
                            caption: "Keep this copy",
                            editedName: undefined,
                            editedTime: undefined,
                        },
                        {
                            fileId: 3,
                            collectionIds: [13],
                            caption: undefined,
                            editedName: undefined,
                            editedTime: undefined,
                        },
                    ],
                ],
                collections,
                files: [
                    { id: 1, collectionId: 11, key: "file-1" },
                    { id: 2, collectionId: 12, key: "file-2" },
                    { id: 3, collectionId: 13, key: "file-3" },
                ],
            },
            expect.any(Function),
        );
        expect(forgetPendingFavoriteFileIDs).toHaveBeenCalledExactlyOnceWith([
            1, 3,
        ]);
        expect(refresh).toHaveBeenCalledOnce();
    });
    test("reports Rust execution progress and awaits refresh before completion", async () => {
        const progress = vi.fn();
        executeDuplicateRemoval.mockImplementation(
            (_session, _input, onProgress) => {
                onProgress(1, 3);
                onProgress(2, 3);
                onProgress(3, 3);
                return Promise.resolve({ trashIds: [1, 3] });
            },
        );
        let finish!: () => void;
        const refresh = vi.fn(
            () =>
                new Promise<void>((resolve) => {
                    finish = resolve;
                }),
        );
        const removal = removeSelectedDuplicateGroups(
            [duplicateGroup()],
            progress,
            refresh,
        );
        await vi.waitFor(() => expect(refresh).toHaveBeenCalledOnce());
        expect(progress.mock.calls).toEqual([[25], [50], [75]]);
        expect(
            forgetPendingFavoriteFileIDs.mock.invocationCallOrder[0],
        ).toBeLessThan(refresh.mock.invocationCallOrder[0]!);
        finish();
        await expect(removal).resolves.toEqual(new Set(["group-1"]));
        expect(progress).toHaveBeenLastCalledWith(100);
    });
    test("does not clear local state or refresh when Rust execution fails", async () => {
        const failure = new Error("Rust request failed");
        executeDuplicateRemoval.mockRejectedValue(failure);
        const refresh = vi.fn();
        await expect(
            removeSelectedDuplicateGroups([duplicateGroup()], vi.fn(), refresh),
        ).rejects.toBe(failure);
        expect(forgetPendingFavoriteFileIDs).not.toHaveBeenCalled();
        expect(refresh).not.toHaveBeenCalled();
    });
    test("propagates refresh failures without reporting completion", async () => {
        const failure = new Error("Refresh failed");
        const progress = vi.fn();
        await expect(
            removeSelectedDuplicateGroups([duplicateGroup()], progress, () =>
                Promise.reject(failure),
            ),
        ).rejects.toBe(failure);
        expect(progress).not.toHaveBeenCalledWith(100);
    });
    test("passes multiple selected groups in one call and uses Rust's returned trash IDs", async () => {
        const first = duplicateGroup();
        const second = duplicateGroup();
        second.id = "group-2";
        for (const { file } of second.items) file.id += 3;
        executeDuplicateRemoval.mockResolvedValue({ trashIds: [1, 3, 4, 6] });
        await expect(
            removeSelectedDuplicateGroups([first, second], vi.fn(), vi.fn()),
        ).resolves.toEqual(new Set([first.id, second.id]));
        expect(executeDuplicateRemoval).toHaveBeenCalledOnce();
        expect(
            executeDuplicateRemoval.mock.calls[0]![1].groups.map((g) =>
                g.map((i) => i.fileId),
            ),
        ).toEqual([
            [1, 2, 3],
            [4, 5, 6],
        ]);
        expect(
            executeDuplicateRemoval.mock.calls[0]![1].files.map((f) => f.id),
        ).toEqual([1, 2, 3, 4, 5, 6]);
        expect(forgetPendingFavoriteFileIDs).toHaveBeenCalledExactlyOnceWith([
            1, 3, 4, 6,
        ]);
    });
    test("only refreshes when no groups are selected", async () => {
        const refresh = vi.fn();
        const progress = vi.fn();
        await expect(
            removeSelectedDuplicateGroups(
                [{ ...duplicateGroup(), isSelected: false }],
                progress,
                refresh,
            ),
        ).resolves.toEqual(new Set());
        expect(executeDuplicateRemoval).not.toHaveBeenCalled();
        expect(forgetPendingFavoriteFileIDs).not.toHaveBeenCalled();
        expect(refresh).toHaveBeenCalledOnce();
        expect(progress).toHaveBeenCalledExactlyOnceWith(100);
    });
});
