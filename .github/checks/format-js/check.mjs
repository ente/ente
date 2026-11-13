import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dirname, "../../..");
const lock = readJSON("web/package-lock.json");
const version = lock.packages["node_modules/prettier"].version;
const { plugins, ...options } = readJSON("web/.prettierrc.json");
const write = process.argv.includes("--write");
const temporary = mkdtempSync(join(tmpdir(), "ente-prettier-"));

try {
    const config = join(temporary, "prettier.json");
    writeFileSync(config, JSON.stringify(options));
    const { error, status } = spawnSync(
        "npm",
        [
            "exec",
            "--yes",
            "--ignore-scripts",
            "--prefer-offline",
            `--package=prettier@${version}`,
            "--",
            "prettier",
            "--config",
            config,
            write ? "--write" : "--check",
            ".github/{checks,scripts}/**/*.{js,cjs,mjs}",
            "**/{checks,scripts}/**/*.{js,cjs,mjs}",
            "!mobile/apps/auth/assets/simple-icons/**",
        ],
        { cwd: root, stdio: "inherit" },
    );
    if (error) throw error;
    if (status === 1)
        console.error("Fix: node .github/checks/format-js/check.mjs --write");
    process.exitCode = status ?? 1;
} finally {
    rmSync(temporary, { recursive: true });
}

function readJSON(path) {
    return JSON.parse(readFileSync(resolve(root, path), "utf8"));
}
