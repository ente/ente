import { earliestFileSystemTime } from "ente-gallery/services/upload/date";
import { afterEach, describe, expect, test, vi } from "vitest";

const createdMs = Date.parse("2024-06-29T09:50:00Z");
const modifiedMs = Date.parse("2026-11-12T00:06:00Z");
const modificationTime = modifiedMs * 1000;

const stubStatBirthtime = (statBirthtime: () => Promise<number>) => {
    const stub = vi.fn(statBirthtime);
    vi.stubGlobal("electron", {
        fs: { statBirthtime: stub },
        logToDisk: vi.fn(),
    });
    return stub;
};

afterEach(() => vi.unstubAllGlobals());

describe("earliestFileSystemTime", () => {
    test.each([
        ["an earlier Created", createdMs, createdMs * 1000],
        ["a later Created", modifiedMs + 1000, modificationTime],
        ["an unavailable Created", 0, modificationTime],
    ])("picks the date for %s", async (_, birthtimeMs, expected) => {
        const stub = stubStatBirthtime(() => Promise.resolve(birthtimeMs));

        expect(
            await earliestFileSystemTime(
                "/photos/sample.jpg",
                modificationTime,
            ),
        ).toBe(expected);
        expect(stub).toHaveBeenCalledWith("/photos/sample.jpg");
    });

    test("reads the path of a dragged file", async () => {
        const stub = stubStatBirthtime(() => Promise.resolve(createdMs));
        const item = {
            file: new File(["sample"], "sample.jpg"),
            path: "/photos/sample.jpg",
        };

        expect(await earliestFileSystemTime(item, modificationTime)).toBe(
            createdMs * 1000,
        );
        expect(stub).toHaveBeenCalledWith(item.path);
    });

    test("keeps Modified when the path cannot be read", async () => {
        stubStatBirthtime(() => Promise.reject(new Error("ENOENT")));

        expect(await earliestFileSystemTime("", modificationTime)).toBe(
            modificationTime,
        );
    });

    test.each([
        [new File(["sample"], "sample.jpg")],
        [["/photos/archive.zip", "sample.jpg"] as [string, string]],
    ])("skips browser files and ZIP entries: %s", async (item) => {
        const stub = stubStatBirthtime(() => Promise.resolve(createdMs));

        expect(await earliestFileSystemTime(item, modificationTime)).toBe(
            modificationTime,
        );
        expect(stub).not.toHaveBeenCalled();
    });
});
