import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { logSpaceImageReadCheck } from "../src/utils/post-image-diagnostics";

const mocks = vi.hoisted(() => ({
    logToDisk: vi.fn<(line: string) => void>(),
}));
vi.mock("ente-base/log-web", () => ({ logToDisk: mocks.logToDisk }));

const context = {
    requestId: "12345678-1234-1234-1234-123456789abc",
    attempt: 1,
    item: 2,
};
const decodeError = new Error("Could not decode image");
const entries = () =>
    mocks.logToDisk.mock.calls.map(
        ([line]: [string]) =>
            JSON.parse(line.slice(line.indexOf("{"))) as unknown,
    );

beforeEach(() => mocks.logToDisk.mockReset());
afterEach(() => vi.restoreAllMocks());

test("checks a failed image once and logs progress while the read is pending", async () => {
    const file = new File(["PRIVATE_CONTENT"], "PRIVATE_FILENAME.jpg");
    const pendingRead = Promise.withResolvers<ArrayBuffer>();
    const read = vi
        .spyOn(Blob.prototype, "arrayBuffer")
        .mockReturnValue(pendingRead.promise);
    vi.spyOn(performance, "now").mockReturnValue(100);

    const check = logSpaceImageReadCheck(file, decodeError, context);
    await logSpaceImageReadCheck(file, decodeError, { ...context, attempt: 2 });

    expect(read).toHaveBeenCalledOnce();
    expect(entries()).toEqual([{ ...context, outcome: "started" }]);
    vi.spyOn(performance, "now").mockReturnValue(150);
    pendingRead.resolve(new TextEncoder().encode("PRIVATE_CONTENT").buffer);
    await check;

    expect(entries()).toEqual([
        { ...context, outcome: "started" },
        { ...context, outcome: "prefix-readable", elapsedMs: 50 },
    ]);
});

test.each([1024, 128 * 1024])(
    "reads at most 64 KB from a %i-byte file",
    async (size) => {
        const file = new File([new Uint8Array(size)], "photo.jpg");
        const read = vi.spyOn(Blob.prototype, "arrayBuffer");

        await logSpaceImageReadCheck(file, decodeError, context);

        expect(read).toHaveBeenCalledOnce();
        await expect(read.mock.results[0]!.value).resolves.toHaveProperty(
            "byteLength",
            Math.min(size, 64 * 1024),
        );
    },
);

test.each(["NotReadableError", "PRIVATE_NAME"])(
    "logs a safe read error category for %s without private data",
    async (name) => {
        const file = new File(["PRIVATE_CONTENT"], "PRIVATE_FILENAME.jpg", {
            type: "private/type",
            lastModified: 1700123456789,
        });
        const error = new DOMException("PRIVATE_PATH", name);
        error.stack = "PRIVATE_STACK";
        vi.spyOn(Blob.prototype, "arrayBuffer").mockRejectedValue(error);
        vi.spyOn(performance, "now").mockReturnValue(100);

        await logSpaceImageReadCheck(file, decodeError, context);

        expect(entries()).toEqual([
            { ...context, outcome: "started" },
            {
                ...context,
                outcome: "failed",
                error: name == "NotReadableError" ? name : "Unknown",
                elapsedMs: 0,
            },
        ]);
        expect(JSON.stringify(entries())).not.toMatch(/PRIVATE|1700123456789/i);
    },
);

test.each([new Error("Could not encode image"), "PRIVATE_ERROR"])(
    "does not read or log for other preparation failures: %s",
    async (error) => {
        const file = new File(["photo"], "photo.jpg");
        const read = vi.spyOn(Blob.prototype, "arrayBuffer");

        await logSpaceImageReadCheck(file, error, context);

        expect(read).not.toHaveBeenCalled();
        expect(mocks.logToDisk).not.toHaveBeenCalled();
    },
);
