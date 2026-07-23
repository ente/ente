import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const rootDir = path.resolve(__dirname, "..");
const webDir = path.resolve(rootDir, "..", "..", "..", "web");
const checkWebDepsPath = path.join(webDir, "scripts", "check-deps.mjs");
const tauriConfigPath = path.join(rootDir, "src-tauri", "tauri.conf.json");
const desktopVersion = JSON.parse(
    fs.readFileSync(tauriConfigPath, "utf8"),
).version;
if (!desktopVersion) throw new Error("Missing Ensu desktop version");

const npmBin = process.platform === "win32" ? "npm.cmd" : "npm";
const check = spawnSync(process.execPath, [checkWebDepsPath], {
    stdio: "inherit",
});
if (check.status !== 0) process.exit(check.status ?? 1);

const child = spawn(npmBin, ["run", "build:ensu"], {
    cwd: webDir,
    stdio: "inherit",
    shell: process.platform === "win32",
    env: {
        ...process.env,
        ENTE_TAURI: "1",
        _ENTE_IS_DESKTOP: "1",
        NEXT_PUBLIC_ENSU_DESKTOP_VERSION: desktopVersion,
    },
});

child.on("exit", (code) => process.exit(code ?? 1));
