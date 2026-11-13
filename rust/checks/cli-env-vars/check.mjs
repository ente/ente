import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(process.argv[2]);
const documented = new Set([
    "ENTE_CLI_HOME",
    "ENTE_CLI_PASSWORD",
    "ENTE_CLI_VAULT_KEY",
]);
const reads = /\benv::var(?:_os)?\s*\(\s*([^)]*?)\s*\)/g;
const sources = execFileSync(
    "git",
    [
        "ls-files",
        "--cached",
        "--others",
        "--exclude-standard",
        "-z",
        "--",
        "rust/apps/cli/src",
    ],
    { cwd: root, encoding: "utf8" },
)
    .split("\0")
    .filter((path) => path.endsWith(".rs") && existsSync(resolve(root, path)));

for (const path of sources) {
    const source = readFileSync(resolve(root, path), "utf8");
    for (const match of source.matchAll(reads)) {
        const line = source.slice(0, match.index).split("\n").length;
        const name = match[1].match(/^"([^"]*)"$/)?.[1];
        if (name === undefined) {
            console.error(`${path}:${line}: env::var takes a string literal`);
        } else if (!documented.has(name)) {
            console.error(
                `${path}:${line}: ${name} is not a documented environment variable`,
            );
        } else continue;
        process.exitCode = 1;
    }
}
