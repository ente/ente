import { execFileSync } from "node:child_process";
import { resolve } from "node:path";

const cwd = resolve(import.meta.dirname, "../..");
for (const args of [
    [
        "node_modules/eslint/bin/eslint.js",
        "--config",
        "checks/wasm-names/eslint.config.mjs",
        "--no-inline-config",
        "--max-warnings",
        "0",
        "packages/wasm/*/pkg/*.d.ts",
    ],
    ["--test", "checks/wasm-names/test.mjs"],
]) {
    execFileSync(process.execPath, args, { cwd, stdio: "inherit" });
}
