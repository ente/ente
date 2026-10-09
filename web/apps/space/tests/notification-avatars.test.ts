import { beforeEach, expect, test, vi } from "vitest";
import {
    cachedSpaceMediaBlobURL,
    cachedSpaceMediaBlobURLIfPresent,
    spaceProfileMediaCacheKey,
} from "../src/services/media-cache";
import {
    ensureCurrentSpaceContext,
    loadExistingSpaceProfile,
    releaseCurrentSpaceContext,
} from "../src/services/profile";
import {
    loadCurrentFriendAvatarURL,
    loadCurrentMessageConversations,
    loadCurrentNotifications,
} from "../src/services/space";

vi.mock("ente-base/log", () => ({ default: { warn: vi.fn() } }));
vi.mock("ente-accounts/services/accounts-db", () => ({
    savedPartialLocalUser: () => ({ id: 1 }),
}));
vi.mock("ente-base/log-web", () => ({ logToDisk: vi.fn() }));
vi.mock("services/feed-cache", () => ({}));
vi.mock("services/profile", () => ({
    ensureCurrentSpaceContext: vi.fn(),
    loadExistingSpaceProfile: vi.fn(),
    releaseCurrentSpaceContext: vi.fn(),
}));
vi.mock("services/media-cache", async (importOriginal) => ({
    ...(await importOriginal<typeof import("../src/services/media-cache")>()),
    cachedSpaceMediaBlobURL: vi.fn(),
    cachedSpaceMediaBlobURLIfPresent: vi.fn(),
}));

const actor = {
    spaceId: "friend-space",
    spaceSlug: "maya",
    profile: { fullName: "Maya Patel" },
    avatar: { objectID: "avatar-1", keyVersion: 2 },
};
const createdAt = "2026-10-07T06:00:00Z";
const context = {
    downloadSpaceAvatar: vi.fn(),
    listNotifications: vi.fn(),
    listConversations: vi.fn(),
};

beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(ensureCurrentSpaceContext).mockResolvedValue(
        context as unknown as Awaited<
            ReturnType<typeof ensureCurrentSpaceContext>
        >,
    );
    context.listNotifications.mockResolvedValue({
        items: [
            {
                notificationId: "like-1",
                notificationIds: ["like-1"],
                kind: "post_like",
                actors: [actor],
                actorCount: 1,
                unread: true,
                postId: 42,
                createdAt,
            },
        ],
    });
    context.listConversations.mockResolvedValue({
        friends: [{ friend: actor, createdAt }],
        chatSummaries: new Map(),
        pendingRequests: [],
    });
    vi.mocked(cachedSpaceMediaBlobURLIfPresent).mockResolvedValue(undefined);
});

test("notifications restore the same cached avatar as Messages before returning rows", async () => {
    vi.mocked(cachedSpaceMediaBlobURLIfPresent).mockResolvedValue(
        "blob:cached-avatar",
    );

    const notifications = await loadCurrentNotifications("viewer-space");
    const messages = await loadCurrentMessageConversations("viewer-space");

    expect(notifications.items[0]?.actors[0]?.avatarUrl).toBe(
        "blob:cached-avatar",
    );
    expect(notifications.items[0]?.actors[0]).toEqual(
        messages.items[0]?.friend,
    );
    expect(cachedSpaceMediaBlobURLIfPresent).toHaveBeenCalledWith(
        spaceProfileMediaCacheKey(actor.spaceId, "avatar", "avatar-1", 2),
    );
    expect(context.downloadSpaceAvatar).not.toHaveBeenCalled();
});

test("notification groups preserve full counts with only the latest two actors", async () => {
    const notificationIds = Array.from(
        { length: 50 },
        (_, i) => `like-${i + 1}`,
    );
    const secondActor = {
        ...actor,
        spaceId: "second-friend",
        spaceSlug: "sam",
        profile: { fullName: "Sam Reed" },
    };
    context.listNotifications.mockResolvedValue({
        items: [
            {
                notificationId: "like-50",
                notificationIds,
                kind: "post_like",
                actors: [actor, secondActor],
                actorCount: 50,
                unread: true,
                postId: 42,
                createdAt,
            },
        ],
        nextCursor: "next-post-group",
    });

    const page = await loadCurrentNotifications("viewer-space");

    expect(context.listNotifications).toHaveBeenCalledWith(
        "viewer-space",
        undefined,
        20,
    );
    expect(page.items).toHaveLength(1);
    expect(page.items[0]).toMatchObject({
        id: "like-50",
        notificationIds,
        actorCount: 50,
        read: false,
        actors: [{ fullName: "Maya Patel" }, { fullName: "Sam Reed" }],
    });
    expect(page.nextCursor).toBe("next-post-group");
});

test("uncached avatars use the selected viewer without loading another profile", async () => {
    const page = await loadCurrentNotifications("viewer-space");
    const friend = page.items[0]!.actors[0]!;
    vi.mocked(cachedSpaceMediaBlobURL).mockImplementation(async (_, load) => {
        await load();
        return "blob:downloaded-avatar";
    });
    context.downloadSpaceAvatar.mockResolvedValue(new Uint8Array([1]));

    await expect(
        loadCurrentFriendAvatarURL(friend, "viewer-space"),
    ).resolves.toBe("blob:downloaded-avatar");

    expect(context.downloadSpaceAvatar).toHaveBeenCalledWith(
        actor.spaceId,
        "viewer-space",
        "avatar-1",
        2,
    );
    expect(loadExistingSpaceProfile).not.toHaveBeenCalled();
    expect(releaseCurrentSpaceContext).toHaveBeenCalledWith(context);
});

test("friend notifications preserve request targets without inventing post targets", async () => {
    context.listNotifications.mockResolvedValue({
        items: [
            {
                notificationId: "request-1",
                notificationIds: ["request-1"],
                kind: "friend_request",
                actors: [{ spaceId: "requester", spaceSlug: "maya" }],
                actorCount: 1,
                friendRequestId: 7,
                createdAt,
                unread: true,
            },
            {
                notificationId: "accepted-1",
                notificationIds: ["accepted-1"],
                kind: "friend_accepted",
                actors: [actor],
                actorCount: 1,
                createdAt,
                unread: false,
            },
        ],
    });
    const page = await loadCurrentNotifications("viewer-space");
    expect(page.items).toHaveLength(2);
    expect(page.items[0]).toMatchObject({
        kind: "friend_request",
        friendRequestId: 7,
        postId: undefined,
        read: false,
    });
    expect(page.items[0]?.actors[0]?.fullName).toBe("maya");
    expect(page.items[0]?.actors[0]?.avatarObjectID).toBeUndefined();
    expect(page.items[1]).toMatchObject({
        kind: "friend_accepted",
        friendRequestId: undefined,
        postId: undefined,
        read: true,
    });
});

test("already hydrated avatars do not start another lookup or download", async () => {
    const page = await loadCurrentNotifications("viewer-space");
    const friend = {
        ...page.items[0]!.actors[0]!,
        avatarUrl: "blob:cached-avatar",
    };
    vi.clearAllMocks();

    await expect(
        loadCurrentFriendAvatarURL(friend, "viewer-space"),
    ).resolves.toBe("blob:cached-avatar");

    expect(cachedSpaceMediaBlobURLIfPresent).not.toHaveBeenCalled();
    expect(ensureCurrentSpaceContext).not.toHaveBeenCalled();
});
