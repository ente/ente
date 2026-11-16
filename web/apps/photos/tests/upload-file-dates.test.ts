import { fileSystemCreationTimeOrModified } from "ente-gallery/services/upload/date";
import { afterEach, describe, expect, test, vi } from "vitest";

const createdMs = Date.parse("2024-06-29T09:50:00Z");
const modifiedMs = Date.parse("2026-11-12T00:06:00Z");
const modificationTime = modifiedMs * 1000;

afterEach(() => vi.unstubAllGlobals());

describe("desktop filesystem date fallback", () => {
    test.each([
        ["preserved creation date", createdMs, createdMs * 1000],
        ["newer copy creation date", modifiedMs + 1000, modificationTime],
        ["equal dates", modifiedMs, modificationTime],
        ["unavailable birthtime", 0, modificationTime],
        ["negative birthtime", -1, modificationTime],
        ["invalid birthtime", NaN, modificationTime],
        ["infinite birthtime", Infinity, modificationTime],
    ])("uses the earlier valid date for %s", async (_, birthtime, expected) => {
        const statBirthtime = vi.fn().mockResolvedValue(birthtime);
        vi.stubGlobal("electron", { fs: { statBirthtime } });

        expect(
            await fileSystemCreationTimeOrModified(
                "/photos/sample.jpg",
                modificationTime,
            ),
        ).toBe(expected);
        expect(statBirthtime).toHaveBeenCalledWith("/photos/sample.jpg");
    });

    test("reads the source path of a dragged file", async () => {
        const statBirthtime = vi.fn().mockResolvedValue(createdMs);
        vi.stubGlobal("electron", { fs: { statBirthtime } });
        const item = {
            file: new File(["sample"], "sample.jpg"),
            path: "/photos/sample.jpg",
        };

        expect(
            await fileSystemCreationTimeOrModified(item, modificationTime),
        ).toBe(createdMs * 1000);
        expect(statBirthtime).toHaveBeenCalledWith(item.path);
    });

    test("retains Modified if native stat fails", async () => {
        const statBirthtime = vi.fn().mockRejectedValue(new Error("ENOENT"));
        vi.stubGlobal("electron", {
            fs: { statBirthtime },
            logToDisk: vi.fn(),
        });

        expect(
            await fileSystemCreationTimeOrModified(
                "/photos/sample.jpg",
                modificationTime,
            ),
        ).toBe(modificationTime);
    });

    test.each([
        [new File(["sample"], "sample.jpg")],
        [["/photos/archive.zip", "sample.jpg"] as [string, string]],
    ])(
        "does not read birthtime for browser files or ZIP entries: %s",
        async (item) => {
            const statBirthtime = vi.fn();
            vi.stubGlobal("electron", { fs: { statBirthtime } });

            expect(
                await fileSystemCreationTimeOrModified(item, modificationTime),
            ).toBe(modificationTime);
            expect(statBirthtime).not.toHaveBeenCalled();
        },
    );

    test.each([undefined, { fs: {} }])(
        "retains Modified without native capability: %s",
        async (electron) => {
            vi.stubGlobal("electron", electron);

            expect(
                await fileSystemCreationTimeOrModified(
                    "/photos/sample.jpg",
                    modificationTime,
                ),
            ).toBe(modificationTime);
        },
    );
});
