import assert from "node:assert/strict";
import test from "node:test";

for (const name of ["files", "thumbnails", "public-albums"]) {
    const { default: worker } = await import(`./${name}/src/index.ts`);

    for (const secret of ["worker-secret", undefined, ""]) {
        test(`${name}: API secret ${JSON.stringify(secret)}`, async (t) => {
            const requests = [];
            t.mock.method(globalThis, "fetch", async (input, init) => {
                const request = new Request(input, init);
                requests.push(request);
                return requests.length === 1
                    ? Response.json({ url: "https://storage.example/file" })
                    : new Response("file contents");
            });
            const request = new Request(
                "https://worker.example/download?fileID=42",
                {
                    headers: {
                        "X-Ente-Worker-Secret": "client-spoof",
                        "X-Auth-Token": "user-token",
                        "X-Auth-Access-Token": "link-token",
                        "CF-Connecting-IP": "192.0.2.1",
                        Range: "bytes=0-9",
                    },
                    redirect: "follow",
                },
            );
            const response = await worker.fetch(request, {
                MUSEUM_WORKER_SECRET: secret,
            });
            assert.equal(response.status, 200);
            assert.equal(await response.text(), "file contents");
            assert.equal(response.headers.get("X-Ente-Worker-Secret"), null);
            assert.equal(requests.length, 2);
            const [api, blob] = requests;
            assert.equal(new URL(api.url).origin, "https://api.ente.com");
            assert.equal(api.redirect, "manual");
            assert.equal(api.headers.get("X-Ente-Worker-Secret"), secret ?? "");
            assert.equal(api.headers.get("X-Auth-Token"), "user-token");
            assert.equal(api.headers.get("X-Auth-Access-Token"), "link-token");
            assert.equal(api.headers.get("X-Forwarded-For"), "192.0.2.1");
            assert.equal(blob.headers.get("X-Ente-Worker-Secret"), null);
            assert.equal(blob.headers.get("X-Auth-Token"), null);
            assert.equal(
                blob.headers.get("Range"),
                name === "files" ? "bytes=0-9" : null,
            );
        });
    }

    test(`${name}: API redirects do not forward secrets`, async (t) => {
        const fetch = t.mock.method(
            globalThis,
            "fetch",
            async (input, init) => {
                assert.equal(new Request(input, init).redirect, "manual");
                return Response.redirect("https://other.example/", 302);
            },
        );
        const response = await worker.fetch(
            new Request("https://worker.example/download?fileID=42"),
            { MUSEUM_WORKER_SECRET: "worker-secret" },
        );
        assert.equal(response.status, 302);
        assert.equal(fetch.mock.callCount(), 1);
        assert.equal(response.headers.get("X-Ente-Worker-Secret"), null);
    });
}
