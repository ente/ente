import { gunzipWithLimit, gzip } from "ente-new/photos/utils/gzip";
import { describe, expect, test } from "vitest";

describe("gunzipWithLimit", () => {
    test("decompresses data within the output limit", async () => {
        const value = "memory metadata";
        const compressed = await gzip(value);

        await expect(gunzipWithLimit(compressed, value.length)).resolves.toBe(
            value,
        );
    });

    test("rejects data that expands beyond the output limit", async () => {
        const compressed = await gzip("a".repeat(64 * 1024));

        await expect(gunzipWithLimit(compressed, 1024)).rejects.toThrow(
            "Decompressed data exceeds the allowed size",
        );
    });
});
