import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(process.argv[2]);
const listPath = "rust/checks/cli-test-sleeps/allowed.json";
const allowed = JSON.parse(readFileSync(resolve(root, listPath), "utf8"));
const unused = new Map(
    Object.entries(allowed).map(([path, names]) => [path, new Set(names)]),
);
const sleeps = /\bsleep\s*\(/g;
const functions = /\bfn\s+([A-Za-z_][A-Za-z0-9_]*)/g;
const sources = execFileSync(
    "git",
    [
        "ls-files",
        "--cached",
        "--others",
        "--exclude-standard",
        "-z",
        "--",
        "rust/apps/cli/tests",
    ],
    { cwd: root, encoding: "utf8" },
)
    .split("\0")
    .filter((path) => path.endsWith(".rs") && existsSync(resolve(root, path)));

for (const path of sources) {
    const source = readFileSync(resolve(root, path), "utf8");
    const names = [...source.matchAll(functions)];
    for (const match of source.matchAll(sleeps)) {
        const name = names.findLast((name) => name.index < match.index)?.[1];
        if (unused.get(path)?.delete(name)) continue;
        const line = source.slice(0, match.index).split("\n").length;
        console.error(
            `${path}:${line}: sleep in ${name}; use the ObjectStoreControl barriers in ente-test-support`,
        );
        process.exitCode = 1;
    }
}

for (const [path, names] of unused) {
    for (const name of names) {
        console.error(
            `${path}: ${name} no longer sleeps; remove it from ${listPath}`,
        );
        process.exitCode = 1;
    }
}
