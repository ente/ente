import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";

const script = join(import.meta.dirname, "check.mjs");
const pathsFile = ".github/scripts/ci/paths.json";

test("CI covers transitive local Rust dependencies", (t) => {
    const root = mkdtempSync(join(tmpdir(), "ente-rust-ci-paths-"));
    t.after(() => rmSync(root, { recursive: true }));
    const write = (path, content) => {
        mkdirSync(dirname(join(root, path)), { recursive: true });
        writeFileSync(join(root, path), content);
    };
    const crate = (path, name, dependencies = "") => {
        write(`rust/${path}/src/lib.rs`, "");
        write(
            `rust/${path}/Cargo.toml`,
            `
[package]
name = "${name}"
version = "0.1.0"
edition = "2024"
${dependencies}`,
        );
    };
    const run = (patterns, workflow = "web-lint") => {
        write(pathsFile, JSON.stringify({ [workflow]: patterns }));
        return spawnSync(process.execPath, [script, root], {
            encoding: "utf8",
        });
    };

    write(
        "rust/Cargo.toml",
        `
[workspace]
resolver = "2"
members = ["bindings/wasm/*", "bindings/uniffi/*", "crates/*", "tools/*", "apps/*"]
[workspace.dependencies]
shared-alias = { package = "shared", path = "crates/shared" }
`,
    );
    write(
        "web/packages/wasm/app/package.json",
        JSON.stringify({
            name: "app-wasm",
            scripts: { build: "wasm-pack build" },
        }),
    );
    write(
        "web/packages/wasm/tests/package.json",
        JSON.stringify({ name: "wasm-tests", scripts: { test: "vitest" } }),
    );
    crate(
        "bindings/wasm/app",
        "app-wasm",
        `
[dependencies]
shared-alias.workspace = true
[build-dependencies]
builder = { path = "../../../crates/builder" }
[dev-dependencies]
test-only = { path = "../../../crates/test-only" }
`,
    );
    crate(
        "crates/shared",
        "shared",
        `
[target.'cfg(windows)'.dependencies]
leaf = { path = "../leaf", optional = true }
`,
    );
    for (const name of ["builder", "leaf", "test-only", "native-only"])
        crate(`crates/${name}`, name);
    crate(
        "bindings/wasm/unused",
        "unused-wasm",
        `
[dependencies]
native-only = { path = "../../../crates/native-only" }
`,
    );

    crate(
        "bindings/uniffi/app",
        "app-native",
        `[dependencies]
native-only = { path = "../../../crates/native-only" }`,
    );
    crate(
        "tools/codegen",
        "codegen",
        `[dependencies]
builder = { path = "../../crates/builder" }`,
    );

    crate(
        "apps/cli",
        "cli",
        `[dev-dependencies]
test-only = { path = "../../crates/test-only" }`,
    );

    const base = [
        "rust/.cargo/config.toml",
        "rust/Cargo.lock",
        "rust/Cargo.toml",
        "rust/bindings/wasm/**",
    ];
    const needed = ["builder", "leaf", "shared"].map(
        (name) => `rust/crates/${name}/**`,
    );
    const incomplete = [
        ...base,
        "rust/crates/shared-other/**",
        "rust/crates/leaf/Cargo.toml",
    ];
    let result = run(incomplete);
    assert.equal(result.status, 1, result.stderr);
    assert.equal(result.stdout, "");
    assert.equal(
        result.stderr,
        needed
            .map(
                (path) =>
                    `${pathsFile}: web-lint missing Rust dependency path ${JSON.stringify(path)}\n`,
            )
            .join(""),
    );
    for (const patterns of [[...base, ...needed], ["rust/**"], null]) {
        result = run(patterns);
        assert.equal(result.status, 0, result.stderr);
        assert.equal(result.stdout, "");
        assert.equal(result.stderr, "");
    }
    const nativeBase = [
        "rust/.cargo/config.toml",
        "rust/Cargo.lock",
        "rust/Cargo.toml",
        "rust/bindings/uniffi/**",
        "rust/tools/codegen/**",
    ];
    result = run(nativeBase, "android-lint");
    assert.equal(result.status, 1, result.stderr);
    assert.equal(
        result.stderr,
        ["builder", "native-only"]
            .map(
                (name) =>
                    `${pathsFile}: android-lint missing Rust dependency path "rust/crates/${name}/**"\n`,
            )
            .join(""),
    );
    result = run(
        [...nativeBase, "rust/crates/builder/**", "rust/crates/native-only/**"],
        "android-lint",
    );
    assert.equal(result.status, 0, result.stderr);

    result = run(["rust/apps/cli/**", ...base], "rust-cli-test");
    assert.equal(result.status, 1, result.stderr);
    assert.equal(
        result.stderr,
        `${pathsFile}: rust-cli-test missing Rust dependency path "rust/crates/test-only/**"\n`,
    );
    result = run(
        ["rust/apps/cli/**", "rust/crates/test-only/**", ...base],
        "rust-cli-test",
    );
    assert.equal(result.status, 0, result.stderr);

    result = run([...base, ...needed, "!rust/crates/leaf/private/**"]);
    assert.equal(result.status, 1);
    assert.match(
        result.stderr,
        /web-lint coverage does not support negated paths/,
    );
    assert.equal(result.stdout, "");
    write(
        "web/packages/wasm/app/package.json",
        JSON.stringify({
            name: "missing-wasm",
            scripts: { build: "wasm-pack build" },
        }),
    );
    result = run(["rust/**"]);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /no matching Cargo package for missing-wasm/);
});
