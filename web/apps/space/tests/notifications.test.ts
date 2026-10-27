import { expect, test } from "vitest";
import type { SpaceNotification } from "../src/services/space";
import { commentNotificationText } from "../src/utils/comments";
import { notificationGroupKey } from "../src/utils/notifications";

const notification: SpaceNotification = {
    id: "latest",
    notificationIds: ["latest", "older"],
    kind: "comment",
    actors: [
        {
            id: "owner",
            spaceId: "owner",
            username: "anand",
            fullName: "Anand",
            friendsCount: 0,
        },
        {
            id: "friend",
            spaceId: "friend",
            username: "sam",
            fullName: "Sam",
            friendsCount: 0,
        },
    ],
    actorCount: 2,
    postId: 42,
    postSpaceId: "owner",
    postOwnerSlug: "anand",
    postOwnerName: "Anand Baburajan",
    createdAtMs: 0,
    read: false,
};

test("a group names the post owner even when they are its latest commenter", () => {
    expect(commentNotificationText(notification, "viewer")).toBe(
        "Commented on Anand's post",
    );
    expect(
        commentNotificationText({ ...notification, actorCount: 1 }, "viewer"),
    ).toBe("Commented on their post");
    expect(commentNotificationText(notification, "owner")).toBe(
        "Commented on your post",
    );
});

test.each(["comment", "post_like"])(
    "%s keeps its group across new events and pagination",
    (kind) => {
        expect(notificationGroupKey({ ...notification, kind })).toBe(
            notificationGroupKey({
                ...notification,
                kind,
                id: "older",
                commentId: "older-comment",
            }),
        );
        expect(notificationGroupKey({ ...notification, kind })).not.toBe(
            notificationGroupKey({ ...notification, kind, postId: 43 }),
        );
    },
);

test("reactions group by the exact comment, independently of replies", () => {
    const reaction = {
        ...notification,
        kind: "comment_reaction",
        commentId: "target",
    };
    expect(notificationGroupKey(reaction)).toBe(
        notificationGroupKey({ ...reaction, id: "older" }),
    );
    expect(notificationGroupKey(reaction)).not.toBe(
        notificationGroupKey({ ...reaction, commentId: "another-target" }),
    );
    expect(notificationGroupKey(reaction)).not.toBe(
        notificationGroupKey({
            ...reaction,
            kind: "comment_reply",
            commentId: "reply",
            replyToId: "target",
        }),
    );
});

test("replies to the same comment retain their group when the newest reply changes", () => {
    const reply = {
        ...notification,
        kind: "comment_reply",
        commentId: "newest-reply",
        replyToId: "target",
    };
    expect(notificationGroupKey(reply)).toBe(
        notificationGroupKey({
            ...reply,
            id: "older",
            commentId: "older-reply",
        }),
    );
    expect(notificationGroupKey(reply)).not.toBe(
        notificationGroupKey({ ...reply, replyToId: "another-target" }),
    );
});
