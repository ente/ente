import { afterEach, beforeEach, expect, test, vi } from "vitest";

const mocks = vi.hoisted(() => ({
    load: vi.fn(),
    mount: vi.fn(),
    exec: vi.fn(),
    terminate: vi.fn(),
    closeBitmap: vi.fn(),
    rejectPending: undefined as ((error: Error) => void) | undefined,
    packetTimes: [0],
}));

vi.mock("ente-base/log-web", () => ({ logToDisk: vi.fn() }));
vi.mock("@ffmpeg/ffmpeg", () => ({
    FFFSType: { WORKERFS: "WORKERFS" },
    FFmpeg: class {
        load = mocks.load;
        createDir = vi.fn();
        mount = mocks.mount;
        exec = mocks.exec;
        ffprobe = vi.fn(() => Promise.resolve(0));
        readFile = vi.fn((path: string) =>
            Promise.resolve(
                path.endsWith("json")
                    ? JSON.stringify({
                          packets: mocks.packetTimes.map((pts_time) => ({
                              pts_time,
                          })),
                      })
                    : new Uint8Array([1, 2, 3]),
            ),
        );
        deleteFile = vi.fn();
        terminate = () => {
            mocks.terminate();
            mocks.rejectPending?.(new Error("Worker terminated"));
        };
    },
}));

beforeEach(() => {
    vi.clearAllMocks();
    mocks.rejectPending = undefined;
    mocks.packetTimes = [0];
    mocks.load.mockResolvedValue(true);
    mocks.exec.mockResolvedValue(0);
    vi.stubGlobal("document", {
        createElement: () => ({
            width: 0,
            height: 0,
            getContext: () => ({ drawImage: vi.fn() }),
        }),
    });
    vi.stubGlobal(
        "createImageBitmap",
        vi.fn(() =>
            Promise.resolve({
                width: 90,
                height: 160,
                close: mocks.closeBitmap,
            }),
        ),
    );
});
afterEach(() => vi.unstubAllGlobals());

const file = new File(["source"], "private.mov");
const edit = { start: 1.125, end: 9.875, muted: false, coverTime: 1.4 };

test("software covers use one worker for a batch and release bitmaps and the worker", async () => {
    const { extractSoftwareVideoFrames } =
        await import("../src/utils/video-encoding/software");
    const result = await extractSoftwareVideoFrames(
        file,
        [0, 1],
        160,
        true,
        new AbortController().signal,
    );
    expect(result).toMatchObject([
        { width: 90, height: 160 },
        { width: 90, height: 160 },
    ]);
    expect(mocks.load).toHaveBeenCalledOnce();
    const mount = mocks.mount.mock.calls[0]![1] as { files: File[] };
    expect(mount.files[0]!.name).toBe("video");
    expect(mocks.closeBitmap).toHaveBeenCalledTimes(2);
    expect(mocks.terminate).toHaveBeenCalledOnce();
    const args = mocks.exec.mock.calls[0]![0] as string[];
    expect(args.join(" ")).toContain("tonemap=tonemap=hable");
});

test.each([false, true])(
    "software export preserves trimming, metadata removal, and mute=%s",
    async (muted) => {
        const { transcodeSoftwareVideo } =
            await import("../src/utils/video-encoding/software");
        await expect(
            transcodeSoftwareVideo(
                file,
                { ...edit, muted },
                false,
                new AbortController().signal,
            ),
        ).resolves.toEqual(new Uint8Array([1, 2, 3]));
        const args = mocks.exec.mock.calls[0]![0] as string[];
        expect(args.slice(0, 8)).toEqual([
            "-seek_timestamp",
            "1",
            "-ss",
            "1.125",
            "-i",
            "/input/video",
            "-t",
            "8.75",
        ]);
        expect(args.join(" ")).toContain(
            "-map_metadata -1 -map_metadata:s -1 -map_chapters -1",
        );
        expect(args.includes("-an")).toBe(muted);
        expect(args.includes("aac")).toBe(!muted);
        expect(mocks.terminate).toHaveBeenCalledOnce();
    },
);

test("canceling software encoding terminates the worker and permits another export", async () => {
    mocks.exec.mockImplementationOnce(
        () =>
            new Promise((_, reject) => {
                mocks.rejectPending = reject;
            }),
    );
    const { transcodeSoftwareVideo } =
        await import("../src/utils/video-encoding/software");
    const controller = new AbortController();
    const pending = transcodeSoftwareVideo(
        file,
        edit,
        false,
        controller.signal,
    );
    const canceled = expect(pending).rejects.toMatchObject({
        name: "AbortError",
    });
    await vi.waitFor(() => expect(mocks.exec).toHaveBeenCalledOnce());
    controller.abort();
    await canceled;
    expect(mocks.terminate).toHaveBeenCalled();
    await expect(
        transcodeSoftwareVideo(file, edit, false, new AbortController().signal),
    ).resolves.toBeDefined();
});

test("a canceled request does not load FFmpeg, and a failed load releases the worker", async () => {
    const { transcodeSoftwareVideo } =
        await import("../src/utils/video-encoding/software");
    await expect(
        transcodeSoftwareVideo(file, edit, false, AbortSignal.abort()),
    ).rejects.toMatchObject({ name: "AbortError" });
    expect(mocks.load).not.toHaveBeenCalled();
    mocks.load.mockRejectedValueOnce(new Error("Unavailable"));
    await expect(
        transcodeSoftwareVideo(file, edit, false, new AbortController().signal),
    ).rejects.toThrow("Unavailable");
    expect(mocks.terminate).toHaveBeenCalledOnce();
    expect(mocks.mount).not.toHaveBeenCalled();
});

test("software cover seeking uses absolute packet timestamps for offset videos", async () => {
    mocks.packetTimes = [5, 6, 7];
    const { extractSoftwareVideoFrames } =
        await import("../src/utils/video-encoding/software");
    await extractSoftwareVideoFrames(
        file,
        [6],
        160,
        false,
        new AbortController().signal,
    );
    const args = mocks.exec.mock.calls[0]![0] as string[];
    expect(args.slice(0, 6)).toEqual([
        "-seek_timestamp",
        "1",
        "-ss",
        "5.999999",
        "-i",
        "/input/video",
    ]);
});
