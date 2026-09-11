import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import { beforeEach, describe, expect, test, vi } from "vitest";
import {
    findCollectionCreatingIfNeeded,
    performCollectionOp,
} from "../src/components/gallery/helpers";

const collectionService = vi.hoisted(() => ({
    addOrCopyToCollection: vi.fn(),
    createUncategorizedCollection: vi.fn(),
    getOrCreateDefaultHiddenCollection: vi.fn(),
    moveFromCollection: vi.fn(),
    moveToCollection: vi.fn(),
    restoreToCollection: vi.fn(),
}));

vi.mock("ente-new/photos/services/collection", () => collectionService);

describe("performCollectionOp", () => {
    beforeEach(() => vi.clearAllMocks());

    test("moves hidden items using their real source collections", async () => {
        const destination = { id: 2 } as Collection;
        const files = [{ id: 1, collectionID: 1 }] as EnteFile[];

        await performCollectionOp(
            "move",
            destination,
            files,
            PseudoCollectionID.hiddenItems,
        );

        expect(collectionService.moveToCollection).toHaveBeenCalledWith(
            destination,
            files,
        );
        expect(collectionService.moveFromCollection).not.toHaveBeenCalled();
    });

    test("moves album files from the active source collection", async () => {
        const destination = { id: 2 } as Collection;
        const files = [{ id: 1, collectionID: 1 }] as EnteFile[];

        await performCollectionOp("move", destination, files, 1);

        expect(collectionService.moveFromCollection).toHaveBeenCalledWith(
            1,
            destination,
            files,
        );
        expect(collectionService.moveToCollection).not.toHaveBeenCalled();
    });
});

describe("findCollectionCreatingIfNeeded", () => {
    beforeEach(() => vi.clearAllMocks());

    test("resolves Hidden Items to the real default-hidden collection", async () => {
        const defaultHiddenCollection = { id: 1 } as Collection;
        collectionService.getOrCreateDefaultHiddenCollection.mockResolvedValue(
            defaultHiddenCollection,
        );

        await expect(
            findCollectionCreatingIfNeeded([], PseudoCollectionID.hiddenItems),
        ).resolves.toBe(defaultHiddenCollection);
    });
});
