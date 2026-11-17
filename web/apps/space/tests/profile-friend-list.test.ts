import { beforeEach, expect, test, vi } from "vitest";
import { ensureCurrentSpaceContext } from "../src/services/profile";
import { loadProfileFriendList } from "../src/services/space";

vi.mock("ente-base/log", () => ({ default: {} }));
vi.mock("ente-base/log-web", () => ({ logToDisk: vi.fn() }));
vi.mock("services/feed-cache", () => ({}));
vi.mock("ente-accounts/services/accounts-db", () => ({
    savedPartialLocalUser: () => ({ id: 1 }),
}));
vi.mock("services/profile", () => ({
    ensureCurrentSpaceContext: vi.fn(),
    releaseCurrentSpaceContext: vi.fn(),
}));

const ctx = {
    listSpaceFriends: vi
        .fn()
        .mockResolvedValue([
            {
                friend: {
                    spaceSlug: "alice",
                    profile: { fullName: "Alice Young" },
                },
            },
        ]),
    listProfileFriendUsernames: vi
        .fn()
        .mockResolvedValue(["alice", "dan", "jo", "maya", "me"]),
    listFriendRequests: vi
        .fn()
        .mockResolvedValue([
            { requester: { spaceSlug: "maya" }, requestId: 19 },
        ]),
    listSentFriendRequests: vi
        .fn()
        .mockResolvedValue([{ target: { spaceSlug: "jo" }, requestId: 22 }]),
};

beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(ensureCurrentSpaceContext).mockResolvedValue(
        ctx as unknown as Awaited<ReturnType<typeof ensureCurrentSpaceContext>>,
    );
});

test("another profile's friends have the viewer's relationship and pending request IDs", async () => {
    const rows = await loadProfileFriendList("viewer-id", "me", "caleb");
    expect(ctx.listProfileFriendUsernames).toHaveBeenCalledWith(
        "viewer-id",
        "caleb",
    );
    expect(rows).toMatchObject([
        {
            username: "alice",
            friend: { fullName: "Alice Young" },
            status: "friend",
        },
        { username: "dan", status: "available" },
        { username: "jo", status: "sent", requestId: 22 },
        { username: "maya", status: "received", requestId: 19 },
        { username: "me", status: "self" },
    ]);
});
