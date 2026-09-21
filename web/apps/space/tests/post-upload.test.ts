import { encryptBox, openSpaceAccountContext } from "ente-space-wasm";
import { afterEach, expect, test, vi } from "vitest";

afterEach(() => vi.unstubAllGlobals());

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
    objects: { objectKey: string; position: number; metadataCipher: string }[];
}

const uploadFixture = async (failSecondUpload = false) => {
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
    const calls: string[] = [];
    const uploadedAssets = new Map<string, ArrayBuffer>();
    let presigned = 0;
    let created: UploadedPost | undefined;
    const respond = async (request: Request) => {
        const path = new URL(request.url).pathname;
        calls.push(`${request.method} ${path}`);
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
            return Response.json({
                ...created,
                postId: 501,
                spaceId: "test-space",
                spaceSlug: "test",
                author: { spaceId: "test-space", spaceSlug: "test" },
                createdAt: "2026-09-17T00:00:00Z",
                viewerLiked: false,
            });
        }
        throw new Error(`Unexpected request: ${request.method} ${path}`);
    };
    vi.stubGlobal("fetch", async (request: Request) => {
        const response = await respond(request);
        Object.defineProperty(response, "url", { value: request.url });
        return response;
    });
    return { ctx, calls, created: () => created };
};

test.each([1, 3, 10])(
    "publishes %i encrypted photos in order with one caption",
    async (count) => {
        const { ctx, calls, created } = await uploadFixture();
        try {
            const result = await ctx.createPhotoPost(
                "test-space",
                Array.from({ length: count }, (_, index) => photo(index)),
                "One shared caption",
            );
            expect(result.caption).toBe("One shared caption");
            expect(result.objects.map((object) => object.objectKey)).toEqual(
                Array.from({ length: count }, (_, i) => `photo-${i}`),
            );
            expect(result.objects.map((object) => object.width)).toEqual(
                Array.from({ length: count }, (_, i) => 1200 + i),
            );
            expect(result.objects.map((object) => object.thumbHash)).toEqual(
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
    const { ctx, created } = await uploadFixture();
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
        const post = await ctx.createPhotoPost(
            "test-space",
            [input],
            "Caption",
        );
        expect(created()?.objects).toHaveLength(1);
        const downloaded = await ctx.downloadPostAssetWithKey(
            post.spaceId,
            post.encryptedPostKey,
            post.keyVersion,
            post.spaceId,
            post.objects[0]!.objectKey,
        );
        expect(downloaded).toEqual(photo(0).bytes);
    } finally {
        ctx.free();
    }
});

test("a failed photo upload does not publish a partial post", async () => {
    const { ctx, calls } = await uploadFixture(true);
    try {
        await expect(
            ctx.createPhotoPost(
                "test-space",
                [photo(0), photo(1), photo(2)],
                "Caption",
            ),
        ).rejects.toThrow();
        expect(calls).not.toContain("POST /spaces/test-space/posts");
    } finally {
        ctx.free();
    }
});

test.each([0, 11])("rejects %i photos before uploading", async (count) => {
    const { ctx, calls } = await uploadFixture();
    try {
        await expect(
            ctx.createPhotoPost(
                "test-space",
                Array.from({ length: count }, (_, i) => photo(i)),
                "Caption",
            ),
        ).rejects.toThrow("Choose between 1 and 10 photos");
        expect(calls).toHaveLength(0);
    } finally {
        ctx.free();
    }
});
