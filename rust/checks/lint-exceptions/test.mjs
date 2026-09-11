import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const check = join(import.meta.dirname, "check.mjs");

for (const source of [
    '#![expect(clippy::unwrap_used, reason = "fixture")]\nfn helper() {}\n',
    '#[expect(dead_code, clippy::unwrap_used, reason = "fixture")]\nmod tests {}\n',
    '#[expect(dead_code, reason = "")]\nmod tests {}\n',
]) {
    const result = run("rust/crates/fixture/src/lib.rs", source);
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
    "rust/crates/ml/examples/vecdb_bench.rs",
    '#![expect(clippy::expect_used, reason = "fixture")]\nfn main() {}\n',
);
assert.equal(result.status, 0, result.stderr);
assert.equal(result.stderr, "");

result = run(
    "rust/crates/ml/examples/vecdb_bench.rs",
    '#![expect(clippy::expect_used, clippy::unwrap_used, reason = "fixture")]\nfn main() {}\n',
);
assert.equal(result.status, 1, result.stderr);

result = run(
    "rust/crates/fixture/src/lib.rs",
    '#[expect(clippy::unwrap_used, reason = "fixture")]\nmod frb_generated;\n',
);
assert.equal(result.status, 0, result.stderr);
assert.equal(result.stderr, "");

function run(path, source) {
    const root = mkdtempSync(join(tmpdir(), "ente-rust-lint-exceptions-"));
    try {
        spawn("git", ["init", "-q"], root);
        write(root, path, source);
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
