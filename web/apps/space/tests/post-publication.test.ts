import type { PostResponse } from "ente-space-wasm";
import { beforeEach, expect, test, vi } from "vitest";
import {
    createCurrentMediaPost,
    loadCurrentCreatedPost,
    type SpacePostUploadSession,
} from "../src/services/space";

const mocks = vi.hoisted(() => ({
    ctx: {
        generatePostKey: vi.fn(),
        uploadPostPhotoAsset: vi.fn(),
        uploadPostVideoAsset: vi.fn(),
        createMediaPost: vi.fn(),
        getPost: vi.fn(),
        downloadPostAsset: vi.fn(),
    },
    release: vi.fn(),
    cacheMedia: vi.fn(),
    cacheVideo: vi.fn(),
    cachePost: vi.fn(),
    logToDisk: vi.fn(),
}));

vi.mock("services/profile", () => ({
    ensureCurrentSpaceContext: () => Promise.resolve(mocks.ctx),
    releaseCurrentSpaceContext: mocks.release,
}));
vi.mock("services/feed-cache", () => ({
    prependCachedSpaceFeedPost: mocks.cachePost,
}));
vi.mock("services/media-cache", () => ({
    rememberCachedSpaceMediaBlobURL: mocks.cacheMedia,
    rememberCachedSpaceVideoBlob: mocks.cacheVideo,
    spacePostMediaCacheKey: (spaceId: string, key: string) =>
        `${spaceId}:${key}`,
    clearSpaceMediaURLCache: vi.fn(),
}));
vi.mock("ente-base/log", () => ({ default: { warn: vi.fn() } }));
vi.mock("ente-base/log-web", () => ({ logToDisk: mocks.logToDisk }));

const file = new File(["photo"], "photo.webp", { type: "image/webp" });
const images = [{ file, width: 1200, height: 800, thumbHash: "hash" }];
const asset = {
    objectKey: "photo-1",
    postId: 501,
    spaceId: "self",
    encryptedPostKey: "encrypted-key",
    keyVersion: 1,
};

beforeEach(() => {
    vi.resetAllMocks();
    mocks.ctx.generatePostKey.mockReturnValue(new Uint8Array(32));
    mocks.ctx.uploadPostPhotoAsset.mockResolvedValue({
        objectKey: "photo-1",
        size: 100,
        metadataCipher: "metadata",
    });
    mocks.ctx.createMediaPost.mockResolvedValue(501n);
    mocks.ctx.getPost.mockResolvedValue({
        postId: 501,
        spaceId: "self",
        caption: "Caption",
        createdAt: "2026-09-30T00:00:00Z",
        viewerLiked: false,
        author: {
            spaceId: "self",
            spaceSlug: "self",
            profile: { fullName: "Self" },
            avatar: { objectID: "avatar", keyVersion: 1 },
        },
        photos: [{ asset, width: 1200, height: 800, mediaType: "image/webp" }],
    });
    mocks.cacheMedia.mockResolvedValue("blob:preview");
});

test("confirms creation without waiting for a post readback", async () => {
    mocks.ctx.getPost.mockRejectedValue(new Error("Offline"));
    const session: SpacePostUploadSession = { uploads: [] };
    await expect(
        createCurrentMediaPost({
            images,
            caption: "Caption",
            spaceId: "self",
            session,
        }),
    ).resolves.toBe(501);
    expect(session.postId).toBe(501);
    expect(mocks.ctx.getPost).not.toHaveBeenCalled();
    expect(mocks.release).toHaveBeenCalledWith(mocks.ctx);
});

test("retains a committed session through a failed readback without creating another post", async () => {
    const session: SpacePostUploadSession = { uploads: [] };
    const request = { images, caption: "Caption", spaceId: "self", session };
    const postId = await createCurrentMediaPost(request);
    mocks.ctx.getPost.mockRejectedValueOnce(new Error("Offline"));
    await expect(
        loadCurrentCreatedPost("self", postId, images),
    ).rejects.toThrow("Offline");
    expect(await createCurrentMediaPost(request)).toBe(postId);
    const post = await loadCurrentCreatedPost("self", postId, images);
    expect(post.postId).toBe(postId);
    expect(mocks.ctx.createMediaPost).toHaveBeenCalledTimes(1);
    expect(mocks.ctx.uploadPostPhotoAsset).toHaveBeenCalledTimes(1);
    expect(mocks.ctx.getPost).toHaveBeenNthCalledWith(1, "self", 501n, "self");
    expect(mocks.ctx.getPost).toHaveBeenNthCalledWith(2, "self", 501n, "self");
});

test("hydrates a published post from its uploaded previews without another media download", async () => {
    const post = await loadCurrentCreatedPost("self", 501, images);
    expect(post.imageUrl).toBe("blob:preview");
    expect(post.photos?.[0]).toMatchObject({
        imageUrl: "blob:preview",
        imageAsset: asset,
    });
    expect(mocks.cacheMedia).toHaveBeenCalledWith("self:photo-1", file);
    expect(mocks.ctx.downloadPostAsset).not.toHaveBeenCalled();
    expect(mocks.cachePost).toHaveBeenCalledWith("self", post);
});

test("a cache failure after creation does not discard the saved post ID", async () => {
    const session: SpacePostUploadSession = { uploads: [] };
    const request = { images, caption: "Caption", spaceId: "self", session };
    const postId = await createCurrentMediaPost(request);
    mocks.cacheMedia.mockRejectedValueOnce(new Error("Cache unavailable"));
    await expect(
        loadCurrentCreatedPost("self", postId, images),
    ).rejects.toThrow("Cache unavailable");
    expect(await createCurrentMediaPost(request)).toBe(postId);
    expect(mocks.ctx.createMediaPost).toHaveBeenCalledTimes(1);
});

test("readback caches the exported MP4 under the published video asset", async () => {
    const created = (await mocks.ctx.getPost()) as PostResponse;
    const videoAsset = { ...asset, objectKey: "video-1" };
    created.photos[0]!.video = { asset: videoAsset, durationMs: 1000 };
    const video = {
        file: new File(["video"], "video.mp4", { type: "video/mp4" }),
        durationMs: 1000,
    };
    const post = await loadCurrentCreatedPost("self", 501, [
        { ...images[0]!, video },
    ]);
    expect(mocks.cacheVideo).toHaveBeenCalledWith("self:video-1", video.file);
    expect(post.video?.asset).toEqual({
        ...videoAsset,
        mediaType: "video/mp4",
    });
    expect(mocks.ctx.downloadPostAsset).not.toHaveBeenCalled();
});

test("a rejected creation is still reported as a failure", async () => {
    mocks.ctx.createMediaPost.mockRejectedValue(
        new Error("Post limit reached"),
    );
    const session: SpacePostUploadSession = { uploads: [] };
    await expect(
        createCurrentMediaPost({
            images,
            caption: "Caption",
            spaceId: "self",
            session,
        }),
    ).rejects.toThrow("Post limit reached");
    expect(session.postId).toBeUndefined();
    expect(mocks.ctx.getPost).not.toHaveBeenCalled();
});

test("retry keeps completed photos and the post request ID", async () => {
    mocks.ctx.uploadPostPhotoAsset
        .mockResolvedValueOnce({ objectKey: "first" })
        .mockRejectedValueOnce(new Error("HTTP 503"))
        .mockResolvedValueOnce({ objectKey: "second" });
    const session: SpacePostUploadSession = { uploads: [] };
    const request = {
        images: [images[0]!, images[0]!],
        caption: "Caption",
        spaceId: "self",
        session,
    };
    await expect(createCurrentMediaPost(request)).rejects.toThrow("HTTP 503");
    const requestId = session.requestId;
    expect(mocks.ctx.createMediaPost).not.toHaveBeenCalled();
    expect(mocks.logToDisk).toHaveBeenCalledWith(
        expect.stringContaining('"stage":"upload-preview","itemIndex":2'),
    );
    expect(mocks.logToDisk).toHaveBeenCalledWith(
        expect.stringContaining('"message":"HTTP 503"'),
    );
    expect(await createCurrentMediaPost(request)).toBe(501);
    expect(mocks.ctx.uploadPostPhotoAsset).toHaveBeenCalledTimes(3);
    expect(mocks.ctx.generatePostKey).toHaveBeenCalledTimes(1);
    expect(mocks.ctx.createMediaPost).toHaveBeenCalledWith(
        "self",
        session.key,
        [
            { preview: { objectKey: "first" }, video: undefined },
            { preview: { objectKey: "second" }, video: undefined },
        ],
        requestId,
        "Caption",
    );
});

test("retry after a failed video upload reuses its cover", async () => {
    mocks.ctx.uploadPostVideoAsset
        .mockRejectedValueOnce(new Error("Offline"))
        .mockResolvedValueOnce({ objectKey: "video" });
    const session: SpacePostUploadSession = { uploads: [] };
    const request = {
        images: [{ ...images[0]!, video: { file, durationMs: 1000 } }],
        caption: "",
        spaceId: "self",
        session,
    };
    await expect(createCurrentMediaPost(request)).rejects.toThrow("Offline");
    expect(await createCurrentMediaPost(request)).toBe(501);
    expect(mocks.ctx.uploadPostPhotoAsset).toHaveBeenCalledTimes(1);
    expect(mocks.ctx.uploadPostVideoAsset).toHaveBeenCalledTimes(2);
});

test("retry after a lost creation response keeps the request ID and uploaded assets", async () => {
    mocks.ctx.createMediaPost.mockRejectedValueOnce(new Error("Lost response"));
    const session: SpacePostUploadSession = { uploads: [] };
    const request = { images, caption: "Caption", spaceId: "self", session };
    await expect(createCurrentMediaPost(request)).rejects.toThrow(
        "Lost response",
    );
    expect(await createCurrentMediaPost(request)).toBe(501);
    expect(mocks.ctx.uploadPostPhotoAsset).toHaveBeenCalledTimes(1);
    expect(mocks.ctx.createMediaPost.mock.calls[1]).toEqual(
        mocks.ctx.createMediaPost.mock.calls[0],
    );
});

test.each(["Safari", "Chrome"])(
    "records the %s upload error and facts without exposing the space ID",
    async (browser) => {
        const message =
            "HTTP 429 SPACE_UPLOAD_LIMIT_REACHED at /spaces/private-space/uploads/presign";
        const error = Object.assign(new Error(message), {
            status: 429,
            code: "SPACE_UPLOAD_LIMIT_REACHED",
        });
        error.stack =
            browser == "Safari"
                ? "upload@https://space.test/app.js:10:5"
                : `Error: ${message}\n    at upload (https://space.test/app.js:10:5)`;
        mocks.ctx.uploadPostPhotoAsset.mockRejectedValueOnce(error);
        const session: SpacePostUploadSession = { uploads: [] };
        await expect(
            createCurrentMediaPost({
                images: [
                    {
                        ...images[0]!,
                        file: new File(["photo"], "Alice-family.jpg", {
                            type: "image/jpeg",
                        }),
                    },
                ],
                caption: "Family birthday",
                spaceId: "private-space",
                session,
            }),
        ).rejects.toBe(error);
        expect(error.message).toBe(message);
        const redactedMessage =
            "HTTP 429 SPACE_UPLOAD_LIMIT_REACHED at /spaces/[space-id]/uploads/presign";
        const redactedStack =
            browser == "Safari"
                ? "upload@https://space.test/app.js:10:5"
                : `Error: ${redactedMessage}\n    at upload (https://space.test/app.js:10:5)`;
        expect(mocks.logToDisk.mock.calls).toEqual([
            [
                `[error] Space post upload failed ${JSON.stringify({ requestId: session.requestId, stage: "upload-preview", itemIndex: 1, itemCount: 1, bytes: 5, status: 429, code: "SPACE_UPLOAD_LIMIT_REACHED", name: "Error", message: redactedMessage, stack: redactedStack })}`,
            ],
        ]);
    },
);
