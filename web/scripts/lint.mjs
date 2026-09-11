import concurrently from "concurrently";
import { globSync } from "node:fs";
import { basename, dirname, resolve } from "node:path";

const cwd = resolve(import.meta.dirname, "..");
const fix = process.argv.includes("--fix");
const commands = [
    {
        name: "prettier",
        command: `npm exec -- prettier --${fix ? "write" : "check"} --log-level warn .`,
    },
    {
        name: "eslint",
        command: `npm exec --workspaces -- eslint ${fix ? "--fix " : ""}--max-warnings 0`,
    },
    { name: "tsc", command: "npm exec --workspaces -- tsc" },
    ...globSync("checks/*/check.mjs", { cwd })
        .sort()
        .map((path) => ({
            name: basename(dirname(path)),
            command: `node ${path}`,
        })),
];

try {
    await concurrently(commands, { cwd }).result;
} catch {
    process.exitCode = 1;
}
