"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { MARKER, reconcile } = require("./upstream-sync-issue.cjs");

const context = { repo: { owner: "vanton1", repo: "ente" } };

function report(upstreamOnly) {
    return {
        schemaVersion: 1,
        ready: true,
        commits: {
            fork: "a".repeat(40),
            official: "b".repeat(40),
            mergeBase: "c".repeat(40),
            forkOnly: 3,
            upstreamOnly,
        },
    };
}

function issue(number = 42) {
    return {
        number,
        title: "old title",
        body: `${MARKER}\nold report`,
        html_url: `https://github.com/vanton1/ente/issues/${number}`,
    };
}

function mockGitHub(existing = []) {
    const calls = [];
    const response = (number) => ({
        data: {
            number,
            html_url: `https://github.com/vanton1/ente/issues/${number}`,
        },
    });
    return {
        calls,
        github: {
            paginate: async (_method, options) => {
                calls.push(["list", options]);
                return existing;
            },
            rest: {
                issues: {
                    listForRepo: Symbol("listForRepo"),
                    create: async (options) => {
                        calls.push(["create", options]);
                        return response(77);
                    },
                    update: async (options) => {
                        calls.push(["update", options]);
                        return response(options.issue_number);
                    },
                    createComment: async (options) => {
                        calls.push(["comment", options]);
                        return response(options.issue_number);
                    },
                },
            },
        },
    };
}

test("no drift and no marker issue is idempotently unchanged", async () => {
    const mock = mockGitHub();

    const result = await reconcile({ github: mock.github, context, report: report(0) });

    assert.deepEqual(result, { action: "unchanged", number: null, url: null });
    assert.deepEqual(mock.calls.map(([name]) => name), ["list"]);
});

test("drift creates one marker issue with exact evidence", async () => {
    const mock = mockGitHub();

    const result = await reconcile({
        github: mock.github,
        context,
        report: report(5),
        now: new Date("2026-07-20T06:17:00Z"),
    });

    assert.equal(result.action, "created");
    const create = mock.calls.find(([name]) => name === "create")[1];
    assert.match(create.body, new RegExp(MARKER.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
    assert.match(create.body, /Upstream-only commits: 5/);
    assert.match(create.body, new RegExp(`--official-sha ${"b".repeat(40)}`));
});

test("later drift updates the same marker issue", async () => {
    const mock = mockGitHub([issue()]);

    const result = await reconcile({ github: mock.github, context, report: report(7) });

    assert.equal(result.action, "updated");
    assert.equal(result.number, 42);
    assert.equal(mock.calls.filter(([name]) => name === "create").length, 0);
    assert.equal(mock.calls.filter(([name]) => name === "update").length, 1);
});

test("zero drift comments and closes the marker issue", async () => {
    const mock = mockGitHub([issue()]);

    const result = await reconcile({ github: mock.github, context, report: report(0) });

    assert.equal(result.action, "closed");
    assert.deepEqual(mock.calls.map(([name]) => name), ["list", "comment", "update"]);
    const close = mock.calls.find(([name, options]) => name === "update" && options.state === "closed");
    assert(close);
});

test("duplicate marker issues stop without mutation", async () => {
    const mock = mockGitHub([issue(42), issue(43)]);

    await assert.rejects(
        reconcile({ github: mock.github, context, report: report(3) }),
        /refusing an ambiguous update/,
    );
    assert.deepEqual(mock.calls.map(([name]) => name), ["list"]);
});

test("invalid evidence stops before reading or writing issues", async () => {
    const mock = mockGitHub();
    const invalid = report(2);
    invalid.commits.official = "not-a-sha";

    await assert.rejects(
        reconcile({ github: mock.github, context, report: invalid }),
        /invalid commit evidence/,
    );
    assert.deepEqual(mock.calls, []);
});
