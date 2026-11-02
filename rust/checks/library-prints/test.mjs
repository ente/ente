import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const check = join(import.meta.dirname, "check.mjs");

let result = run(
    'pub fn f() {\n    let s = "println!(x)";\n}\n// eprintln!("no")\n#[cfg(test)]\nuse std::fmt;\n#[cfg(test)]\nfn helper() {\n    eprintln!("test");\n}\n#[cfg(test)]\nmod tests {\n    #[test]\n    fn t() {\n        println!("{}", 1);\n    }\n}\n',
);
assert.equal(result.status, 0, result.stderr);
assert.equal(result.stderr, "");

result = run(
    'pub fn f() {\n    print!("a");\n    log::warn!("b");\n}\n#[cfg(test)]\nmod tests {}\nfn g() {\n    eprintln!("c");\n}\n',
);
assert.equal(result.status, 1, result.stderr);
assert.equal(
    result.stderr,
    "rust/crates/domain/src/lib.rs:2: print! in a library crate; use the log macros\nrust/crates/domain/src/lib.rs:8: eprintln! in a library crate; use the log macros\n",
);

for (const path of [
    "rust/crates/test-support/src/lib.rs",
    "rust/crates/domain/examples/run.rs",
    "rust/apps/cli/src/main.rs",
]) {
    result = run('fn f() {\n    println!("x");\n}\n', path);
    assert.equal(result.status, 0, result.stderr);
}

result = run(
    'fn f() {\n    println!("x");\n}\n',
    "rust/bindings/wasm/lib/src/lib.rs",
);
assert.equal(result.status, 1, result.stderr);

function run(source, path = "rust/crates/domain/src/lib.rs") {
    const root = mkdtempSync(join(tmpdir(), "ente-library-prints-"));
    try {
        spawnSync("git", ["init", "-q"], { cwd: root });
        mkdirSync(join(root, dirname(path)), { recursive: true });
        writeFileSync(join(root, path), source);
        return spawnSync(process.execPath, [check, root], { encoding: "utf8" });
    } finally {
        rmSync(root, { recursive: true });
    }
}
