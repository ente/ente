import { HTTPError } from "ente-base/http";
import { describe, expect, test, vi } from "vitest";
import { AlbumImportBlockedError, albumImportIssue } from "./import-error";

const httpError = (
    status: number,
    code?: string,
    retryAfter?: string,
    path = "/public-collection/info",
) => {
    const res = new Response(JSON.stringify({ code }), {
        status,
        headers: retryAfter ? { "Retry-After": retryAfter } : undefined,
    });
    Object.defineProperty(res, "url", { value: `https://api.ente.com${path}` });
    return new HTTPError(res);
};

describe("album import recovery", () => {
    test.each([
        [403, "LINK_DEVICE_LIMIT_EXCEEDED", true],
        [410, "LINK_EXPIRED", true],
        [410, "LINK_UNAVAILABLE", true],
        [410, "LINK_DISABLED", false],
        [410, "UNKNOWN", false],
        [401, "UNAUTHORIZED", false],
    ] as const)(
        "chooses recovery for %s %s",
        async (status, code, canRetry) => {
            await expect(
                albumImportIssue(httpError(status, code)),
            ).resolves.toMatchObject({ canRetry });
        },
    );

    test("allows authentication to restart if access changes while listing photos", async () => {
        await expect(
            albumImportIssue(
                httpError(401, undefined, undefined, "/public-collection/diff"),
            ),
        ).resolves.toMatchObject({ canRetry: true });
    });

    test("preserves the explanation for a blocked import", async () => {
        await expect(
            albumImportIssue(
                new AlbumImportBlockedError("Cannot import this album"),
            ),
        ).resolves.toEqual({
            message: "Cannot import this album",
            canRetry: false,
        });
    });

    test("temporary errors retain retry", async () => {
        await expect(
            albumImportIssue(new TypeError("Failed to fetch")),
        ).resolves.toMatchObject({ canRetry: true });
        await expect(albumImportIssue(httpError(503))).resolves.toMatchObject({
            canRetry: true,
        });
    });

    test("rate limits respect Retry-After and use a short cooldown without it", async () => {
        const now = Date.parse("2026-11-20T08:00:00Z");
        const clock = vi.spyOn(Date, "now").mockReturnValue(now);
        try {
            for (const [header, delay] of [
                ["45", 45000],
                ["Fri, 20 Nov 2026 08:01:00 GMT", 60000],
                [undefined, 30000],
                ["invalid", 30000],
            ] as const) {
                await expect(
                    albumImportIssue(httpError(429, undefined, header)),
                ).resolves.toMatchObject({
                    canRetry: true,
                    retryAt: now + delay,
                });
            }
        } finally {
            clock.mockRestore();
        }
    });
});
