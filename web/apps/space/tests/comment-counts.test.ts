import { beforeEach, expect, test, vi } from "vitest";
import {
    cachedCommentCount,
    clearCommentCounts,
    subscribeToCommentCounts,
} from "../src/services/comment-counts";
import { patchCachedSpaceFeedPost } from "../src/services/feed-cache";
import { ensureCurrentSpaceContext } from "../src/services/profile";
import {
    createCurrentComment,
    loadCurrentComments,
    loadCurrentFeedPage,
    loadCurrentSpaceProfilePostsPage,
} from "../src/services/space";

vi.mock("ente-base/log", () => ({ default: { warn: vi.fn() } }));
vi.mock("ente-base/log-web", () => ({ logToDisk: vi.fn() }));
vi.mock("ente-accounts/services/accounts-db", () => ({
    savedPartialLocalUser: () => ({ id: 1 }),
}));
vi.mock("services/feed-cache", () => ({ patchCachedSpaceFeedPost: vi.fn() }));
vi.mock("services/profile", () => ({
    ensureCurrentSpaceContext: vi.fn(),
    persistCurrentOwnedSpaces: vi.fn(),
    releaseCurrentSpaceContext: vi.fn(),
}));

const context = {
    createComment: vi.fn(),
    getPost: vi.fn(),
    listComments: vi.fn(),
    listFeed: vi.fn(),
    listPosts: vi.fn(),
};
const actor = {
    spaceId: "friend",
    spaceSlug: "maya",
    profile: { fullName: "Maya Patel" },
};
const post = (commentCount: number) => ({
    postId: 42,
    spaceId: "friend",
    commentCount,
    author: actor,
    createdAt: "2026-10-19T06:00:00Z",
    photos: [{ asset: {} }],
});

beforeEach(() => {
    vi.resetAllMocks();
    clearCommentCounts();
    vi.mocked(ensureCurrentSpaceContext).mockResolvedValue(
        context as unknown as Awaited<
            ReturnType<typeof ensureCurrentSpaceContext>
        >,
    );
});

test("keeps the updated count after the viewer closes and reopens with an old post snapshot", async () => {
    context.listFeed.mockResolvedValue({ items: [post(0)] });
    const feed = await loadCurrentFeedPage("viewer");
    const snapshot = feed.items[0]!;
    const updateViewer = vi.fn();
    const closeViewer = subscribeToCommentCounts(updateViewer);

    context.listComments.mockResolvedValue({
        items: [{ commentId: "comment", deleted: false, reactions: [] }],
    });
    await loadCurrentComments("viewer", "friend", 42);
    expect(updateViewer).toHaveBeenCalledOnce();
    expect(patchCachedSpaceFeedPost).toHaveBeenCalledWith("viewer", 42, {
        commentCount: 1,
    });
    closeViewer();

    expect(snapshot.commentCount).toBe(0);
    expect(cachedCommentCount("viewer", snapshot.postId)).toBe(1);
});

test.each([undefined, "parent"])(
    "updates the count when a send to %s finishes after the viewer closes",
    async (replyToId) => {
        context.listFeed.mockResolvedValue({ items: [post(0)] });
        const feed = await loadCurrentFeedPage("viewer");
        const updateViewer = vi.fn();
        const closeViewer = subscribeToCommentCounts(updateViewer);
        let finishSend!: () => void;
        context.createComment.mockReturnValue(
            new Promise<void>((resolve) => {
                finishSend = resolve;
            }),
        );
        context.getPost.mockResolvedValue(post(3));

        const send = createCurrentComment(
            "viewer",
            "friend",
            42,
            "comment",
            replyToId,
            "Hello",
        );
        await vi.waitFor(() =>
            expect(context.createComment).toHaveBeenCalled(),
        );
        expect(cachedCommentCount("viewer", 42)).toBe(0);
        closeViewer();
        finishSend();
        await send;

        expect(updateViewer).not.toHaveBeenCalled();
        expect(feed.items[0]!.commentCount).toBe(0);
        expect(cachedCommentCount("viewer", 42)).toBe(3);
        expect(patchCachedSpaceFeedPost).toHaveBeenCalledWith("viewer", 42, {
            commentCount: 3,
        });
        expect(context.getPost).toHaveBeenCalledWith("friend", 42n, "viewer");
    },
);

test("keeps the count unchanged when sending fails", async () => {
    context.listFeed.mockResolvedValue({ items: [post(2)] });
    await loadCurrentFeedPage("viewer");
    context.createComment.mockRejectedValue(new Error("Send failed"));

    await expect(
        createCurrentComment(
            "viewer",
            "friend",
            42,
            "comment",
            undefined,
            "Hi",
        ),
    ).rejects.toThrow("Send failed");

    expect(cachedCommentCount("viewer", 42)).toBe(2);
    expect(patchCachedSpaceFeedPost).not.toHaveBeenCalled();
});

test.each(["post", "cache"])(
    "does not report a saved comment as failed when refreshing the %s fails",
    async (failure) => {
        context.getPost.mockResolvedValue(post(1));
        if (failure == "post") {
            context.getPost.mockRejectedValue(new Error("Offline"));
        } else {
            vi.mocked(patchCachedSpaceFeedPost).mockRejectedValue(
                new Error("Storage unavailable"),
            );
        }

        await expect(
            createCurrentComment(
                "viewer",
                "friend",
                42,
                "comment",
                undefined,
                "Hi",
            ),
        ).resolves.toBeUndefined();
        expect(context.getPost).toHaveBeenCalled();
        if (failure == "cache") {
            expect(cachedCommentCount("viewer", 42)).toBe(1);
        }
    },
);

test("counts replies across pages and removes deleted comments from the total", async () => {
    context.listComments
        .mockResolvedValueOnce({
            items: [{ commentId: "parent", deleted: false, reactions: [] }],
            nextCursor: "replies",
        })
        .mockResolvedValueOnce({
            items: [
                {
                    commentId: "reply",
                    parentId: "parent",
                    deleted: false,
                    reactions: [],
                },
                { commentId: "deleted", deleted: true, reactions: [] },
            ],
        });
    await loadCurrentComments("viewer", "friend", 42);
    expect(cachedCommentCount("viewer", 42)).toBe(2);

    context.listComments.mockResolvedValue({
        items: [{ commentId: "parent", deleted: true, reactions: [] }],
    });
    await loadCurrentComments("viewer", "friend", 42);
    expect(cachedCommentCount("viewer", 42)).toBe(0);
});

test("returns loaded comments when persisting their count fails", async () => {
    context.listComments.mockResolvedValue({
        items: [
            {
                commentId: "comment",
                text: "Hello",
                deleted: false,
                reactions: [],
            },
        ],
    });
    vi.mocked(patchCachedSpaceFeedPost).mockRejectedValue(
        new Error("Storage unavailable"),
    );

    const comments = await loadCurrentComments("viewer", "friend", 42);

    expect(comments).toMatchObject([{ commentId: "comment", text: "Hello" }]);
    expect(cachedCommentCount("viewer", 42)).toBe(1);
});

test.each(["feed", "profile"])(
    "keeps a count updated by sending when an older %s response arrives",
    async (source) => {
        const pending = Promise.withResolvers<{
            items: ReturnType<typeof post>[];
        }>();
        const list = source == "feed" ? context.listFeed : context.listPosts;
        list.mockReturnValueOnce(pending.promise);
        const load = () =>
            source == "feed"
                ? loadCurrentFeedPage("viewer")
                : loadCurrentSpaceProfilePostsPage("friend", "viewer");
        const page = load();
        await vi.waitFor(() => expect(list).toHaveBeenCalled());
        context.getPost.mockResolvedValue(post(1));
        await createCurrentComment(
            "viewer",
            "friend",
            42,
            "comment",
            undefined,
            "Hi",
        );

        pending.resolve({ items: [post(0)] });
        expect((await page).items[0]!.commentCount).toBe(1);
        expect(cachedCommentCount("viewer", 42)).toBe(1);

        list.mockResolvedValue({ items: [post(0)] });
        expect((await load()).items[0]!.commentCount).toBe(0);
        expect(cachedCommentCount("viewer", 42)).toBe(0);
    },
);

test("does not restore a deleted comment's count from an older feed response", async () => {
    const pending = Promise.withResolvers<{
        items: ReturnType<typeof post>[];
    }>();
    context.listFeed.mockReturnValueOnce(pending.promise);
    const page = loadCurrentFeedPage("viewer");
    await vi.waitFor(() => expect(context.listFeed).toHaveBeenCalled());
    context.listComments.mockResolvedValue({ items: [] });
    await loadCurrentComments("viewer", "friend", 42);

    pending.resolve({ items: [post(1)] });
    expect((await page).items[0]!.commentCount).toBe(0);
    expect(cachedCommentCount("viewer", 42)).toBe(0);
});

test("keeps newer counts when an older comments request finishes", async () => {
    const pending = Promise.withResolvers<{ items: [] }>();
    context.listComments.mockReturnValueOnce(pending.promise);
    const comments = loadCurrentComments("viewer", "friend", 42);
    await vi.waitFor(() => expect(context.listComments).toHaveBeenCalled());
    context.getPost.mockResolvedValue(post(1));
    await createCurrentComment(
        "viewer",
        "friend",
        42,
        "comment",
        undefined,
        "Hi",
    );

    pending.resolve({ items: [] });
    await comments;
    expect(cachedCommentCount("viewer", 42)).toBe(1);
    expect(patchCachedSpaceFeedPost).toHaveBeenLastCalledWith("viewer", 42, {
        commentCount: 1,
    });
});

test("does not repopulate shared counts from a request started before logout", async () => {
    const pending = Promise.withResolvers<{
        items: ReturnType<typeof post>[];
    }>();
    context.listFeed.mockReturnValueOnce(pending.promise);
    const page = loadCurrentFeedPage("viewer");
    await vi.waitFor(() => expect(context.listFeed).toHaveBeenCalled());
    clearCommentCounts();

    pending.resolve({ items: [post(1)] });
    await page;
    expect(cachedCommentCount("viewer", 42)).toBeUndefined();
});

test("uses fresh feed and profile counts after other people comment or delete", async () => {
    context.listComments.mockResolvedValue({ items: [] });
    await loadCurrentComments("viewer", "friend", 42);

    context.listFeed.mockResolvedValue({ items: [post(3)] });
    await loadCurrentFeedPage("viewer");
    expect(cachedCommentCount("viewer", 42)).toBe(3);

    context.listPosts.mockResolvedValue({ items: [post(1)] });
    await loadCurrentSpaceProfilePostsPage("friend", "viewer");
    expect(cachedCommentCount("viewer", 42)).toBe(1);
});

test("isolates viewers and posts and clears counts on logout", async () => {
    context.listFeed.mockResolvedValue({ items: [post(2)] });
    await loadCurrentFeedPage("viewer");
    expect(cachedCommentCount("other-viewer", 42)).toBeUndefined();
    expect(cachedCommentCount("viewer", 43)).toBeUndefined();

    clearCommentCounts();
    expect(cachedCommentCount("viewer", 42)).toBeUndefined();
});
