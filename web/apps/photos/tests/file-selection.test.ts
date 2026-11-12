import type { EnteFile } from "ente-media/file";
import { expect, test } from "vitest";
import {
    emptySelection,
    retainVisibleSelection,
} from "../src/components/gallery/media/file-selection";

const files = [
    { id: 1, ownerID: 1 },
    { id: 2, ownerID: 2 },
    { id: 3, ownerID: 1 },
] as EnteFile[];
const selected = {
    ...emptySelection,
    1: true,
    2: true,
    count: 2,
    ownCount: 1,
    collectionID: 10,
};

test("sorting and refreshed file objects retain the selection", () => {
    expect(
        retainVisibleSelection(
            selected,
            files.toReversed().map((file) => ({ ...file })),
            1,
        ),
    ).toBe(selected);
});

test("removing a selected photo updates counts without selecting an upload", () => {
    const next = retainVisibleSelection(selected, files.slice(1), 1);
    expect(next).toMatchObject({
        2: true,
        count: 1,
        ownCount: 0,
        collectionID: 10,
    });
    expect(next[1]).toBeUndefined();
    expect(next[3]).toBeUndefined();
});

test("empty results remove the selection", () => {
    expect(retainVisibleSelection(selected, [], 1)).toMatchObject({
        count: 0,
        ownCount: 0,
    });
});

test("duplicate collection memberships do not inflate selected counts", () => {
    expect(retainVisibleSelection(selected, [...files, files[0]!], 1)).toBe(
        selected,
    );
});
