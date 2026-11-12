import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import type { Comment } from "ente-new/photos/services/comment";
import type { UnifiedReaction } from "ente-new/photos/services/social";
import { describe, expect, test } from "vitest";
import { buildFeedItems, emptyFeedSocialData } from "../src/services/feed";

const album = (id = 10, ownerID = 1, sharedAt?: number): Collection =>
    ({
        id,
        owner: { id: ownerID },
        name: `Album ${id}`,
        sharedAt,
    }) as Collection;
const photo = (id = 1, overrides: Partial<EnteFile> = {}): EnteFile =>
    ({
        id,
        collectionID: 10,
        ownerID: 1,
        metadata: { fileType: FileType.image },
        ...overrides,
    }) as EnteFile;
const comment = (id: string, overrides: Partial<Comment> = {}): Comment => ({
    id,
    collectionID: 10,
    fileID: 1,
    userID: 2,
    text: "Hello",
    isDeleted: false,
    createdAt: 100,
    updatedAt: 100,
    ...overrides,
});
const reaction = (
    id: string,
    overrides: Partial<UnifiedReaction> = {},
): UnifiedReaction => ({ ...comment(id), reactionType: "<3", ...overrides });
const build = (options: Partial<Parameters<typeof buildFeedItems>[0]> = {}) =>
    buildFeedItems({
        userID: 1,
        collections: [album()],
        files: [photo()],
        socialByCollection: {},
        hiddenCollectionIDs: new Set(),
        excludedFileIDs: new Set(),
        ...options,
    });

describe("social Feed grouping", () => {
    test("keeps replies to deleted parents while suppressing the parent's own activity", () => {
        const items = build({
            socialByCollection: {
                10: {
                    ...emptyFeedSocialData(),
                    comments: [
                        comment("parent", { userID: 1, isDeleted: true }),
                        comment("reply", { parentCommentID: "parent" }),
                    ],
                    reactions: [
                        reaction("parent-like", { commentID: "parent" }),
                    ],
                },
            },
        });
        expect(items).toHaveLength(1);
        expect(items[0]).toMatchObject({
            type: "reply",
            commentID: "reply",
            isOwnedByCurrentUser: true,
        });
    });
    test("groups newest first, deduplicates actors and excludes own/deleted activity", () => {
        const items = build({
            socialByCollection: {
                10: {
                    ...emptyFeedSocialData(),
                    comments: [
                        comment("old"),
                        comment("new", { userID: 3, createdAt: 200 }),
                        comment("repeat", { createdAt: 150 }),
                        comment("mine", { userID: 1, createdAt: 400 }),
                        comment("deleted", { isDeleted: true, createdAt: 500 }),
                    ],
                    reactions: [
                        reaction("like", { createdAt: 300 }),
                        reaction("unliked", {
                            isDeleted: true,
                            createdAt: 600,
                        }),
                        reaction("mine", { userID: 1, createdAt: 700 }),
                    ],
                },
            },
        });
        expect(items.map((item) => item.type)).toEqual([
            "photoLike",
            "comment",
        ]);
        expect(items[1]).toMatchObject({
            createdAt: 200,
            commentID: "new",
            actors: [{ userID: 3 }, { userID: 2 }],
            isOwnedByCurrentUser: true,
        });
    });

    test("keeps anonymous identities distinct and scopes groups to album membership", () => {
        const social = {
            ...emptyFeedSocialData(),
            reactions: [
                reaction("a", { userID: 0, anonUserID: "a" }),
                reaction("b", { userID: 0, anonUserID: "b" }),
                reaction("repeat-a", { userID: 0, anonUserID: "a" }),
            ],
        };
        const items = build({
            collections: [album(), album(11), album(12)],
            files: [photo(), photo(1, { collectionID: 11 })],
            socialByCollection: { 10: social, 11: social, 12: social },
        });
        expect(items).toHaveLength(2);
        expect(items.map((item) => item.collectionID)).toEqual([10, 11]);
        expect(items[0]!.actors.map((actor) => actor.anonUserID)).toEqual([
            "a",
            "b",
        ]);
    });

    test("classifies replies and likes using the target comment owner and media", () => {
        const items = build({
            files: [
                photo(1, {
                    metadata: {
                        fileType: FileType.video,
                    } as EnteFile["metadata"],
                }),
            ],
            socialByCollection: {
                10: {
                    ...emptyFeedSocialData(),
                    comments: [
                        comment("parent", { userID: 1 }),
                        comment("reply", {
                            parentCommentID: "parent",
                            createdAt: 200,
                        }),
                        comment("other-parent", { userID: 3 }),
                    ],
                    reactions: [
                        reaction("parent-like", { commentID: "parent" }),
                        reaction("reply-like", { commentID: "reply" }),
                        reaction("other-like", { commentID: "other-parent" }),
                    ],
                },
            },
        });
        expect(items.find((item) => item.type === "reply")).toMatchObject({
            commentID: "reply",
            isOwnedByCurrentUser: true,
            isVideo: true,
        });
        expect(items.find((item) => item.type === "replyLike")).toMatchObject({
            commentID: "reply",
            isOwnedByCurrentUser: false,
        });
        expect(
            items
                .filter((item) => item.type === "commentLike")
                .map((item) => item.isOwnedByCurrentUser)
                .sort(),
        ).toEqual([false, true]);
    });

    test("never exposes hidden, temporarily removed or inaccessible files", () => {
        const social = {
            ...emptyFeedSocialData(),
            reactions: [reaction("like")],
        };
        expect(
            build({
                socialByCollection: { 10: social },
                hiddenCollectionIDs: new Set([10]),
            }),
        ).toEqual([]);
        expect(
            build({
                socialByCollection: { 10: social },
                excludedFileIDs: new Set([1]),
            }),
        ).toEqual([]);
        expect(
            build({
                socialByCollection: { 10: social },
                files: [photo(1, { collectionID: 11 })],
            }),
        ).toEqual([]);
    });
});

describe("sharing activity", () => {
    const minute = 60 * 1_000_000;
    const added = (id: number, minutes: number, ownerID = 2) =>
        photo(id, { ownerID, collectionAddedAt: minutes * minute });

    test("groups consecutive ten-minute additions by album and uploader", () => {
        const items = build({
            files: [
                added(1, 1),
                added(2, 10),
                added(3, 19),
                added(4, 30),
                added(5, 18, 3),
            ],
        });
        expect(items.map((item) => item.files.map((file) => file.id))).toEqual([
            [4],
            [3, 2, 1],
            [5],
        ]);
    });

    test("uses original album contents as previews, excludes public uploads and keeps old share events", () => {
        const files = [added(1, 1), added(2, 10), added(3, 11), added(4, 12)];
        files[3]!.pubMagicMetadata = {
            version: 1,
            count: 1,
            data: { uploaderName: "Guest" },
        };
        const items = build({
            collections: [album(10, 2, 10 * minute)],
            files,
        });
        expect(items.map((item) => item.type)).toEqual([
            "sharedPhoto",
            "sharedCollection",
        ]);
        expect(items[0]!.files.map((file) => file.id)).toEqual([3]);
        expect(items[1]!.files.map((file) => file.id)).toEqual([2, 1]);
    });

    test("caps previews at thirty and final items at five hundred", () => {
        const previews = build({
            collections: [album(10, 2, 100 * minute)],
            files: Array.from({ length: 40 }, (_, i) => added(i + 1, i + 1)),
        });
        expect(previews[0]!.files).toHaveLength(30);
        const files = Array.from({ length: 501 }, (_, i) => photo(i + 1));
        const items = build({
            files,
            socialByCollection: {
                10: {
                    ...emptyFeedSocialData(),
                    reactions: files.map((file) =>
                        reaction(String(file.id), {
                            fileID: file.id,
                            createdAt: file.id,
                        }),
                    ),
                },
            },
        });
        expect(items).toHaveLength(500);
        expect(items[0]!.fileID).toBe(501);
        expect(items[499]!.fileID).toBe(2);
    });
});

test("excludes public uploads before capping sharing activity", () => {
    const legitimate = photo(1, { ownerID: 2, collectionAddedAt: 1 });
    const publicUploads = Array.from({ length: 1001 }, (_, i) =>
        photo(i + 2, {
            ownerID: 2,
            collectionAddedAt: i + 2,
            pubMagicMetadata: {
                version: 1,
                count: 1,
                data: { uploaderName: "Guest" },
            },
        }),
    );
    const items = build({ files: [legitimate, ...publicUploads] });
    expect(items).toHaveLength(1);
    expect(items[0]!.files).toEqual([legitimate]);
});

test("preserves public uploads already present when an album was shared as previews", () => {
    const file = photo(1, {
        ownerID: 2,
        collectionAddedAt: 1,
        pubMagicMetadata: {
            version: 1,
            count: 1,
            data: { uploaderName: "Guest" },
        },
    });
    const items = build({ collections: [album(10, 2, 2)], files: [file] });
    expect(items).toHaveLength(1);
    expect(items[0]!.type).toBe("sharedCollection");
    expect(items[0]!.files).toEqual([file]);
});
