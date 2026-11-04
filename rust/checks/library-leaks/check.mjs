import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

const root = resolve(process.argv[2]);
const library =
    /^rust\/(?:crates\/(?!test-support\/)[^/]+|bindings\/[^/]+\/[^/]+)\/src\/.*\.rs$/;
const tokens =
    /\/\/[^\n]*|\/\*[\s\S]*?\*\/|b?'(?:\\.|[^'\\\n])'|(b?r(#*)"[\s\S]*?"\2|b?"(?:\\[\s\S]|[^"\\])*")|(#\[cfg\(test\)\])|\b(e?print(?:ln)?)!|([{};])/g;
const testModules =
    /#\[cfg\(test\)\]\s*(?:pub(?:\([^)]*\))?\s+)?mod\s+([A-Za-z_][A-Za-z0-9_]*)\s*;/g;
const wording = /--[a-z][a-z-]*|\bCLI\b/g;
const wordingExceptions = new Map([
    ["rust/crates/ml/src/onnx/golden_test/tooling.rs", ["--example"]],
]);
const files = new Map(
    execFileSync(
        "git",
        [
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "-z",
            "--",
            "rust/crates",
            "rust/bindings",
        ],
        { cwd: root, encoding: "utf8" },
    )
        .split("\0")
        .filter((path) => library.test(path) && existsSync(resolve(root, path)))
        .map((path) => [path, readFileSync(resolve(root, path), "utf8")]),
);
const testOnly = [];
for (const [path, source] of files) {
    const base = /(?:^|\/)(?:mod|lib|main)\.rs$/.test(path)
        ? dirname(path)
        : path.slice(0, -3);
    for (const [, name] of source.matchAll(testModules)) {
        testOnly.push(`${base}/${name}.rs`, `${base}/${name}/`);
    }
}

for (const [path, source] of files) {
    if (testOnly.some((prefix) => path.startsWith(prefix))) continue;
    let skipping = 0;
    let depth = 0;
    for (const match of source.matchAll(tokens)) {
        const [, string, , cfg, macro, brace] = match;
        let problem;
        if (cfg) skipping ||= 1;
        else if (brace === "{" && skipping) {
            skipping = 2;
            depth++;
        } else if (brace === "}" && skipping === 2 && --depth === 0) {
            skipping = 0;
        } else if (brace === ";" && skipping === 1) skipping = 0;
        else if (skipping) continue;
        else if (macro)
            problem = `${macro}! in a library crate; use the log macros`;
        else if (string) {
            const allowed = wordingExceptions.get(path) ?? [];
            const hit = string
                .match(wording)
                ?.find((hit) => !allowed.includes(hit));
            if (hit)
                problem = `${JSON.stringify(hit)} in a library string; CLI wording belongs in the CLI`;
        }
        if (!problem) continue;
        const line = source.slice(0, match.index).split("\n").length;
        console.error(`${path}:${line}: ${problem}`);
        process.exitCode = 1;
    }
}
