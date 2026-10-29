import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { join } from "node:path";
import test from "node:test";

function workflow(name) {
    const path = join(import.meta.dirname, `../../workflows/${name}.yml`);
    const source = execFileSync(
        "ruby",
        [
            "-ryaml",
            "-e",
            'puts YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true).fetch("jobs").fetch(ARGV.fetch(1)).fetch("steps").first.fetch("with").fetch("script")',
            path,
            name,
        ],
        { encoding: "utf8" },
    );
    return new Function(
        "github",
        "context",
        "core",
        `return (async () => {${source}})()`,
    );
}

const cla = workflow("cla");
const stale = workflow("stale");
const coveredId = 24503581;
const otherId = 1;
const context = {
    repo: { owner: "ente", repo: "ente" },
    serverUrl: "https://github.com",
    runId: 123,
};
const pull = (overrides = {}) => ({
    number: 42,
    state: "open",
    user: { id: coveredId },
    base: { ref: "main" },
    head: { sha: "current", repo: { full_name: "contributor/ente" } },
    created_at: "2020-01-01T00:00:00Z",
    labels: [],
    ...overrides,
});
const authors = (...ids) => ({
    commit: {
        authors: {
            totalCount: ids.length,
            nodes: ids.map((id) => ({
                user: id === null ? null : { databaseId: id },
            })),
        },
    },
});
const commitPage = (
    nodes,
    { next = false, count = nodes.length, ...rest } = {},
) => ({
    repository: {
        pullRequest: {
            headRefOid: "current",
            baseRefOid: "base",
            baseRefName: "main",
            state: "OPEN",
            commits: {
                nodes,
                totalCount: count,
                pageInfo: {
                    hasNextPage: next,
                    endCursor: next ? "next" : null,
                },
            },
            ...rest,
        },
    },
});
const upstream = (state) => ({
    context: "license/cla",
    state,
    description: "CLA Assistant result",
    target_url: "https://cla-assistant.io/ente/ente?pullRequest=42",
});
const required = (state) => ({ context: "CLA required", state });

function client({
    pulls = [[pull()]],
    statuses = [[]],
    commits = [commitPage([authors(coveredId)])],
} = {}) {
    const calls = [];
    const writes = [];
    const endpoint = (name, pages) => {
        const request = async (args) => {
            calls.push([name, args]);
            return { data: pages[(args.page ?? 1) - 1] };
        };
        request.pages = pages.length;
        return request;
    };
    const write = (name) => async (args) => writes.push([name, args]);
    let page = 0;
    return {
        calls,
        writes,
        async run(workflow, payload = { pull_request: pulls[0][0] }) {
            await workflow(this, { ...context, payload }, { info() {} });
            return writes;
        },
        async paginate(request, args, map = ({ data }) => data) {
            const results = [];
            for (let page = 1; page <= request.pages; page++) {
                results.push(...[map(await request({ ...args, page }))].flat());
            }
            return results;
        },
        async graphql(query, args) {
            calls.push(["commits", args]);
            return commits[page++];
        },
        rest: {
            pulls: { list: endpoint("pulls", pulls), update: write("close") },
            repos: {
                getCombinedStatusForRef: endpoint(
                    "statuses",
                    statuses.map((statuses) => ({ statuses })),
                ),
                createCommitStatus: write("status"),
            },
            issues: {
                removeLabel: write("remove-label"),
                addLabels: write("add-label"),
                createComment: write("comment"),
            },
        },
    };
}

test("a fork PR moves from pending to signed through a status event", async () => {
    const fork = pull({ user: { id: otherId } });
    const opened = client({ pulls: [[fork]] });
    await opened.run(cla);
    assert.equal(opened.writes[0][1].state, "pending");

    const signed = client({
        pulls: [[], [fork]],
        statuses: [[upstream("success")]],
    });
    await signed.run(cla, { sha: fork.head.sha, context: "license/cla" });
    assert.equal(signed.writes.length, 1);
    assert.deepEqual(signed.writes[0], [
        "status",
        {
            ...context.repo,
            sha: fork.head.sha,
            ...upstream("success"),
            context: "CLA required",
        },
    ]);
    assert.equal(signed.calls[0][1].state, "open");
    assert.equal(signed.calls[0][1].base, "main");
});

test("a delayed status event reads the latest status on the current head", async () => {
    const api = client({
        pulls: [[pull({ user: { id: otherId } })]],
        statuses: [[required("pending")], [upstream("success")]],
    });
    await api.run(cla, {
        sha: "current",
        context: "license/cla",
        state: "pending",
    });
    assert.equal(api.writes[0][1].state, "success");
    assert.ok(
        api.calls
            .filter(([name]) => name === "statuses")
            .every(([, args]) => args.ref === "current"),
    );
});

test("a status for a previous head cannot update the current PR", async () => {
    const api = client();
    await api.run(cla, { sha: "previous", context: "license/cla" });
    assert.deepEqual(api.writes, []);
});

test("covered contributors pass without calling CLA Assistant", async () => {
    const api = client({
        commits: [
            commitPage([authors(coveredId)], { next: true, count: 2 }),
            commitPage([authors(coveredId)], { count: 2 }),
        ],
    });
    await api.run(cla);
    assert.equal(api.writes[0][1].state, "success");
    assert.equal(api.calls[1][1].cursor, "next");
    assert.equal(
        api.calls.some(([name]) => name === "statuses"),
        false,
    );
});

test("an uncovered or unresolved coauthor on a later page needs upstream approval", async () => {
    for (const id of [otherId, null]) {
        const api = client({
            commits: [
                commitPage([authors(coveredId)], { next: true, count: 2 }),
                commitPage([authors(coveredId, id)], { count: 2 }),
            ],
        });
        await api.run(cla);
        assert.equal(api.writes[0][1].state, "pending");
    }
});

test("an advancing base cannot hide contributors between commit pages", async () => {
    const api = client({
        commits: [
            commitPage([authors(coveredId)], { next: true, count: 3 }),
            commitPage([authors(coveredId)], {
                count: 2,
                baseRefOid: "new-base",
            }),
        ],
    });
    await api.run(cla);
    assert.equal(api.writes[0][1].state, "pending");
});

test("a head change during pagination cannot publish coverage for mixed commits", async () => {
    const api = client({
        commits: [
            commitPage([authors(coveredId)], { next: true, count: 2 }),
            commitPage([authors(coveredId)], {
                count: 2,
                headRefOid: "new-head",
            }),
        ],
    });
    await api.run(cla);
    assert.deepEqual(api.writes, []);
});

test("incomplete contributor data falls back to upstream", async () => {
    const truncated = authors(coveredId);
    truncated.commit.authors.totalCount = 2;
    for (const page of [
        commitPage([truncated]),
        commitPage([authors(coveredId)], { count: 2 }),
        commitPage([]),
        commitPage([authors()]),
    ]) {
        const api = client({ commits: [page] });
        await api.run(cla);
        assert.equal(api.writes[0][1].state, "pending");
    }
});

test("uncovered PR authors follow upstream, including failures", async () => {
    for (const state of ["pending", "failure", "error", "success"]) {
        const api = client({
            pulls: [[pull({ user: { id: otherId } })]],
            statuses: [[required("success"), upstream(state)]],
        });
        await api.run(cla);
        assert.equal(api.writes[0][1].state, state);
        assert.equal(api.writes[0][1].target_url, upstream(state).target_url);
    }
});

test("stale cleanup preserves pending PRs until both CLA results exist", async () => {
    for (const statuses of [[upstream("pending")], [required("pending")]]) {
        const api = client({ statuses: [statuses] });
        await api.run(stale);
        assert.deepEqual(api.writes, []);
    }
});

test("stale cleanup reads later pages and removes labels after either approval", async () => {
    for (const statuses of [
        [[upstream("pending")], [required("success")]],
        [[required("pending")], [upstream("success")]],
    ]) {
        const api = client({
            pulls: [[pull({ labels: [{ name: "pending-cla" }] })]],
            statuses,
        });
        await api.run(stale);
        assert.deepEqual(
            api.writes.map(([name]) => name),
            ["remove-label"],
        );
    }
});

test("stale cleanup closes old PRs when both CLA results remain pending", async () => {
    const api = client({
        statuses: [[upstream("pending"), required("pending")]],
    });
    await api.run(stale);
    assert.deepEqual(
        api.writes.map(([name]) => name),
        ["add-label", "comment", "close"],
    );
});

test("stale cleanup uses upstream CLA for branches without the wrapper", async () => {
    const api = client({
        pulls: [[pull({ base: { ref: "release/test" } })]],
        statuses: [[upstream("pending")]],
    });
    await api.run(stale);
    assert.deepEqual(
        api.writes.map(([name]) => name),
        ["add-label", "comment", "close"],
    );
});
