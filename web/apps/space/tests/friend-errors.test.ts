import {
    encryptSpaceRootEntityKey,
    openSpaceAccountContext,
    type SpaceAccountCtxHandle,
} from "ente-space-wasm";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import {
    friendRequestErrorMessage,
    isFriendRequestCanceledError,
} from "../src/utils/friend-errors";

let ctx: SpaceAccountCtxHandle;
const publicKey = Buffer.from([9, ...new Array<number>(31).fill(0)]).toString(
    "base64",
);

beforeEach(async () => {
    const key = Buffer.alloc(32, 1).toString("base64");
    ctx = await openSpaceAccountContext({
        baseUrl: "http://localhost",
        clientPackage: "io.ente.space.web",
        spaceRootKeyB64: key,
        spaceSessionToken: "test-token",
        ownedSpaces: [
            {
                spaceId: "self",
                spaceSlug: "self",
                keyVersion: 1,
                rootWrappedSpaceKey: await encryptSpaceRootEntityKey(key, key),
            },
        ],
    });
});

afterEach(() => {
    ctx.free();
    vi.unstubAllGlobals();
});

test("an absent request reaches the cancellation handler", async () => {
    mockFetch(() => Response.json([]));
    const error: unknown = await ctx
        .confirmFriendRequest("self", 1n)
        .catch((e: unknown) => e);
    expect(error).toBeInstanceOf(Error);
    expect(isFriendRequestCanceledError(error)).toBe(true);
});

test.each(["confirm", "delete"] as const)(
    "%s recognizes a request removed on Museum",
    async (operation) => {
        mockAPI(
            "SPACE_FRIEND_REQUEST_UNAVAILABLE",
            operation == "confirm" ? 400 : 404,
        );
        const error: unknown = await (
            operation == "confirm"
                ? ctx.confirmFriendRequest("self", 1n)
                : ctx.deleteFriendRequest("self", 1n)
        ).catch((e: unknown) => e);
        expect(error).toBeInstanceOf(Error);
        expect(isFriendRequestCanceledError(error)).toBe(true);
    },
);

test.each([400, 404, 409, 500])(
    "HTTP %i without the unavailable code stays an error",
    async (status) => {
        mockAPI("BAD_REQUEST", status);
        for (const operation of [
            () => ctx.confirmFriendRequest("self", 1n),
            () => ctx.deleteFriendRequest("self", 1n),
        ]) {
            const error: unknown = await operation().catch((e: unknown) => e);
            expect(error).toBeInstanceOf(Error);
            expect(isFriendRequestCanceledError(error)).toBe(false);
        }
    },
);

test("a missing profile reaches the add-friend message", async () => {
    mockFetch(() => new Response(null, { status: 404 }));
    const error: unknown = await ctx
        .requestFriendByUsername("self", "missing")
        .catch((e: unknown) => e);
    expect(error).toBeInstanceOf(Error);
    expect(friendRequestErrorMessage(error, "missing")).toBe(
        "No Space profile found for @missing.",
    );
});

test.each([
    ["SPACE_SELF_FRIENDSHIP", 400, "You can't add yourself as a friend."],
    [
        "SPACE_FRIEND_REQUEST_LIMIT_REACHED",
        409,
        "@friend can't receive more friend requests right now.",
    ],
    ["CONFLICT", 409, "Couldn't send the friend request. Please try again."],
] as const)(
    "%s reaches the add-friend message",
    async (code, status, message) => {
        mockAPI(code, status);
        const error: unknown = await ctx
            .requestFriendByUsername("self", "friend")
            .catch((e: unknown) => e);
        expect(error).toBeInstanceOf(Error);
        expect(friendRequestErrorMessage(error, "friend")).toBe(message);
    },
);

const mockAPI = (code: string, status: number) =>
    mockFetch((request) => {
        const path = new URL(request.url).pathname;
        if (path == "/space/public/by-slug/friend") {
            return Response.json({
                spaceId: "friend",
                spaceSlug: "friend",
                owner: "friend",
                publicKey,
            });
        }
        if (
            request.method == "GET" &&
            path == "/spaces/self/friends/requests"
        ) {
            return Response.json([
                {
                    requestId: 1,
                    requester: {
                        spaceId: "friend",
                        spaceSlug: "friend",
                        publicKey,
                    },
                    createdAt: "2026-09-07T00:00:00Z",
                },
            ]);
        }
        return Response.json({ code }, { status });
    });

const mockFetch = (respond: (request: Request) => Response) =>
    vi.stubGlobal("fetch", (request: Request) => {
        const response = respond(request);
        Object.defineProperty(response, "url", { value: request.url });
        return Promise.resolve(response);
    });
