import assert from "node:assert/strict";
import test from "node:test";
import worker from "./src/index.ts";

const feedback = {
    message: "Expected export to resume.\nIt started again.",
    version: "0.4.3",
    os: "linux",
};

const env = {
    GITHUB_REPOSITORY: "test/feedback",
    GITHUB_TOKEN: "test-token",
    SUBMISSIONS: { limit: async () => ({ success: true }) },
};

const request = (value) =>
    new Request("https://feedback.test/", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            "CF-Connecting-IP": "192.0.2.1",
        },
        body: JSON.stringify(value),
    });

test("creates a plain-text issue before acknowledging the submission", async (t) => {
    let complete;
    let submitted;
    let issue;
    const posted = new Promise((resolve) => {
        complete = resolve;
    });
    const started = new Promise((resolve) => {
        submitted = resolve;
    });
    const upstream = t.mock.method(globalThis, "fetch", async (url, init) => {
        assert.equal(url, "https://api.github.com/repos/test/feedback/issues");
        assert.equal(init.headers.Authorization, "Bearer test-token");
        issue = JSON.parse(init.body);
        submitted();
        await posted;
        return new Response("{}", { status: 201 });
    });
    const message = "@someone\n```\n<img src=x>\n\n# Heading\r\n\tLast line";
    let finished = false;
    const pending = worker
        .fetch(
            request({ ...feedback, message, token: "must-not-forward" }),
            env,
        )
        .then((response) => {
            finished = true;
            return response;
        });
    await started;
    assert.equal(upstream.mock.callCount(), 1);
    assert.equal(finished, false);
    complete();
    const response = await pending;
    assert.equal(response.status, 201);
    const { id } = await response.json();
    assert.match(id, /^[0-9a-f-]{36}$/);
    assert.ok(issue.body.includes(`Receipt: ${id}`));
    for (const line of issue.body.split("\n"))
        assert.ok(line === "" || line.startsWith("    "));
    assert.ok(issue.body.includes("    ```\n    <img src=x>"));
    assert.ok(!issue.body.includes("must-not-forward"));
    assert.ok(!issue.body.includes("192.0.2.1"));
});

test("counts Unicode characters", async (t) => {
    const upstream = t.mock.method(
        globalThis,
        "fetch",
        async () => new Response(null, { status: 201 }),
    );
    const accepted = await worker.fetch(
        request({ ...feedback, message: "🔐".repeat(2_000) }),
        env,
    );
    assert.equal(accepted.status, 201);
    const rejected = await worker.fetch(
        request({ ...feedback, message: "🔐".repeat(2_001) }),
        env,
    );
    assert.equal(rejected.status, 400);
    assert.equal(upstream.mock.callCount(), 1);
});

test("rejects invalid and oversized submissions before contacting GitHub", async (t) => {
    const upstream = t.mock.method(globalThis, "fetch", () =>
        assert.fail("Unexpected GitHub request"),
    );
    for (const value of [
        null,
        {},
        { ...feedback, message: " \n" },
        { ...feedback, message: "x".repeat(2_001) },
        { ...feedback, version: "version\n# Injected" },
        { ...feedback, message: "clear\u001b[2Jscreen" },
        { ...feedback, message: "\u001b]8;;https://example.test\u0007link" },
        { ...feedback, message: "C1\u009b2Jcontrol" },
        { ...feedback, message: "nul\0byte" },
    ]) {
        assert.equal((await worker.fetch(request(value), env)).status, 400);
    }
    const malformed = request(feedback);
    const malformedBody = new Request(malformed, { body: "{" });
    assert.equal((await worker.fetch(malformedBody, env)).status, 400);
    const oversized = new Request(request(feedback), {
        headers: { "Content-Type": "application/json", "Content-Length": "1" },
        body: new ReadableStream({
            start(controller) {
                controller.enqueue(new Uint8Array(10_000));
                controller.enqueue(new Uint8Array(10_000));
                controller.close();
            },
        }),
        duplex: "half",
    });
    assert.equal((await worker.fetch(oversized, env)).status, 413);
    assert.equal(upstream.mock.callCount(), 0);
});

test("a rate-limited request cannot create an issue", async (t) => {
    const upstream = t.mock.method(globalThis, "fetch", () =>
        assert.fail("Unexpected GitHub request"),
    );
    const response = await worker.fetch(request(feedback), {
        ...env,
        SUBMISSIONS: {
            async limit({ key }) {
                assert.equal(key, "192.0.2.1");
                return { success: false };
            },
        },
    });
    assert.equal(response.status, 429);
    assert.equal(response.headers.get("Retry-After"), "60");
    assert.equal(upstream.mock.callCount(), 0);
});

test("upstream failures do not return a receipt or retry", async (t) => {
    t.mock.method(console, "error", () => {});
    const upstream = t.mock.method(globalThis, "fetch");
    for (const result of [403, 422, 500, new Error("connection lost")]) {
        upstream.mock.mockImplementation(async () => {
            if (result instanceof Error) throw result;
            return new Response("private upstream response", {
                status: result,
            });
        });
        const response = await worker.fetch(request(feedback), env);
        assert.equal(response.status, 502);
        const body = await response.json();
        assert.equal(body.id, undefined);
        assert.ok(!JSON.stringify(body).includes("private upstream response"));
    }
    assert.equal(upstream.mock.callCount(), 4);
});
