import { findUserUncategorizedCollection } from "ente-media/collection";
import { describe, expect, test } from "vitest";

describe("findUserUncategorizedCollection", () => {
    test("selects the collection owned by the user", () => {
        const sharedCollection = { type: "uncategorized", owner: { id: 20 } };
        const ownCollection = { type: "uncategorized", owner: { id: 10 } };

        expect(
            findUserUncategorizedCollection(
                [sharedCollection, ownCollection],
                10,
            ),
        ).toBe(ownCollection);
    });

    test("does not return another user's collection", () => {
        const sharedCollection = { type: "uncategorized", owner: { id: 20 } };

        expect(
            findUserUncategorizedCollection([sharedCollection], 10),
        ).toBeUndefined();
    });
});
