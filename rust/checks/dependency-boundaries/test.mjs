import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const check = join(import.meta.dirname, "check.mjs");
const packageToml = (name, dependencies = "") =>
    `[package]\nname = ${JSON.stringify(name)}\nversion = "0.1.0"\nedition = "2024"\n${dependencies}`;

let result = run();
assert.equal(result.status, 0, result.stderr);
assert.equal(result.stdout, "");
assert.equal(result.stderr, "");

for (const framework of [
    "wasm-bindgen",
    "js-sys",
    "web-sys",
    "serde-wasm-bindgen",
    "tsify-macros",
    "flutter_rust_bridge_macros",
    "uniffi_macros",
    "napi-derive",
]) {
    result = run({ framework });
    assert.equal(result.status, 1, result.stderr);
    assert.match(
        result.stderr,
        new RegExp(`dependency "${framework}" crosses`),
    );
}

result = run({ binding: true });
assert.equal(result.status, 1, result.stderr);
assert.match(result.stderr, /dependency "ente-binding" crosses/);

result = run({
    source: '// wasm_bindgen::JsValue is isolated here.\npub const NOTE: &str = "uniffi::export";\n',
});
assert.equal(result.status, 0, result.stderr);

result = run({ unregistered: true });
assert.equal(result.status, 1, result.stderr);
assert.match(
    result.stderr,
    /rust\/crates\/unregistered\/Cargo\.toml: domain crate is not registered/,
);

result = run({ empty: true });
assert.equal(result.status, 1, result.stderr);
assert.match(result.stderr, /found no domain crates/);

result = run({ deleted: true });
assert.equal(result.status, 0, result.stderr);
assert.equal(result.stderr, "");

for (const dependencyKind of [
    "dependencies",
    "dev-dependencies",
    "build-dependencies",
    `target.'cfg(target_arch = "wasm32")'.dependencies`,
    `target.'cfg(target_arch = "wasm32")'.dev-dependencies`,
]) {
    result = run({ framework: "reqwest", dependencyKind });
    assert.equal(result.status, 1, result.stderr);
    assert.match(
        result.stderr,
        /use ente-core::http instead of a direct reqwest dependency/,
    );
}

result = run({ framework: "reqwest", bindingDependencyKind: "dependencies" });
assert.equal(result.status, 1, result.stderr);
assert.match(
    result.stderr,
    /rust\/bindings\/wasm\/lib\/Cargo\.toml: use ente-core::http/,
);

for (const domainName of ["core", "assets"]) {
    result = run({
        framework: "reqwest",
        dependencyKind: "dependencies",
        domainName,
    });
    assert.equal(result.status, 0, result.stderr);
}

result = run({
    projections: {
        "rust/bindings/wasm/lib/src/projection.rs":
            "pub struct Output;\npub enum Error { Other }\n",
        "rust/bindings/frb/lib/src/projection.rs":
            "pub fn operation() {}\npub enum LockerError { Other }\n",
    },
});
assert.equal(result.status, 1, result.stderr);
assert.match(result.stderr, /projection\.rs: Output precedes Error/);
assert.match(result.stderr, /projection\.rs: operation precedes LockerError/);

result = run({
    projections: {
        "rust/bindings/wasm/lib/src/projection.rs":
            "pub enum Error { Other }\npub struct Output;\n",
        "rust/bindings/frb/lib/src/projection.rs":
            "pub enum LockerError { Other }\npub fn operation() {}\n",
    },
});
assert.equal(result.status, 0, result.stderr);
assert.equal(result.stderr, "");

function run({
    source = "pub fn domain() {}\n",
    framework,
    binding = false,
    empty = false,
    unregistered = false,
    deleted = false,
    dependencyKind = "dev-dependencies",
    domainName = "domain",
    bindingDependencyKind,
    projections = {},
} = {}) {
    const root = mkdtempSync(join(tmpdir(), "ente-rust-dependencies-"));
    try {
        spawn("git", ["init", "-q"], root);
        if (empty) {
            write(root, "rust/Cargo.toml", '[workspace]\nresolver = "2"\n');
        } else {
            const members = [`crates/${domainName}`, "bindings/wasm/lib"];
            if (framework) members.push("vendor/framework");
            write(
                root,
                "rust/Cargo.toml",
                `[workspace]\nmembers = ${JSON.stringify(members)}\nresolver = "2"\n`,
            );
            const dependencies = framework
                ? `\n[${dependencyKind}]\nbinding = { package = ${JSON.stringify(framework)}, path = "../../vendor/framework" }\n`
                : binding
                  ? '\n[dependencies]\nbinding = { package = "ente-binding", path = "../../bindings/wasm/lib" }\n'
                  : "";
            write(
                root,
                `rust/crates/${domainName}/Cargo.toml`,
                packageToml(domainName, dependencies),
            );
            write(root, `rust/crates/${domainName}/src/lib.rs`, source);
            write(
                root,
                "rust/bindings/wasm/lib/Cargo.toml",
                packageToml(
                    "ente-binding",
                    bindingDependencyKind
                        ? `\n[${bindingDependencyKind}]\nhttp = { package = ${JSON.stringify(framework)}, path = "../../../vendor/framework" }\n`
                        : "",
                ),
            );
            write(
                root,
                "rust/bindings/wasm/lib/src/lib.rs",
                "pub fn binding() {}\n",
            );
            for (const [path, source] of Object.entries(projections)) {
                write(root, path, source);
            }
            if (framework) {
                write(
                    root,
                    "rust/vendor/framework/Cargo.toml",
                    packageToml(framework),
                );
                write(
                    root,
                    "rust/vendor/framework/src/lib.rs",
                    "pub fn framework() {}\n",
                );
            }
            if (unregistered || deleted) {
                write(
                    root,
                    "rust/crates/unregistered/Cargo.toml",
                    packageToml("unregistered"),
                );
                write(
                    root,
                    "rust/crates/unregistered/src/lib.rs",
                    "pub fn unregistered() {}\n",
                );
            }
        }
        spawn(
            "cargo",
            ["metadata", "--no-deps", "--format-version", "1", "--offline"],
            join(root, "rust"),
        );
        spawn("git", ["add", "."], root);
        if (deleted)
            rmSync(join(root, "rust/crates/unregistered"), { recursive: true });
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
    return result;
}
