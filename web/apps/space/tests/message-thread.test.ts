import { expect, test } from "vitest";
import type { SpaceMessage } from "../src/services/space";
import { reconcileMessageThread } from "../src/utils/message-thread";

const actor = {
    avatarUrl: null,
    friendsCount: 0,
    fullName: "",
    id: "space-1",
    spaceId: "space-1",
    username: "alice",
};

const message = (id: string, createdAtMs: number): SpaceMessage => ({
    createdAtMs,
    id,
    isDeleted: false,
    kind: "regular",
    recipient: actor,
    sender: actor,
    text: id,
    updatedAtMs: createdAtMs,
});

test("refresh drops deleted and paged-out messages while retaining a pending send", () => {
    const loaded = [message("server-3", 3), message("server-5", 5)];
    const current = [
        message("paged-out", 1),
        message("deleted", 2),
        message("server-3", 3),
        message("space-local-message-1", 4),
    ];

    expect(reconcileMessageThread(loaded, current).map(({ id }) => id)).toEqual(
        ["server-3", "space-local-message-1", "server-5"],
    );
});

test("refresh preserves server ordering for messages in the same millisecond", () => {
    const loaded = [message("server-z", 3), message("server-a", 3)];
    const current = [message("space-local-message-1", 3)];

    expect(reconcileMessageThread(loaded, current).map(({ id }) => id)).toEqual(
        ["server-z", "server-a", "space-local-message-1"],
    );
});

test("thread load retains a send confirmed after the request began", () => {
    const loaded = [message("server-1", 1), message("server-3", 3)];
    const current = [message("server-4", 4)];

    expect(
        reconcileMessageThread(loaded, current, new Set(["server-4"])).map(
            ({ id }) => id,
        ),
    ).toEqual(["server-1", "server-3", "server-4"]);
});

test("thread load does not duplicate a confirmed send it already includes", () => {
    const loaded = [message("server-1", 1), message("server-4", 4)];
    const current = [message("server-4", 4)];

    expect(
        reconcileMessageThread(loaded, current, new Set(["server-4"])).map(
            ({ id }) => id,
        ),
    ).toEqual(["server-1", "server-4"]);
});
