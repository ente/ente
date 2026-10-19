import { initiateGenerateHLS } from "ente-gallery/utils/native-stream";
import { afterEach, describe, expect, test, vi } from "vitest";

afterEach(() => vi.unstubAllGlobals());

describe("initiateGenerateHLS", () => {
    test.each([false, true])(
        "passes the preview upload flag (%s) and keeps auth in headers",
        async (previewUploadV2) => {
            const authToken = "session-secret+/=";
            const video = new ReadableStream();
            let requestURL: string | undefined;
            let requestInit: RequestInit | undefined;

            vi.stubGlobal(
                "fetch",
                vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
                    requestURL =
                        typeof input == "string"
                            ? input
                            : input instanceof URL
                              ? input.href
                              : input.url;
                    requestInit = init;
                    return Promise.resolve(
                        new Response(
                            JSON.stringify({
                                playlistToken: "playlist-token",
                                dimensions: { width: 1920, height: 1080 },
                                videoSize: 123,
                                videoObjectID: "object-id",
                            }),
                            { status: 200 },
                        ),
                    );
                }),
            );

            await initiateGenerateHLS(
                undefined as never,
                video,
                42,
                "https://api.example.com/files/data/preview-upload-url",
                authToken,
                previewUploadV2,
            );

            const url = new URL(requestURL!);
            expect(url.searchParams.get("previewUploadV2")).toBe(
                previewUploadV2 ? "true" : null,
            );
            expect(url.searchParams.has("authToken")).toBe(false);
            expect(url.href).not.toContain(authToken);
            expect(new Headers(requestInit?.headers).get("X-Auth-Token")).toBe(
                authToken,
            );
            expect(requestInit?.body).toBe(video);
        },
    );

    test("does not include the auth token or request URL in an HTTP error", async () => {
        const authToken = "session-secret+/=";
        vi.stubGlobal(
            "fetch",
            vi.fn(() => Promise.resolve(new Response("", { status: 500 }))),
        );

        let error: unknown;
        try {
            await initiateGenerateHLS(
                undefined as never,
                new ReadableStream(),
                42,
                "https://api.example.com/files/data/preview-upload-url",
                authToken,
                false,
            );
        } catch (e) {
            error = e;
        }

        expect(error).toBeInstanceOf(Error);
        const message = (error as Error).message;
        expect(message).toBe("Failed to generate HLS: HTTP 500");
        expect(message).not.toContain(authToken);
        expect(message).not.toContain("stream://");
    });
});
