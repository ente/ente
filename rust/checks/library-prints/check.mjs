import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(process.argv[2]);
const library =
    /^rust\/(?:crates\/(?!test-support\/)[^/]+|bindings\/[^/]+\/[^/]+)\/src\/.*\.rs$/;
const literals =
    /\/\/[^\n]*|\/\*[\s\S]*?\*\/|b?r(#*)"[\s\S]*?"\1|b?"(?:\\[\s\S]|[^"\\])*"|b?'(?:\\.|[^'\\\n])'/g;
const tokens = /#\[cfg\(test\)\]|\b(e?print(?:ln)?)!|[{};]/g;
const sources = execFileSync(
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
    .filter((path) => library.test(path) && existsSync(resolve(root, path)));

for (const path of sources) {
    const source = readFileSync(resolve(root, path), "utf8").replace(
        literals,
        (text) => text.replace(/[^\n]/g, " "),
    );
    let skipping = 0;
    let depth = 0;
    for (const match of source.matchAll(tokens)) {
        const [token, macro] = match;
        if (token === "#[cfg(test)]") skipping ||= 1;
        else if (token === "{" && skipping) {
            skipping = 2;
            depth++;
        } else if (token === "}" && skipping === 2 && --depth === 0) {
            skipping = 0;
        } else if (token === ";" && skipping === 1) skipping = 0;
        else if (macro && !skipping) {
            const line = source.slice(0, match.index).split("\n").length;
            console.error(
                `${path}:${line}: ${macro}! in a library crate; use the log macros`,
            );
            process.exitCode = 1;
        }
    }
}
