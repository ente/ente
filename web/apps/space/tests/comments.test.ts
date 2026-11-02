import { expect, test, vi } from "vitest";
import type { SpaceComment, SpaceNotification } from "../src/services/space";
import {
    commentNotificationText,
    commentReactionGroups,
    commentThreads,
    groupCommentReactions,
    isEmojiOnlyComment,
    validateCommentReplyTarget,
    type CommentReplyTarget,
} from "../src/utils/comments";

const comment = (
    commentId: string,
    second: number,
    parentId = "",
    replyToId = "",
): SpaceComment => ({
    commentId,
    unreadNotificationIds: [],
    parentId,
    replyToId,
    author: {
        id: commentId,
        username: commentId,
        fullName: commentId,
        friendsCount: 0,
    },
    text: commentId,
    createdAt: `2026-10-16T10:00:${String(second).padStart(2, "0")}Z`,
    deleted: false,
    canDelete: false,
    reactions: [],
});

const reaction = (
    id: string,
    emoji: string,
    isOwn = false,
): SpaceComment["reactions"][number] => ({
    actor: { id, username: id, fullName: id, friendsCount: 0 },
    emoji,
    isOwn,
});

test("reaction chips combine counts and move your optimistic reaction", () => {
    const reactions = [
        reaction("alice", "❤️"),
        reaction("you", "❤️", true),
        reaction("bob", "😂"),
    ];
    const original = [...reactions];
    expect(commentReactionGroups(reactions, "❤️")).toEqual([
        { emoji: "❤️", count: 2, isOwn: true },
        { emoji: "😂", count: 1, isOwn: false },
    ]);
    expect(commentReactionGroups(reactions, "😂")).toEqual([
        { emoji: "❤️", count: 1, isOwn: false },
        { emoji: "😂", count: 2, isOwn: true },
    ]);
    expect(commentReactionGroups(reactions, undefined)).toEqual([
        { emoji: "❤️", count: 1, isOwn: false },
        { emoji: "😂", count: 1, isOwn: false },
    ]);
    expect(reactions).toEqual(original);
});

test("the first reaction adds a chip and removing the last one clears it", () => {
    expect(commentReactionGroups([], "🥹")).toEqual([
        { emoji: "🥹", count: 1, isOwn: true },
    ]);
    expect(
        commentReactionGroups([reaction("you", "🥹", true)], undefined),
    ).toEqual([]);
});

test.each(["🥹", "😂 🥪", "👍🏽", "👨‍👩‍👧‍👦", "🇮🇳", "1️⃣", "  ❤️\n🙌  "])(
    "%s is a short emoji-only comment",
    (text) => expect(isEmojiOnlyComment(text)).toBe(true),
);

test.each(["", "   ", "123", "Nice 😂", "😂😂😂😂", "á", "hello"])(
    "%s keeps normal comment typography",
    (text) => expect(isEmojiOnlyComment(text)).toBe(false),
);

test("comments load and classify simple emojis without Intl.Segmenter", async () => {
    const descriptor = Object.getOwnPropertyDescriptor(Intl, "Segmenter")!;
    Reflect.deleteProperty(Intl, "Segmenter");
    vi.resetModules();
    try {
        const comments = await import("../src/utils/comments");
        expect(comments.isEmojiOnlyComment("😂 🥪")).toBe(true);
        expect(comments.isEmojiOnlyComment("Nice 😂")).toBe(false);
        expect(comments.isEmojiOnlyComment("😂😂😂😂")).toBe(false);
        expect(comments.isEmojiOnlyComment("👨‍👩‍👧‍👦")).toBe(false);
    } finally {
        Object.defineProperty(Intl, "Segmenter", descriptor);
        vi.resetModules();
    }
});

test("reactions stay grouped by emoji with your group and your row first", () => {
    const reactions = [
        reaction("alice", "❤️"),
        reaction("bob", "😂"),
        reaction("carol", "👍"),
        reaction("dave", "❤️"),
        reaction("you", "😂", true),
        reaction("eve", "😂"),
        reaction("frank", "👍"),
    ];
    const original = [...reactions];
    expect(
        groupCommentReactions(reactions).map(({ actor }) => actor.id),
    ).toEqual(["you", "bob", "eve", "alice", "dave", "carol", "frank"]);
    expect(reactions).toEqual(original);
});

test("removing your reaction restores first-appearance emoji group order", () => {
    const reactions = [
        reaction("alice", "❤️"),
        reaction("bob", "😂"),
        reaction("you", "😂", true),
        reaction("carol", "❤️"),
    ].filter(({ isOwn }) => !isOwn);
    expect(
        groupCommentReactions(reactions).map(({ actor }) => actor.id),
    ).toEqual(["alice", "carol", "bob"]);
    expect(groupCommentReactions([])).toEqual([]);
});

test.each([
    ["comment", "owner", "friend", "Commented on your post"],
    ["comment", "viewer", "friend", "Commented on @bob's post"],
    ["comment", "viewer", "owner", "Commented on their post"],
    ["comment_reply", "owner", "friend", "Replied to your comment"],
    ["comment_reply", "viewer", "friend", "Replied to your comment"],
    ["comment_reply", "viewer", "owner", "Replied to your comment"],
    ["comment_reaction", "owner", "friend", "Reacted to your comment"],
    ["comment_reaction", "viewer", "friend", "Reacted to your comment"],
    ["comment_reaction", "viewer", "owner", "Reacted to your comment"],
])(
    "%s names the post for viewer %s and actor %s",
    (kind, viewer, actor, expected) => {
        const notification: SpaceNotification = {
            id: "notification",
            notificationIds: ["notification"],
            kind,
            postSpaceId: "owner",
            postOwnerSlug: "bob",
            postId: 42,
            commentId: "reply",
            actors: [
                {
                    id: actor,
                    spaceId: actor,
                    username: "alice",
                    fullName: "Alice",
                    friendsCount: 0,
                },
            ],
            actorCount: 1,
            createdAtMs: 0,
            read: false,
        };
        expect(commentNotificationText(notification, viewer)).toBe(expected);
    },
);

test("comments are chronological with replies grouped under their root", () => {
    const entries = [
        comment("second", 2),
        comment("reply2", 4, "first", "reply1"),
        comment("first", 1),
        comment("reply1", 3, "first", "first"),
    ];
    const threads = commentThreads(entries);
    expect(threads.map((thread) => thread.comment.commentId)).toEqual([
        "first",
        "second",
    ]);
    expect(threads[0]?.replies.map((reply) => reply.commentId)).toEqual([
        "reply1",
        "reply2",
    ]);
    expect(threads[0]?.replies[1]?.replyToId).toBe("reply1");
    expect(entries[0]?.commentId).toBe("second");
});

test("deleted roots and their replies leave no visible thread", () => {
    const root = { ...comment("root", 1), text: undefined, deleted: true };
    expect(commentThreads([comment("reply", 2, "root", "root"), root])).toEqual(
        [],
    );
});

test("deleted reply branches disappear without hiding sibling replies", () => {
    const root = comment("root", 1);
    const deleted = { ...comment("deleted", 2, "root", "root"), deleted: true };
    const descendant = {
        ...comment("descendant", 3, "root", "deleted"),
        deleted: true,
    };
    const reply = comment("reply", 4, "root", "root");
    expect(commentThreads([root, deleted, descendant, reply])).toEqual([
        { comment: root, replies: [reply] },
    ]);
});

test("refresh preserves the selected reply without retaining profile metadata", () => {
    const target: CommentReplyTarget = {
        status: "selected",
        commentId: "reply",
    };
    const entries = [comment("root", 1), comment("reply", 2, "root", "root")];
    expect(validateCommentReplyTarget(target, entries)).toEqual(target);
    entries[1]!.author = { ...entries[1]!.author!, fullName: "" };
    expect(validateCommentReplyTarget(target, entries)).toEqual(target);
    expect(validateCommentReplyTarget(undefined, entries)).toBeUndefined();
});

test("a reply target becomes unavailable when its root is deleted", () => {
    const target: CommentReplyTarget = {
        status: "selected",
        commentId: "reply",
    };
    const root = {
        ...comment("root", 1),
        text: undefined,
        author: undefined,
        deleted: true,
    };
    expect(
        validateCommentReplyTarget(target, [
            root,
            comment("reply", 2, "root", "root"),
        ]),
    ).toEqual({ status: "unavailable" });
    expect(
        validateCommentReplyTarget({ status: "selected", commentId: "root" }, [
            root,
        ]),
    ).toEqual({ status: "unavailable" });
});

test.each(["missing", "deleted", "root-missing"])(
    "%s reply targets require an explicit choice before sending a new comment",
    (state) => {
        const target: CommentReplyTarget = {
            status: "selected",
            commentId: "reply",
        };
        const root = comment("root", 1);
        const reply = {
            ...comment("reply", 2, "root", "root"),
            deleted: state == "deleted",
        };
        const entries =
            state == "missing"
                ? [root]
                : state == "root-missing"
                  ? [reply]
                  : [root, reply];
        const invalidated = validateCommentReplyTarget(target, entries);
        expect(invalidated).toEqual({ status: "unavailable" });
        expect(
            validateCommentReplyTarget(invalidated, [
                comment("root", 1),
                comment("reply", 2, "root", "root"),
            ]),
        ).toEqual(invalidated);
    },
);
