import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const check = join(import.meta.dirname, "check.mjs");

for (const [source, rules] of [
    [
        '#![expect(clippy::unwrap_used, reason = "fixture")]\nfn helper() {}\n',
        ["clippy::unwrap_used"],
    ],
    [
        '#[expect(dead_code, clippy::unwrap_used, reason = "fixture")]\nmod tests {}\n',
        ["dead_code", "clippy::unwrap_used"],
    ],
    ['#[expect(dead_code, reason = "")]\nmod tests {}\n', ["dead_code"]],
]) {
    const result = run("rust/crates/fixture/src/lib.rs", source, rules);
    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stderr, /unapproved crate or module lint exception/);
}

let result = run(
    "rust/crates/fixture/src/lib.rs",
    '#[expect(dead_code, reason = "fixture")]\nfn helper() {}\n',
);
assert.equal(result.status, 0, result.stderr);
assert.equal(result.stderr, "");

result = run(
    "rust/crates/fixture/src/lib.rs",
    "#![allow(dead_code)]\nfn helper() {}\n",
);
assert.equal(result.status, 0, result.stderr);
assert.equal(result.stderr, "");

result = run(
    "rust/crates/fixture/src/lib.rs",
    '#[expect(dead_code, reason = "fixture")]\n#[cfg(test)]\nmod support {}\n',
);
assert.equal(result.status, 0, result.stderr);
assert.equal(result.stderr, "");

result = run(
    "rust/crates/vecdb/examples/vecdb_bench.rs",
    '#![expect(clippy::expect_used, reason = "fixture")]\nfn main() {}\n',
    ["clippy::expect_used"],
);
assert.equal(result.status, 0, result.stderr);
assert.equal(result.stderr, "");

result = run(
    "rust/crates/vecdb/examples/vecdb_bench.rs",
    '#![expect(clippy::expect_used, clippy::unwrap_used, reason = "fixture")]\nfn main() {}\n',
    ["clippy::expect_used", "clippy::unwrap_used"],
);
assert.equal(result.status, 1, result.stderr);

result = run(
    "rust/crates/fixture/src/lib.rs",
    '#[expect(clippy::unwrap_used, reason = "fixture")]\nmod frb_generated;\n',
    ["clippy::unwrap_used"],
);
assert.equal(result.status, 0, result.stderr);
assert.equal(result.stderr, "");

for (const source of [
    '#[expect(dead_code, reason = "fixture")] fn helper() {}',
    "#[allow(dead_code)] fn helper() {}",
    '#[cfg_attr(unix, expect(dead_code, reason = "fixture"))] fn helper() {}',
    '#[r#expect(dead_code, reason = "fixture")] fn helper() {}',
]) {
    const path = "rust/crates/fixture/src/lib.rs";
    const rejected = run(path, source, []);
    assert.equal(rejected.status, 1, rejected.stderr);
    assert.match(rejected.stderr, /dead_code is not listed/);
    const allowed = run(path, source, ["dead_code"]);
    assert.equal(allowed.status, 0, allowed.stderr);
}

const path = "rust/crates/fixture/src/lib.rs";
const suppression = '#[expect(dead_code, reason = "fixture")] fn helper() {}\n';
for (const source of [
    suppression + suppression.replace("fn helper", "fn other"),
    suppression,
]) {
    const result = run(path, source);
    assert.equal(result.status, 0, result.stderr);
}
for (const source of ["fn helper() {}", null]) {
    const result = run(path, source);
    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stderr, /dead_code has no suppression/);
    const cleaned = run(path, source, []);
    assert.equal(cleaned.status, 0, cleaned.stderr);
}

function run(path, source, rules = ["dead_code"]) {
    const root = mkdtempSync(join(tmpdir(), "ente-rust-lint-exceptions-"));
    try {
        spawn("git", ["init", "-q"], root);
        if (source !== null) write(root, path, source);
        write(
            root,
            "rust/checks/lint-exceptions/suppressions.json",
            JSON.stringify({ [path]: rules }),
        );
        spawn("git", ["add", "."], root);
        return spawnSync(process.execPath, [check, root], { encoding: "utf8" });
    } finally {
        rmSync(root, { recursive: true });
    }
}

function write(root, path, content) {
    const target = join(root, path);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, content);
}

function spawn(command, args, cwd) {
    const result = spawnSync(command, args, { cwd, encoding: "utf8" });
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0, result.stderr);
}
