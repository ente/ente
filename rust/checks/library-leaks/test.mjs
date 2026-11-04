import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const check = join(import.meta.dirname, "check.mjs");

let result = run({
    "rust/crates/domain/src/lib.rs":
        'pub fn f() {\n    let s = "println!(x)";\n    let sql = "SELECT 1 -- note";\n}\n// eprintln!("use --adopt")\n#[cfg(test)]\nuse std::fmt;\n#[cfg(test)]\nfn helper() {\n    eprintln!("test");\n}\n#[cfg(test)]\nmod tests;\n#[cfg(test)]\nmod inline {\n    #[test]\n    fn t() {\n        println!("{}", 1);\n        let args = ["--exact"];\n    }\n}\n',
    "rust/crates/domain/src/tests.rs": 'fn t() {\n    println!("--json");\n}\n',
    "rust/crates/ml/src/onnx/golden_test/tooling.rs":
        'const HEADER: &str = "cargo run --example goldens";\n',
});
assert.equal(result.status, 0, result.stderr);
assert.equal(result.stderr, "");

result = run({
    "rust/crates/ml/src/onnx/golden_test/tooling.rs":
        'const HEADER: &str = "cargo run --example goldens --release";\n',
});
assert.equal(result.status, 1, result.stderr);
assert.equal(
    result.stderr,
    'rust/crates/ml/src/onnx/golden_test/tooling.rs:1: "--release" in a library string; CLI wording belongs in the CLI\n',
);

result = run({
    "rust/crates/domain/src/lib.rs":
        'pub fn f() {\n    print!("a");\n    log::warn!("use --adopt to take over");\n}\n#[cfg(test)]\nmod tests {}\nfn g() {\n    eprintln!("c");\n    let label = "this CLI\'s records";\n}\n',
});
assert.equal(result.status, 1, result.stderr);
assert.equal(
    result.stderr,
    'rust/crates/domain/src/lib.rs:2: print! in a library crate; use the log macros\nrust/crates/domain/src/lib.rs:3: "--adopt" in a library string; CLI wording belongs in the CLI\nrust/crates/domain/src/lib.rs:8: eprintln! in a library crate; use the log macros\nrust/crates/domain/src/lib.rs:9: "CLI" in a library string; CLI wording belongs in the CLI\n',
);

for (const path of [
    "rust/crates/test-support/src/lib.rs",
    "rust/crates/domain/examples/run.rs",
    "rust/apps/cli/src/main.rs",
]) {
    result = run({ [path]: 'fn f() {\n    println!("--json");\n}\n' });
    assert.equal(result.status, 0, result.stderr);
}

result = run({
    "rust/bindings/wasm/lib/src/lib.rs": 'fn f() {\n    println!("x");\n}\n',
});
assert.equal(result.status, 1, result.stderr);

function run(files) {
    const root = mkdtempSync(join(tmpdir(), "ente-library-leaks-"));
    try {
        spawnSync("git", ["init", "-q"], { cwd: root });
        for (const [path, source] of Object.entries(files)) {
            mkdirSync(join(root, dirname(path)), { recursive: true });
            writeFileSync(join(root, path), source);
        }
        return spawnSync(process.execPath, [check, root], { encoding: "utf8" });
    } finally {
        rmSync(root, { recursive: true });
    }
}
