import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

const cwd = resolve(import.meta.dirname, "../..");
process.exitCode =
    spawnSync(
        process.execPath,
        [
            "node_modules/knip/bin/knip.js",
            "--config",
            "checks/unused-exports/knip.json",
            "--include",
            "exports,types",
        ],
        { cwd, stdio: "inherit" },
    ).status ?? 1;
