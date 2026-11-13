import { afterEach, expect, expectTypeOf, test, vi } from "vitest";
import { PasteClient } from "../pkg/ente_paste_wasm.js";

afterEach(() => vi.unstubAllGlobals());

test.each([false, true])(
    "returns cloneable paste results (password required: %s)",
    async (passwordRequired) => {
        let payload: string | undefined;
        vi.stubGlobal("fetch", async (request: Request) => {
            let response: Response;
            switch (new URL(request.url).pathname) {
                case "/paste/create":
                    payload = await request.text();
                    response = Response.json({ accessToken: "ABC123" });
                    break;
                case "/paste/guard":
                    response = Response.json({});
                    break;
                case "/paste/consume":
                    response = new Response(payload);
                    break;
                default:
                    throw new Error(`Unexpected request: ${request.url}`);
            }
            Object.defineProperty(response, "url", { value: request.url });
            return response;
        });

        const client = new PasteClient("http://localhost");
        try {
            const text = "A paste with Unicode: 🦋";
            const password = "correct horse";
            const created = await client.create(
                "http://localhost",
                text,
                passwordRequired ? password : undefined,
            );
            expect(created.url).toMatch(/^http:\/\/localhost\/ABC123#/);
            expect(created).toStrictEqual({
                url: created.url,
                passwordRequired,
            });
            expect(structuredClone(created)).toStrictEqual(created);

            const opened = await client.open(created.url);
            expect(structuredClone(opened)).toStrictEqual(opened);
            expect(opened.passwordRequired).toBe(passwordRequired);
            if (opened.passwordRequired) {
                expect(opened).toStrictEqual({ passwordRequired: true });
                await expect(client.submitPassword(password)).resolves.toBe(
                    text,
                );
            } else {
                expectTypeOf(opened.text).toEqualTypeOf<string>();
                expect(opened).toStrictEqual({ passwordRequired: false, text });
            }
        } finally {
            client.free();
        }
    },
);

test("returns tagged paste errors", async () => {
    const client = new PasteClient("http://localhost");
    await expect(client.create("http://localhost", "")).rejects.toMatchObject({
        name: "empty_text",
    });
    await expect(client.open("http://localhost/ABC123")).rejects.toMatchObject({
        name: "missing_key",
    });
    client.free();
});
