import { loadLegacyKitParser, openKitRecovery } from "ente-legacy-wasm";
import { afterEach, expect, test, vi } from "vitest";

afterEach(() => vi.unstubAllGlobals());

const kitID = "1d42d2b4-546d-4127-8d36-278ff3390e2e";
const shareTexts = [
    "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA=",
    "QENGRUxPSklYW15dVFdSUXBzdnV8f3p5aGtubWRnYmE=",
].map((s, index) =>
    JSON.stringify({
        pv: 1,
        kv: 1,
        k: kitID,
        i: index + 1,
        s,
        c: "aVJmKklH18A=",
        n: `Test sheet ${index + 1}`,
    }),
);

test.each([
    ["session", 410, "SESSION_EXPIRED", "legacy_kit_session_expired"],
    ["info", 410, "SESSION_EXPIRED", "legacy_kit_session_expired"],
    ["session", 404, "NOT_FOUND", "Error"],
    ["session", 410, "OTHER_ERROR", "Error"],
])("recovery %s handles HTTP %s %s", async (endpoint, status, code, name) => {
    vi.stubGlobal("fetch", (request: Request) => {
        const path = new URL(request.url).pathname;
        let response: Response;
        if (path === "/legacy-kits/recovery/challenge") {
            response = Response.json({
                encryptedChallenge:
                    "BnDrxc6stvlxl4sP81ltwILDBHlPGdxm0wt+4Mhls3LD6OARc4T22S3JgBxFC9GUoi9VaUQkBZqvQD93FFc=",
            });
        } else if (path === "/legacy-kits/recovery/open") {
            response = Response.json({
                session: {
                    id: "test-session",
                    kitID,
                    status: "READY",
                    waitTill: 0,
                    createdAt: 1,
                },
                sessionToken: "test-token",
            });
        } else {
            expect(path).toBe(`/legacy-kits/recovery/${endpoint}`);
            response = Response.json({ code }, { status });
        }
        Object.defineProperty(response, "url", { value: request.url });
        return Promise.resolve(response);
    });
    const parser = await loadLegacyKitParser();
    const handle = await openKitRecovery({
        baseUrl: "http://localhost",
        shares: shareTexts.map(parser.parseLegacyKitShare),
    });
    try {
        const operation =
            endpoint === "session"
                ? handle.refreshSession()
                : handle.changePassword("unused-test-password");
        await expect(operation).rejects.toMatchObject({ name });
    } finally {
        handle.free();
    }
});
