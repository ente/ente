import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const check = join(import.meta.dirname, "check.mjs");

let result = run(
    {
        "rust/lib.rs": "//! Module documentation.\npub fn value() {}\n",
        "mobile/value.dart": "/// API documentation.\nclass Value {}\n",
        "android/Value.kt": "/** API documentation. */\nclass Value\n",
        "native/value.h": "/** API documentation. */\nint value(void);\n",
        "web/value.ts": "/** API documentation. */\nexport const value = 1;\n",
        "styles/value.scss": "/** API documentation. */\n.value {}\n",
        "styles/value.css": "/** API documentation. */\n.value {}\n",
        "build/plugin.gradle": "/// API documentation.\n",
        "gen/value.ts":
            "/** A path alone does not mark a file as generated. */\n",
        "web/reference.ts": [
            '/// <reference types="vite/client" />',
            "/// API documentation.",
        ].join("\n"),
        "web/config.js": [
            "/** @param {string} value",
            " * API documentation.",
            " */",
            "function configure(value) {}",
        ].join("\n"),
        "web/type.js":
            "/** @type {string} API documentation. */\nconst value = '';\n",
        "web/type.ts": "/** @type {string} */\nconst value = '';\n",
        "web/param.js":
            "/** @param {string} */\nfunction configure(value) {}\n",
        "web/satisfies.js": [
            "/** @satisfies {Record<string, string>}",
            " * API documentation.",
            " */",
            "const values = {};",
        ].join("\n"),
        "web/returns.js":
            "/** @returns {string} API documentation. */\nfunction value() {}\n",
        "rust/clap.rs": [
            "#[derive(clap::Parser)]",
            "struct Args {",
            "    /// Printed in command help.",
            "    json: bool,",
            "}",
            "/// API documentation.",
            "pub fn value() {}",
        ].join("\n"),
        "rust/unit_clap.rs": [
            "/// Printed in top-level command help.",
            "#[derive(clap::Parser)]",
            "struct Args;",
            "/// API documentation.",
            "pub fn value() {}",
        ].join("\n"),
        "deleted.rs": "/// Deleted documentation.\n",
    },
    { "native/Value.swift": "/// API documentation.\nstruct Value {}\n" },
    ["deleted.rs"],
);
assert.equal(result.status, 1, result.stderr);
for (const path of [
    "rust/lib.rs:1",
    "mobile/value.dart:1",
    "android/Value.kt:1",
    "native/value.h:1",
    "web/value.ts:1",
    "styles/value.scss:1",
    "styles/value.css:1",
    "build/plugin.gradle:1",
    "gen/value.ts:1",
    "web/reference.ts:1",
    "web/config.js:1",
    "web/type.js:1",
    "web/type.ts:1",
    "web/param.js:1",
    "web/satisfies.js:1",
    "web/returns.js:1",
    "rust/clap.rs:6",
    "rust/unit_clap.rs:4",
    "native/Value.swift:1",
]) {
    assert.match(result.stderr, new RegExp(path.replace(".", "\\.")));
}
assert.doesNotMatch(result.stderr, /deleted/);
assert.doesNotMatch(result.stderr, /rust\/clap\.rs:3/);
assert.doesNotMatch(result.stderr, /rust\/unit_clap\.rs:1/);

result = run({
    "rust/local.rs":
        "// Non-obvious implementation reason.\npub fn value() {}\n",
    "rust/args.rs": [
        "/// Printed in top-level command help.",
        "#[derive(clap::Parser)]",
        "pub struct Args {",
        "    /// Printed in command help.",
        "    pub json: bool,",
        "}",
    ].join("\n"),
    "rust/block_args.rs": [
        "/** Printed in top-level command help. */",
        "#[derive(clap::Parser)]",
        "pub struct Args {}",
    ].join("\n"),
    "web/env.d.ts": '/// <reference types="vite/client" />\n',
    "web/config.js": [
        '/** @param {import("webpack").Compiler} compiler */',
        "function configure(compiler) {}",
        '/** @type {import("next").NextConfig} */',
        "const config = {};",
        "/** @satisfies {Record<string, string>} */",
        "const values = {};",
        "/** @returns {string} */",
        "function value() { return ''; }",
        "/**",
        " * @template T",
        " * @param {T} value",
        " * @returns {T}",
        " */",
        "function identity(value) { return value; }",
        "/**",
        " * @typedef {{ value: string }} Value",
        " * @property {string} name",
        " * @prop {number} count",
        " */",
    ].join("\n"),
    "generated/value.dart": [
        "// Generated file. Do not edit.",
        "/// Generated documentation.",
        "class Value {}",
    ].join("\n"),
    "mobile/value.g.dart": [
        "// Generated code. Do not modify.",
        "/// Generated documentation.",
        "class Value {}",
    ].join("\n"),
});
assert.equal(result.status, 0, result.stderr);
assert.equal(result.stdout, "");
assert.equal(result.stderr, "");

result = run({ ".gitignore": "" });
assert.notEqual(result.status, 0, result.stderr);
assert.match(result.stderr, /found no source files/);

function run(tracked, untracked = {}, deleted = []) {
    const root = mkdtempSync(join(tmpdir(), "ente-documentation-comments-"));
    try {
        spawn("git", ["init", "-q"], root);
        for (const [path, content] of Object.entries(tracked))
            write(root, path, content);
        spawn("git", ["add", "."], root);
        for (const path of deleted) rmSync(join(root, path));
        for (const [path, content] of Object.entries(untracked))
            write(root, path, content);
        return spawn(process.execPath, [check, root]);
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
    return result;
}
