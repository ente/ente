import { encryptBox, openSpaceAccountContext } from "ente-space-wasm";
import { afterEach, expect, test, vi } from "vitest";
import { CachedSpacePost } from "../src/services/post-cache";

afterEach(() => {
    vi.unstubAllGlobals();
    vi.useRealTimers();
});

const photo = (index: number) => ({
    bytes: new TextEncoder().encode("RIFF\x04\x00\x00\x00WEBP"),
    options: {
        width: 1200 + index,
        height: 800,
        mediaType: "image/webp",
        thumbHash: `hash-${index}`,
    },
});

interface UploadedPost {
    encryptedPostKey: string;
    captionCipher: string;
    keyVersion: number;
    clientRequestId?: string;
    objects: {
        objectKey: string;
        position: number;
        metadataCipher: string;
        video?: { objectKey: string; metadataCipher: string };
    }[];
}

const uploadFixture = async (
    failSecondUpload = false,
    interceptRequest?: (request: Request) => Promise<Response> | undefined,
) => {
    const rootKey = btoa("r".repeat(32));
    const spaceKey = btoa("s".repeat(32));
    const { encryptedData, nonce } = await encryptBox(spaceKey, rootKey);
    const ctx = await openSpaceAccountContext({
        baseUrl: "http://localhost",
        spaceSessionToken: "test-session",
        spaceRootKeyB64: rootKey,
        clientPackage: "space-test",
        ownedSpaces: [
            {
                spaceId: "test-space",
                spaceSlug: "test",
                rootWrappedSpaceKey: Buffer.concat([
                    Buffer.from(nonce, "base64"),
                    Buffer.from(encryptedData, "base64"),
                ]).toString("base64"),
                publicKey: "",
                encryptedSecretKey: "",
                encryptedProfile: "",
                keyVersion: 1,
            },
        ],
    });
    const profile = await encryptBox(
        btoa(JSON.stringify({ fullName: " Test User " })),
        spaceKey,
    );
    const author = {
        spaceId: "test-space",
        spaceSlug: "test",
        keyVersion: 1,
        encryptedProfile: Buffer.concat([
            Buffer.from(profile.nonce, "base64"),
            Buffer.from(profile.encryptedData, "base64"),
        ]).toString("base64"),
    };
    const calls: string[] = [];
    const uploadedAssets = new Map<string, ArrayBuffer>();
    let presigned = 0;
    let created: UploadedPost | undefined;
    const record = () => ({
        ...created,
        postId: 501,
        spaceId: "test-space",
        spaceSlug: "test",
        author,
        createdAt: "2026-09-17T00:00:00Z",
        viewerLiked: false,
    });
    const respond = async (request: Request) => {
        const path = new URL(request.url).pathname;
        calls.push(`${request.method} ${path}`);
        if (path.endsWith("/friends/shares")) return Response.json([]);
        if (path.endsWith("/uploads/presign")) {
            const index = presigned++;
            return Response.json({
                url: `http://localhost/upload/${index}`,
                method: "PUT",
                headers: {},
                objectKey: `photo-${index}`,
                expiresIn: 300,
            });
        }
        if (request.method == "PUT") {
            uploadedAssets.set(
                `photo-${path.split("/").at(-1)}`,
                await request.arrayBuffer(),
            );
            return new Response("", {
                status: failSecondUpload && path == "/upload/1" ? 500 : 200,
            });
        }
        if (path.endsWith("/assets/redirect")) {
            const objectKey = new URL(request.url).searchParams.get(
                "objectKey",
            );
            return Response.json({
                url: `http://localhost/assets/${objectKey}`,
                expiresIn: 300,
            });
        }
        if (path.startsWith("/assets/")) {
            return new Response(
                uploadedAssets.get(path.slice("/assets/".length)),
            );
        }
        if (request.method == "POST" && path.endsWith("/posts")) {
            created = (await request.json()) as UploadedPost;
            return Response.json({ postId: 501 });
        }
        if (request.method == "GET" && path.endsWith("/posts/501")) {
            return Response.json(record());
        }
        if (
            request.method == "GET" &&
            (path.endsWith("/posts") || path.endsWith("/feed"))
        ) {
            return Response.json({ items: [record()], nextCursor: "older" });
        }
        throw new Error(`Unexpected request: ${request.method} ${path}`);
    };
    vi.stubGlobal("fetch", async (request: Request) => {
        const response = await (interceptRequest?.(request) ??
            respond(request));
        Object.defineProperty(response, "url", { value: request.url });
        return response;
    });
    const createPhotoPost = async (
        spaceId: string,
        photos: ReturnType<typeof photo>[],
        caption: string,
    ) => {
        const key = ctx.generatePostKey();
        const items = [];
        for (const photo of photos)
            items.push({
                preview: await ctx.uploadPostPhotoAsset(
                    spaceId,
                    key,
                    photo.bytes,
                    photo.options,
                ),
            });
        const postId = await ctx.createMediaPost(
            spaceId,
            key,
            items,
            crypto.randomUUID(),
            caption,
        );
        return ctx.getPost(spaceId, postId);
    };
    return { ctx, calls, author, created: () => created, createPhotoPost };
};

test.each([1, 3, 10])(
    "publishes %i encrypted photos in order with one caption",
    async (count) => {
        const { ctx, calls, created, createPhotoPost } = await uploadFixture();
        try {
            const result = await createPhotoPost(
                "test-space",
                Array.from({ length: count }, (_, index) => photo(index)),
                "One shared caption",
            );
            expect(result.caption).toBe("One shared caption");
            expect(result.photos.map((photo) => photo.asset.objectKey)).toEqual(
                Array.from({ length: count }, (_, i) => `photo-${i}`),
            );
            expect(result.photos.map((photo) => photo.width)).toEqual(
                Array.from({ length: count }, (_, i) => 1200 + i),
            );
            expect(result.photos.map((photo) => photo.thumbHash)).toEqual(
                Array.from({ length: count }, (_, i) => `hash-${i}`),
            );
            expect(created()?.objects.map((object) => object.position)).toEqual(
                Array.from({ length: count }, (_, i) => i),
            );
            expect(created()?.captionCipher).not.toContain(
                "One shared caption",
            );
            expect(
                created()?.objects.every((object) => object.metadataCipher),
            ).toBe(true);
            expect(
                calls.filter((call) => call == "POST /spaces/test-space/posts"),
            ).toHaveLength(1);
            expect(
                calls.indexOf("POST /spaces/test-space/posts"),
            ).toBeGreaterThan(calls.indexOf(`PUT /upload/${count - 1}`));
        } finally {
            ctx.free();
        }
    },
);

test("copies typed-array photo bytes without JavaScript iteration", async () => {
    const { ctx, created, createPhotoPost } = await uploadFixture();
    const input = photo(0);
    const buffer = new Uint8Array(input.bytes.length + 16);
    buffer.set(input.bytes, 8);
    input.bytes = buffer.subarray(8, 8 + input.bytes.length);
    Object.defineProperty(input.bytes, Symbol.iterator, {
        value: () => {
            throw new Error("Photo bytes must be copied in bulk");
        },
    });
    try {
        const post = await createPhotoPost("test-space", [input], "Caption");
        expect(created()?.objects).toHaveLength(1);
        const cached = CachedSpacePost.shape.imageAsset
            .unwrap()
            .parse(JSON.parse(JSON.stringify(post.photos[0]!.asset)));
        const downloaded = await ctx.downloadPostAsset(cached, post.spaceId);
        expect(downloaded).toEqual(photo(0).bytes);
    } finally {
        ctx.free();
    }
});

test("a failed photo upload does not publish a partial post", async () => {
    vi.useFakeTimers();
    const { ctx, calls, createPhotoPost } = await uploadFixture(true);
    try {
        const failure = expect(
            createPhotoPost(
                "test-space",
                [photo(0), photo(1), photo(2)],
                "Caption",
            ),
        ).rejects.toThrow();
        await vi.runAllTimersAsync();
        await failure;
        expect(calls).not.toContain("POST /spaces/test-space/posts");
    } finally {
        ctx.free();
    }
});

test.each([429, 503, "network"] as const)(
    "retries a %s transfer failure using the same bytes and upload URL",
    async (failure) => {
        vi.useFakeTimers();
        const bodies: ArrayBuffer[] = [];
        const urls: string[] = [];
        const { ctx, calls, createPhotoPost } = await uploadFixture(
            false,
            (request) => {
                if (request.method != "PUT") return undefined;
                return (async () => {
                    urls.push(request.url);
                    bodies.push(await request.arrayBuffer());
                    if (bodies.length == 1) {
                        if (failure == "network")
                            throw new TypeError("Failed to fetch");
                        return new Response("", { status: failure });
                    }
                    return new Response("", { status: 200 });
                })();
            },
        );
        try {
            const publication = createPhotoPost(
                "test-space",
                [photo(0)],
                "Caption",
            );
            await vi.runAllTimersAsync();
            await expect(publication).resolves.toMatchObject({ postId: 501 });
            expect(urls).toHaveLength(2);
            expect(urls[1]).toBe(urls[0]);
            expect(bodies[1]).toEqual(bodies[0]);
            expect(
                calls.filter((call) => call.endsWith("/uploads/presign")),
            ).toHaveLength(1);
        } finally {
            ctx.free();
        }
    },
);

test("retries a lost creation response with an identical request", async () => {
    vi.useFakeTimers();
    let lostRequest: UploadedPost | undefined;
    let attempts = 0;
    const { ctx, created, createPhotoPost } = await uploadFixture(
        false,
        (request) => {
            if (request.method != "POST" || !request.url.endsWith("/posts"))
                return undefined;
            attempts += 1;
            if (attempts > 1) return undefined;
            return (async () => {
                lostRequest = (await request.json()) as UploadedPost;
                throw new TypeError("Response lost");
            })();
        },
    );
    try {
        const publication = createPhotoPost(
            "test-space",
            [photo(0)],
            "Caption",
        );
        await vi.runAllTimersAsync();
        await expect(publication).resolves.toMatchObject({ postId: 501 });
        expect(attempts).toBe(2);
        expect(created()).toEqual(lostRequest);
        expect(lostRequest!.clientRequestId).toBeTruthy();
    } finally {
        ctx.free();
    }
});

test("preserves the unfinished upload limit code without retrying it", async () => {
    let attempts = 0;
    const { ctx, createPhotoPost } = await uploadFixture(false, (request) => {
        if (!request.url.endsWith("/uploads/presign")) return undefined;
        attempts += 1;
        return Promise.resolve(
            Response.json(
                { code: "SPACE_UPLOAD_LIMIT_REACHED" },
                { status: 429 },
            ),
        );
    });
    try {
        await expect(
            createPhotoPost("test-space", [photo(0)], "Caption"),
        ).rejects.toMatchObject({
            status: 429,
            code: "SPACE_UPLOAD_LIMIT_REACHED",
        });
        expect(attempts).toBe(1);
    } finally {
        ctx.free();
    }
});

test.each([503, "network"] as const)(
    "exposes structured diagnostics after exhausting %s upload retries",
    async (failure) => {
        vi.useFakeTimers();
        const { ctx, createPhotoPost } = await uploadFixture(
            false,
            (request) => {
                if (request.method != "PUT") return undefined;
                if (failure == "network")
                    return Promise.reject(new TypeError("Failed to fetch"));
                return Promise.resolve(new Response("", { status: failure }));
            },
        );
        try {
            const rejection = expect(
                createPhotoPost("test-space", [photo(0)], "Caption"),
            ).rejects.toMatchObject(
                failure == "network"
                    ? { code: "network_error" }
                    : { status: 503 },
            );
            await vi.runAllTimersAsync();
            await rejection;
        } finally {
            ctx.free();
        }
    },
);

test("exposes the permanent post limit as a diagnostic code", async () => {
    const { ctx, createPhotoPost } = await uploadFixture(false, (request) => {
        if (request.method != "POST" || !request.url.endsWith("/posts"))
            return undefined;
        return Promise.resolve(
            Response.json({ code: "CONFLICT" }, { status: 409 }),
        );
    });
    try {
        await expect(
            createPhotoPost("test-space", [photo(0)], "Caption"),
        ).rejects.toMatchObject({
            name: "post_limit_reached",
            code: "post_limit_reached",
        });
    } finally {
        ctx.free();
    }
});

test.each([0, 11])("rejects %i items before publishing", async (count) => {
    const { ctx, calls } = await uploadFixture();
    try {
        await expect(
            ctx.createMediaPost(
                "test-space",
                ctx.generatePostKey(),
                Array.from({ length: count }, (_, i) => ({
                    preview: {
                        objectKey: `photo-${i}`,
                        size: undefined,
                        metadataCipher: undefined,
                    },
                })),
                crypto.randomUUID(),
                "Caption",
            ),
        ).rejects.toThrow("Choose between 1 and 10 items");
        expect(calls).toHaveLength(0);
    } finally {
        ctx.free();
    }
});

test("pages expose typed profiles and mark corrupt posts unavailable", async () => {
    const { ctx, created, author, createPhotoPost } = await uploadFixture();
    try {
        const post = await createPhotoPost("test-space", [photo(0)], "Caption");
        expect(post.author.profile).toEqual({ fullName: "Test User" });
        expect(post.isUnavailable).toBe(false);
        const metadataCipher = created()!.objects[0]!.metadataCipher;
        created()!.objects[0]!.metadataCipher = "not-base64";
        for (const page of [
            await ctx.listPosts("test-space"),
            await ctx.listFeed("test-space"),
        ]) {
            expect(page.nextCursor).toBe("older");
            expect(page.items[0]!.isUnavailable).toBe(true);
            expect(page.items[0]!.caption).toBeUndefined();
            expect(page.items[0]!.photos).toEqual([]);
        }
        await expect(ctx.getPost("test-space", 501n)).rejects.toThrow();
        created()!.objects[0]!.metadataCipher = metadataCipher;
        author.encryptedProfile = "not-base64";
        const [withoutProfile] = (await ctx.listPosts("test-space")).items;
        expect(withoutProfile!.photos).toHaveLength(1);
        expect(withoutProfile!.isUnavailable).toBe(false);
        expect(withoutProfile!.author.profile).toBeUndefined();
    } finally {
        ctx.free();
    }
});

const videoBytes = new Uint8Array([
    0, 0, 0, 24, 102, 116, 121, 112, 109, 112, 52, 50,
]);

test.each([
    ["photo", "POST"],
    ["photo", "PUT"],
    ["video", "POST"],
    ["video", "PUT"],
])(
    "cancels a stalled %s %s request and allows another upload",
    async (kind, method) => {
        const started = Promise.withResolvers<Request>();
        let stalled = true;
        const { ctx, calls } = await uploadFixture(false, (request) => {
            if (!stalled || request.method != method) return;
            started.resolve(request);
            return new Promise((_, reject) => {
                request.signal.addEventListener(
                    "abort",
                    () => reject(request.signal.reason as Error),
                    { once: true },
                );
            });
        });
        const controller = new AbortController();
        const key = ctx.generatePostKey();
        const upload = (signal?: AbortSignal) =>
            kind == "photo"
                ? ctx.uploadPostPhotoAsset(
                      "test-space",
                      key,
                      photo(0).bytes,
                      photo(0).options,
                      signal,
                  )
                : ctx.uploadPostVideoAsset(
                      "test-space",
                      key,
                      videoBytes,
                      { width: 1280, height: 720, durationMs: 10000 },
                      signal,
                  );
        try {
            const canceled = expect(
                upload(controller.signal),
            ).rejects.toMatchObject({ name: "AbortError" });
            const request = await started.promise;
            controller.abort();
            await canceled;
            expect(request.signal.aborted).toBe(true);
            expect(calls).not.toContain("POST /spaces/test-space/posts");
            stalled = false;
            await expect(upload()).resolves.toHaveProperty("objectKey");
        } finally {
            ctx.free();
        }
    },
);

test.each(["photo", "video"])(
    "does not start an already-canceled %s upload",
    async (kind) => {
        const { ctx, calls } = await uploadFixture();
        const controller = new AbortController();
        controller.abort();
        const key = ctx.generatePostKey();
        try {
            const upload =
                kind == "photo"
                    ? ctx.uploadPostPhotoAsset(
                          "test-space",
                          key,
                          photo(0).bytes,
                          photo(0).options,
                          controller.signal,
                      )
                    : ctx.uploadPostVideoAsset(
                          "test-space",
                          key,
                          videoBytes,
                          { width: 1280, height: 720, durationMs: 10000 },
                          controller.signal,
                      );
            await expect(upload).rejects.toMatchObject({ name: "AbortError" });
            expect(calls).toHaveLength(0);
        } finally {
            ctx.free();
        }
    },
);

test("uploads a video larger than the previous photo limit", async () => {
    const { ctx, calls } = await uploadFixture();
    const bytes = new Uint8Array(10 * 1024 * 1024);
    bytes.set(videoBytes);
    try {
        await ctx.uploadPostVideoAsset(
            "test-space",
            ctx.generatePostKey(),
            bytes,
            { width: 1920, height: 1080, durationMs: 10000 },
        );
        expect(calls).toContain("PUT /upload/0");
    } finally {
        ctx.free();
    }
});

test("rejects a video exceeding the encrypted upload limit", async () => {
    const { ctx, calls } = await uploadFixture();
    const bytes = new Uint8Array(15 * 1024 * 1024);
    bytes.set(videoBytes);
    try {
        await expect(
            ctx.uploadPostVideoAsset(
                "test-space",
                ctx.generatePostKey(),
                bytes,
                { width: 1920, height: 1080, durationMs: 10000 },
            ),
        ).rejects.toThrow();
        expect(calls).toHaveLength(0);
    } finally {
        ctx.free();
    }
});

test.each([1, 5, 10])(
    "publishes ten encrypted items with %i videos and downloads their covers and clips",
    async (videoCount) => {
        const { ctx, created, calls } = await uploadFixture();
        try {
            const key = ctx.generatePostKey();
            const items = [];
            for (let i = 0; i < 10; i++) {
                const image = photo(i);
                const preview = await ctx.uploadPostPhotoAsset(
                    "test-space",
                    key,
                    image.bytes,
                    image.options,
                );
                const video =
                    i < videoCount
                        ? await ctx.uploadPostVideoAsset(
                              "test-space",
                              key,
                              videoBytes,
                              { width: 1280, height: 720, durationMs: 10000 },
                          )
                        : undefined;
                items.push({ preview, video });
            }
            const id = await ctx.createMediaPost(
                "test-space",
                key,
                items,
                "retry-id",
                "A mixed post",
            );
            const post = await ctx.getPost("test-space", id);
            expect(created()?.clientRequestId).toBe("retry-id");
            expect(post.photos).toHaveLength(10);
            expect(post.photos.filter((photo) => photo.video)).toHaveLength(
                videoCount,
            );
            expect(created()?.objects.map((object) => object.position)).toEqual(
                Array.from({ length: 10 }, (_, i) => i),
            );
            for (const [index, item] of post.photos.entries()) {
                expect(
                    await ctx.downloadPostAsset(item.asset, "test-space"),
                ).toEqual(photo(index).bytes);
                if (item.video) {
                    expect(item.video.durationMs).toBe(10000);
                    expect(
                        await ctx.downloadPostAsset(
                            item.video.asset,
                            "test-space",
                        ),
                    ).toEqual(videoBytes);
                    expect(
                        CachedSpacePost.parse(
                            JSON.parse(
                                JSON.stringify({
                                    postId: 501,
                                    spaceId: "test-space",
                                    friendID: "test-space",
                                    viewerLiked: false,
                                    timestampMs: 0,
                                    name: "Test",
                                    imageUrl: "",
                                    video: item.video,
                                }),
                            ),
                        ).video,
                    ).toBeDefined();
                }
            }
            expect(
                calls.filter((call) => call.startsWith("PUT /upload/")),
            ).toHaveLength(10 + videoCount);
            expect(
                calls.indexOf("POST /spaces/test-space/posts"),
            ).toBeGreaterThan(
                calls.lastIndexOf(`PUT /upload/${9 + videoCount}`),
            );
        } finally {
            ctx.free();
        }
    },
);

test.each([0, 10001])(
    "rejects an invalid video duration of %i ms before uploading",
    async (duration) => {
        const { ctx, calls } = await uploadFixture();
        try {
            await expect(
                ctx.uploadPostVideoAsset(
                    "test-space",
                    ctx.generatePostKey(),
                    videoBytes,
                    { width: 1280, height: 720, durationMs: duration },
                ),
            ).rejects.toThrow();
            expect(calls).toHaveLength(0);
        } finally {
            ctx.free();
        }
    },
);
