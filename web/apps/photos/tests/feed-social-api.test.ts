import { decryptBoxBytes } from "ente-base/crypto";
import {
    getSocialUpdates,
    getUnifiedSocialDiff,
} from "ente-new/photos/services/social";
import { afterEach, beforeEach, expect, test, vi } from "vitest";

vi.mock("ente-base/crypto", () => ({ decryptBoxBytes: vi.fn() }));
vi.mock("ente-base/http", () => ({
    authenticatedRequestHeaders: () => Promise.resolve({}),
    ensureOk: (response: Response) => {
        if (!response.ok) throw new Error("Request failed");
    },
}));
vi.mock("ente-base/origins", () => ({
    apiURL: (path: string, params?: Record<string, number>) =>
        Promise.resolve(
            `https://api.ente.io${path}?${new URLSearchParams(Object.entries(params ?? {}).map(([key, value]) => [key, String(value)]))}`,
        ),
}));

const fetchMock = vi.fn<typeof fetch>();
const record = (id: string, updatedAt: number, isDeleted = false) => ({
    id,
    collectionID: 10,
    fileID: 1,
    userID: 2,
    isDeleted,
    createdAt: 1,
    updatedAt,
    cipher: isDeleted ? null : "cipher",
    nonce: isDeleted ? null : "nonce",
});
beforeEach(() => {
    vi.resetAllMocks();
    vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => vi.unstubAllGlobals());

test("Feed and file viewer exclude deleted reactions while raw cursors advance", async () => {
    fetchMock.mockImplementation(() =>
        Promise.resolve(
            Response.json({
                comments: [],
                reactions: [record("deleted", 50, true), record("active", 40)],
                hasMoreComments: false,
                hasMoreReactions: false,
            }),
        ),
    );
    vi.mocked(decryptBoxBytes).mockResolvedValue(
        new TextEncoder().encode("<3\0\0"),
    );
    const signal = new AbortController().signal;
    const result = await getUnifiedSocialDiff(10, "key", {
        commentsSinceTime: 10,
        reactionsSinceTime: 20,
        signal,
    });
    expect(
        result.reactions.map(({ id, isDeleted, reactionType }) => ({
            id,
            isDeleted,
            reactionType,
        })),
    ).toEqual([{ id: "active", isDeleted: false, reactionType: "<3" }]);
    expect(result.commentsUpdatedAt).toBe(10);
    expect(result.reactionsUpdatedAt).toBe(50);
    expect(fetchMock).toHaveBeenCalledWith(
        "https://api.ente.io/social/diff?collectionID=10&commentsSinceTime=10&reactionsSinceTime=20&limit=1000",
        { headers: {}, signal },
    );
    const viewer = await getUnifiedSocialDiff(10, "key", { fileID: 1 });
    expect(viewer.reactions.map(({ id }) => id)).toEqual(["active"]);
    expect(fetchMock).toHaveBeenLastCalledWith(
        "https://api.ente.io/social/diff?collectionID=10&fileID=1&commentsSinceTime=0&reactionsSinceTime=0&limit=1000",
        { headers: {}, signal: undefined },
    );
    expect(decryptBoxBytes).toHaveBeenCalledTimes(2);
});

test("a corrupt record does not stall the pagination cursor", async () => {
    fetchMock.mockResolvedValue(
        Response.json({
            comments: [record("unreadable", 200)],
            reactions: [],
            hasMoreComments: true,
            hasMoreReactions: false,
        }),
    );
    vi.mocked(decryptBoxBytes).mockRejectedValue(
        new Error("Invalid ciphertext"),
    );
    const result = await getUnifiedSocialDiff(10, "key", {
        commentsSinceTime: 0,
        reactionsSinceTime: 50,
    });
    expect(result.comments).toEqual([]);
    expect(result.commentsUpdatedAt).toBe(200);
    expect(result.reactionsUpdatedAt).toBe(50);
    expect(result.hasMoreComments).toBe(true);
});

test("handles a new account with no social update records", async () => {
    fetchMock.mockResolvedValue(Response.json({ updates: null }));
    expect(await getSocialUpdates()).toEqual([]);
});

test("file viewer decrypts comments and replies and preserves deleted parent metadata", async () => {
    fetchMock.mockResolvedValue(
        Response.json({
            comments: [
                { ...record("parent", 100), cipher: "parent-cipher" },
                {
                    ...record("reply", 200),
                    cipher: "reply-cipher",
                    parentCommentID: "parent",
                    parentCommentUserID: 2,
                },
                { ...record("deleted-parent", 300, true), userID: 3 },
            ],
            reactions: [],
            hasMoreComments: false,
            hasMoreReactions: false,
        }),
    );
    vi.mocked(decryptBoxBytes).mockImplementation(({ encryptedData }) =>
        Promise.resolve(
            new TextEncoder().encode(
                encryptedData === "parent-cipher"
                    ? "Original comment"
                    : "Reply text",
            ),
        ),
    );
    const result = await getUnifiedSocialDiff(10, "key", { fileID: 1 });
    expect(result.comments).toMatchObject([
        { id: "parent", fileID: 1, text: "Original comment", isDeleted: false },
        {
            id: "reply",
            fileID: 1,
            text: "Reply text",
            isDeleted: false,
            parentCommentID: "parent",
            parentCommentUserID: 2,
        },
        { id: "deleted-parent", text: "", isDeleted: true, userID: 3 },
    ]);
    expect(result.commentsUpdatedAt).toBe(300);
    expect(decryptBoxBytes).toHaveBeenCalledTimes(2);
});
