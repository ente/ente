import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";
import worker from "./src/index.ts";

const feedback = {
    message: "Expected export to resume.\nIt started again.",
    version: "0.4.3",
    os: "linux",
};

const database = (t) => {
    const db = new DatabaseSync(":memory:");
    t.after(() => db.close());
    db.exec(
        readFileSync(
            new URL("./migrations/0001_feedback.sql", import.meta.url),
            "utf8",
        ),
    );
    const env = {
        DB: {
            prepare(sql) {
                return {
                    bind: (...values) => ({
                        run: async () => db.prepare(sql).run(...values),
                    }),
                };
            },
        },
        SUBMISSIONS: { limit: async () => ({ success: true }) },
    };
    return { db, env };
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

test("stores feedback before acknowledging the submission", async (t) => {
    const { db, env } = database(t);
    let complete;
    let submitted;
    const posted = new Promise((resolve) => {
        complete = resolve;
    });
    const started = new Promise((resolve) => {
        submitted = resolve;
    });
    const prepare = env.DB.prepare;
    t.mock.method(env.DB, "prepare", (sql) => ({
        bind(...values) {
            const statement = prepare(sql).bind(...values);
            return {
                async run() {
                    submitted();
                    await posted;
                    return statement.run();
                },
            };
        },
    }));
    const message = "Export couldn't resume.\r\n\t'); DROP TABLE feedback; --";
    const before = Math.floor(Date.now() / 1_000);
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
    assert.equal(finished, false);
    complete();
    const response = await pending;
    assert.equal(response.status, 201);
    const { id } = await response.json();
    assert.match(id, /^[0-9a-f-]{36}$/);
    const rows = db.prepare("SELECT * FROM feedback").all();
    assert.equal(rows.length, 1);
    const { created_at, ...row } = rows[0];
    assert.deepEqual(row, { id, ...feedback, message });
    const timestamp = Date.parse(`${created_at}Z`) / 1_000;
    assert.ok(timestamp >= before && timestamp <= Date.now() / 1_000);
});

test("counts Unicode characters", async (t) => {
    const { db, env } = database(t);
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
    const rows = db.prepare("SELECT message FROM feedback").all();
    assert.equal(rows.length, 1);
    assert.equal(rows[0].message, "🔐".repeat(2_000));
});

test("requires a JSON content type before storing feedback", async (t) => {
    const { db, env } = database(t);
    for (const contentType of [
        "",
        "text/plain; charset=UTF-8",
        "application/x-www-form-urlencoded",
        "multipart/form-data; boundary=test",
        "application/jsonp",
    ]) {
        const submission = request(feedback);
        if (contentType) submission.headers.set("Content-Type", contentType);
        else submission.headers.delete("Content-Type");
        assert.equal((await worker.fetch(submission, env)).status, 415);
    }
    assert.equal(
        db.prepare("SELECT COUNT(*) AS count FROM feedback").get().count,
        0,
    );
    const submission = request(feedback);
    submission.headers.set("Content-Type", "Application/JSON ; charset=utf-8");
    assert.equal((await worker.fetch(submission, env)).status, 201);
    assert.equal(
        db.prepare("SELECT COUNT(*) AS count FROM feedback").get().count,
        1,
    );
});

test("rejects invalid and oversized submissions before writing", async (t) => {
    const { env } = database(t);
    const prepare = t.mock.method(env.DB, "prepare", () =>
        assert.fail("Unexpected database write"),
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
    assert.equal(prepare.mock.callCount(), 0);
});

test("a rate-limited request cannot store feedback", async (t) => {
    const { env } = database(t);
    const prepare = t.mock.method(env.DB, "prepare", () =>
        assert.fail("Unexpected database write"),
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
    assert.equal(prepare.mock.callCount(), 0);
});

test("database failures do not return a receipt or retry", async (t) => {
    const { db, env } = database(t);
    db.exec("DROP TABLE feedback");
    const log = t.mock.method(console, "error", () => {});
    const prepare = t.mock.method(env.DB, "prepare");
    const response = await worker.fetch(request(feedback), env);
    assert.equal(response.status, 500);
    assert.deepEqual(await response.json(), {
        error: "Could not confirm feedback submission",
    });
    assert.equal(prepare.mock.callCount(), 1);
    assert.deepEqual(
        log.mock.calls.map(({ arguments: args }) => args),
        [["Could not confirm feedback submission"]],
    );
});
