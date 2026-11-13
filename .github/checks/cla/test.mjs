import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { join } from "node:path";
import test from "node:test";

const source = execFileSync(
    "ruby",
    [
        "-ryaml",
        "-e",
        'puts YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true).fetch("jobs").fetch("cla").fetch("steps").first.fetch("with").fetch("script")',
        join(import.meta.dirname, "../../workflows/cla.yml"),
    ],
    { encoding: "utf8" },
);
const evaluate = new Function(
    "github",
    "context",
    `return (async () => {${source}})()`,
);
const pr = {
    number: 42,
    state: "open",
    user: { id: 24503581 },
    base: { ref: "main", sha: "base" },
    head: { sha: "head", repo: { full_name: "contributor/ente" } },
};
const commit = {
    author: { id: 24503581 },
    committer: { id: 24503581 },
    commit: { message: "Update photos" },
};
const upstream = (state) => ({
    context: "license/cla",
    state,
    description: "CLA Assistant result",
    target_url: "https://cla-assistant.io/ente/ente?pullRequest=42",
});

async function run({
    eventName = "pull_request_target",
    payload = { pull_request: pr },
    pull = pr,
    peers = [pr],
    commits = [commit],
    total = commits.length,
    statuses = [],
    arriving,
} = {}) {
    const writes = [];
    const reads = [];
    let canonical = statuses;
    const github = {
        rest: {
            pulls: {
                get: async (args) => {
                    reads.push(["pull", args]);
                    return { data: pull };
                },
                list: async () => {
                    reads.push(["peers"]);
                    return { data: peers };
                },
            },
            repos: {
                compareCommitsWithBasehead: async (args) => {
                    reads.push(["compare", args]);
                    if (arriving) canonical = [[arriving]];
                    return { data: { commits, total_commits: total } };
                },
                getCombinedStatusForRef: async (args) => {
                    reads.push(["statuses", args]);
                    return {
                        data: { statuses: canonical[args.page - 1] ?? [] },
                    };
                },
                createCommitStatus: async (args) => {
                    writes.push(args);
                },
            },
        },
        async paginate(method, args, map) {
            if (!map) return (await method(args)).data;
            const result = [];
            for (let page = 1; ; page++) {
                const items = map(await method({ ...args, page }));
                if (!items.length) return result;
                result.push(...items);
            }
        },
    };
    await evaluate(github, {
        repo: { owner: "ente", repo: "ente" },
        eventName,
        payload,
    });
    return { writes, reads };
}

test("canonical results override cached coverage and are read across pages", async () => {
    for (const state of ["success", "pending", "failure", "error"]) {
        const { writes, reads } = await run({
            statuses: [
                [{ context: "CLA", state: "success" }],
                [upstream(state)],
            ],
        });
        assert.deepEqual(writes, [
            {
                owner: "ente",
                repo: "ente",
                sha: "head",
                ...upstream(state),
                context: "CLA",
            },
        ]);
        assert.equal(
            reads.some(([name]) => name === "compare"),
            false,
        );
    }
});

test("missing canonical results can use complete cached coverage at fixed commit SHAs", async () => {
    const { writes, reads } = await run({
        commits: [commit, { ...commit, committer: { id: 19864447 } }],
    });
    assert.equal(writes[0].state, "success");
    assert.deepEqual(reads.find(([name]) => name === "compare")[1], {
        owner: "ente",
        repo: "ente",
        basehead: "base...head",
    });
});

test("uncertain contributor coverage waits for CLA Assistant", async () => {
    for (const options of [
        { pull: { ...pr, user: { id: 1 } } },
        { commits: [{ ...commit, author: null }] },
        { commits: [{ ...commit, author: { id: 1 } }] },
        {
            commits: [
                {
                    ...commit,
                    commit: {
                        message:
                            "Fix\n\nCo-authored-by: Other <other@example.com>",
                    },
                },
            ],
        },
        { commits: [] },
        { total: 2 },
        { peers: [pr, { ...pr, number: 43 }] },
        { peers: [{ ...pr, number: 43 }] },
    ]) {
        const { writes } = await run(options);
        assert.equal(writes[0].state, "pending");
    }
});

test("a canonical result arriving during the cache lookup wins", async () => {
    const { writes } = await run({ arriving: upstream("pending") });
    assert.equal(writes[0].state, "pending");
    assert.equal(writes[0].description, upstream("pending").description);
});

test("status events replace earlier cache approval with the latest canonical result", async () => {
    const { writes, reads } = await run({
        eventName: "status",
        payload: { sha: "fork-head", state: "success" },
        statuses: [[{ context: "CLA", state: "success" }, upstream("pending")]],
    });
    assert.equal(writes[0].sha, "fork-head");
    assert.equal(writes[0].state, "pending");
    assert.ok(reads.every(([name]) => name === "statuses"));
});

test("manual dispatch evaluates the requested PR's existing head", async () => {
    const { writes, reads } = await run({
        eventName: "workflow_dispatch",
        payload: { inputs: { pull_request: "42" } },
    });
    assert.equal(reads[0][1].pull_number, 42);
    assert.equal(writes[0].sha, "head");
    assert.equal(writes[0].state, "success");
});

test("closed and non-main PRs are outside the cache", async () => {
    for (const pull of [
        { ...pr, state: "closed" },
        { ...pr, base: { ref: "release/test", sha: "base" } },
    ]) {
        const { writes } = await run({ pull });
        assert.deepEqual(writes, []);
    }
});
