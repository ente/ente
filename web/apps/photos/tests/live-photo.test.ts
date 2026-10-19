import { decodeLivePhoto } from "ente-media/live-photo";
import JSZip, { type JSZipObject } from "jszip";
import { afterEach, describe, expect, test, vi } from "vitest";

afterEach(() => vi.restoreAllMocks());

const archive = async (names: string[], compression: "STORE" | "DEFLATE") => {
    const zip = new JSZip();
    for (const name of names) zip.file(name, name, { createFolders: false });
    return new Blob([
        await zip.generateAsync({ type: "arraybuffer", compression }),
    ]);
};

describe("Live Photo decoding", () => {
    test.each(["STORE", "DEFLATE"] as const)(
        "decodes %s components in either order, including extensionless names",
        async (compression) => {
            for (const names of [
                ["image.heic", "video.mov"],
                ["video", "image"],
            ]) {
                const result = await decodeLivePhoto(
                    "holiday.photo.zip",
                    await archive(names, compression),
                );
                const imageName = names.find((name) =>
                    name.startsWith("image"),
                )!;
                const videoName = names.find((name) =>
                    name.startsWith("video"),
                )!;
                expect(result.imageFileName).toBe(
                    imageName.replace("image", "holiday.photo"),
                );
                expect(result.videoFileName).toBe(
                    videoName.replace("video", "holiday.photo"),
                );
                expect(new TextDecoder().decode(result.imageData)).toBe(
                    imageName,
                );
                expect(new TextDecoder().decode(result.videoData)).toBe(
                    videoName,
                );
                expect(result.imageData.buffer).toBeInstanceOf(ArrayBuffer);
                expect(result.videoData.buffer).toBeInstanceOf(ArrayBuffer);
            }
        },
    );

    test.each([
        [["image.jpg", "video.mov", "extra.txt"]],
        [["image.jpg", "image.png"]],
        [["folder/image.jpg", "video.mov"]],
        [["./image.jpg", "video.mov"]],
        [["image.jpg\n", "video.mov"]],
    ])("rejects invalid component sets: %j", async (names) => {
        await expect(
            decodeLivePhoto("photo.zip", await archive(names, "STORE")),
        ).rejects.toThrow();
    });
});

const streamEntry = (name: string, chunks: Uint8Array[], error?: Error) => {
    const listeners: Record<string, (value?: unknown) => void> = {};
    const stream = {
        on(event: string, listener: (value?: unknown) => void) {
            listeners[event] = listener;
            return this;
        },
        pause: vi.fn(),
        resume: vi.fn(() => {
            queueMicrotask(() => {
                for (const chunk of chunks) listeners.data?.(chunk);
                if (error) listeners.error?.(error);
                else listeners.end?.();
            });
            return stream;
        }),
    };
    const entry = {
        name,
        unsafeOriginalName: name,
        dir: false,
        internalStream: vi.fn(() => stream),
    };
    return { entry, stream };
};

const stubArchive = (...entries: ReturnType<typeof streamEntry>[]) => {
    const zip = new JSZip();
    zip.files = Object.fromEntries(
        entries.map(({ entry }) => [
            entry.name,
            entry as unknown as JSZipObject,
        ]),
    );
    vi.spyOn(JSZip, "loadAsync").mockResolvedValue(zip);
};

describe("Live Photo output budgets", () => {
    const chunk = new Uint8Array(64 * 1024);
    const chunks = (count: number) =>
        Array.from({ length: count }, () => chunk);

    test("accepts the exact combined budget", async () => {
        const blob = new Blob(["archive"]);
        const inputAllowance = new Uint8Array(blob.size * 20);
        const image = streamEntry("image.jpg", chunks(128));
        const video = streamEntry("video.mov", [
            ...chunks(128),
            inputAllowance,
        ]);
        stubArchive(image, video);
        const result = await decodeLivePhoto("photo.zip", blob);
        expect(result.imageData.length + result.videoData.length).toBe(
            16 * 1024 * 1024 + inputAllowance.length,
        );
        expect(image.stream.pause).not.toHaveBeenCalled();
        expect(video.stream.pause).not.toHaveBeenCalled();

        const oversizedVideo = streamEntry("video.mov", [
            ...chunks(128),
            inputAllowance,
            new Uint8Array(1),
        ]);
        stubArchive(image, oversizedVideo);
        await expect(decodeLivePhoto("photo.zip", blob)).rejects.toThrow(
            "expands beyond limit",
        );
        expect(oversizedVideo.stream.pause).toHaveBeenCalledOnce();
    });

    test("stops an oversized image without starting the video", async () => {
        const image = streamEntry("image.jpg", chunks(257));
        const video = streamEntry("video.mov", []);
        stubArchive(image, video);
        await expect(decodeLivePhoto("photo.zip", new Blob())).rejects.toThrow(
            "expands beyond limit",
        );
        expect(image.stream.pause).toHaveBeenCalledOnce();
        expect(video.entry.internalStream).not.toHaveBeenCalled();
    });

    test("propagates read failures without starting the next component", async () => {
        const failure = new Error("component read failed");
        const image = streamEntry("image.jpg", [chunk], failure);
        const video = streamEntry("video.mov", []);
        stubArchive(image, video);
        await expect(decodeLivePhoto("photo.zip", new Blob())).rejects.toBe(
            failure,
        );
        expect(image.stream.pause).toHaveBeenCalledOnce();
        expect(video.entry.internalStream).not.toHaveBeenCalled();
    });
});
