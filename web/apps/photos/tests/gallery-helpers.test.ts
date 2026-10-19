import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import { beforeEach, describe, expect, test, vi } from "vitest";
import {
    albumShortcutCollectionID,
    findCollectionCreatingIfNeeded,
    performCollectionOp,
    showCollectionSummaryWithAuthentication,
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

describe("album shortcut navigation", () => {
    test("routes collection shortcuts without consuming settings actions", () => {
        expect(albumShortcutCollectionID("shortcuts.uncategorized", 42)).toBe(
            42,
        );
        expect(albumShortcutCollectionID("shortcuts.hidden", 42)).toBe(
            PseudoCollectionID.hiddenItems,
        );
        expect(albumShortcutCollectionID("shortcuts.archive", 42)).toBe(
            PseudoCollectionID.archiveItems,
        );
        expect(albumShortcutCollectionID("shortcuts.trash", 42)).toBe(
            PseudoCollectionID.trash,
        );
        expect(
            albumShortcutCollectionID("utility.preferences", 42),
        ).toBeUndefined();
    });

    test("cancelled or failed authentication does not navigate or refresh authentication", async () => {
        for (const authenticate of [
            vi.fn().mockResolvedValue(false),
            vi.fn().mockRejectedValue(new Error("Authentication failed")),
        ]) {
            const lastAuthentication = { current: 0 };
            const navigate = vi.fn();
            await expect(
                showCollectionSummaryWithAuthentication(
                    PseudoCollectionID.hiddenItems,
                    true,
                    lastAuthentication,
                    authenticate,
                    navigate,
                ),
            ).resolves.toBe(false);
            expect(navigate).not.toHaveBeenCalled();
            expect(lastAuthentication.current).toBe(0);
        }
    });

    test("successful Hidden authentication is reused for five minutes", async () => {
        const lastAuthentication = { current: 0 };
        const authenticate = vi.fn().mockResolvedValue(true);
        const navigate = vi.fn();
        for (let i = 0; i < 2; i++) {
            await expect(
                showCollectionSummaryWithAuthentication(
                    PseudoCollectionID.hiddenItems,
                    true,
                    lastAuthentication,
                    authenticate,
                    navigate,
                ),
            ).resolves.toBe(true);
        }
        expect(authenticate).toHaveBeenCalledTimes(1);
        expect(navigate).toHaveBeenCalledTimes(2);
        lastAuthentication.current -= 5 * 60 * 1e3 + 1;
        await showCollectionSummaryWithAuthentication(
            PseudoCollectionID.hiddenItems,
            true,
            lastAuthentication,
            authenticate,
            navigate,
        );
        expect(authenticate).toHaveBeenCalledTimes(2);
    });

    test("regular collections and an already open Hidden section skip authentication", async () => {
        const authenticate = vi.fn();
        const navigate = vi.fn();
        for (const id of [
            42,
            PseudoCollectionID.trash,
            PseudoCollectionID.hiddenItems,
        ]) {
            await expect(
                showCollectionSummaryWithAuthentication(
                    id,
                    false,
                    { current: 0 },
                    authenticate,
                    navigate,
                ),
            ).resolves.toBe(true);
            expect(navigate).toHaveBeenLastCalledWith(id);
        }
        expect(authenticate).not.toHaveBeenCalled();
    });
});
