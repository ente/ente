import { execFileSync } from "node:child_process";
import { resolve } from "node:path";

const cwd = resolve(import.meta.dirname, "../..");
for (const args of [
    [
        "node_modules/eslint/bin/eslint.js",
        "--config",
        "checks/wasm-imports/eslint.config.mjs",
        "--parser",
        "@typescript-eslint/parser",
        "--no-inline-config",
        "--max-warnings",
        "0",
        "apps",
        "packages",
    ],
    ["checks/wasm-imports/entrypoints.mjs"],
    ["--test", "checks/wasm-imports/test.mjs"],
]) {
    execFileSync(process.execPath, args, { cwd, stdio: "inherit" });
}
