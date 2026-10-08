import { afterEach, beforeEach, expect, test, vi } from "vitest";
import {
    prepareSpaceAvatarImageFromCrop,
    prepareSpaceCoverImageFromCrop,
    prepareSpacePostImageFromEdit,
} from "../src/utils/post-image";

vi.mock("ente-media/heic-convert", () => ({ heicToJPEG: vi.fn() }));
vi.mock("utils/thumbhash", () => ({ thumbHashBase64FromCanvas: () => "hash" }));

const encode =
    vi.fn<(callback: BlobCallback, type?: string, quality?: number) => void>();
const oversizedPNG = new Blob([new Uint8Array(5413019)], { type: "image/png" });
const jpeg = new Blob(["encoded jpeg"], { type: "image/jpeg" });
const file = new File(["photo"], "IMG_3238.JPG", {
    type: "image/jpeg",
    lastModified: 1234,
});
const crop = { x: 0, y: 0, width: 4284, height: 5712 };

beforeEach(() => {
    encode.mockReset().mockImplementation((callback, type) => {
        callback(type == "image/webp" ? oversizedPNG : jpeg);
    });
    vi.stubGlobal(
        "Image",
        class {
            naturalWidth = 4284;
            naturalHeight = 5712;
            onload?: () => void;
            set src(_value: string) {
                queueMicrotask(() => this.onload?.());
            }
        },
    );
    vi.stubGlobal("document", {
        createElement: () => ({
            width: 0,
            height: 0,
            getContext: () => ({
                drawImage: vi.fn(),
                translate: vi.fn(),
                rotate: vi.fn(),
            }),
            toBlob: encode,
        }),
    });
});

afterEach(() => {
    vi.unstubAllGlobals();
});

test.each([
    { kind: "post", prepare: () => prepareSpacePostImageFromEdit(file) },
    {
        kind: "cropped post",
        prepare: () => prepareSpacePostImageFromEdit(file, crop),
    },
    {
        kind: "rotated post",
        prepare: () => prepareSpacePostImageFromEdit(file, undefined, 90),
    },
    {
        kind: "avatar",
        prepare: () =>
            prepareSpaceAvatarImageFromCrop(file, "blob:preview", crop),
    },
    {
        kind: "cover",
        prepare: () =>
            prepareSpaceCoverImageFromCrop(file, "blob:preview", crop),
    },
])(
    "prepares a JPEG $kind when WebP encoding produces an oversized PNG",
    async ({ prepare }) => {
        const prepared = await prepare();
        expect(prepared.file.name).toBe("IMG_3238.jpg");
        expect(prepared.file.type).toBe("image/jpeg");
        expect(prepared.file.size).toBe(jpeg.size);
        expect(prepared.file.lastModified).toBe(file.lastModified);
        expect(encode).toHaveBeenCalledTimes(2);
        expect(encode).toHaveBeenNthCalledWith(
            1,
            expect.any(Function),
            "image/webp",
            0.82,
        );
        expect(encode).toHaveBeenNthCalledWith(
            2,
            expect.any(Function),
            "image/jpeg",
            0.82,
        );
    },
);

test("keeps WebP when the browser supports encoding it", async () => {
    encode.mockImplementation((callback) =>
        callback(new Blob(["webp"], { type: "image/webp" })),
    );
    const prepared = await prepareSpacePostImageFromEdit(file);
    expect(prepared.file.name).toBe("IMG_3238.webp");
    expect(prepared.file.type).toBe("image/webp");
    expect(prepared).toMatchObject({
        width: 1440,
        height: 1920,
        thumbHash: "hash",
    });
    expect(encode).toHaveBeenCalledOnce();
});

test("reports a failed JPEG encoding instead of using the PNG", async () => {
    encode.mockImplementation((callback, type) =>
        callback(type == "image/webp" ? oversizedPNG : null),
    );
    await expect(prepareSpacePostImageFromEdit(file)).rejects.toThrow(
        "Could not encode image",
    );
});

test("still enforces the upload size limit for JPEG output", async () => {
    encode.mockImplementation((callback, type) =>
        callback(
            new Blob([oversizedPNG], {
                type: type == "image/webp" ? "image/png" : "image/jpeg",
            }),
        ),
    );
    await expect(prepareSpacePostImageFromEdit(file)).rejects.toThrow(
        "This photo is too large. Try a smaller one.",
    );
});
