/**
 * Fetch binary dependencies and rebuild native modules.
 *
 * Installs skip dependency lifecycle scripts (`ignore-scripts` in `.npmrc`),
 * so this postinstall step doesn't run automatically on install and needs to
 * be invoked explicitly (`npm run postinstall`).
 *
 * With `--if-needed`, do nothing if we've already run for the currently
 * installed dependency tree. The stamp records a hash of npm's hidden
 * lockfile (`node_modules/.package-lock.json`), which reflects what is
 * actually installed, so both `npm ci` (which recreates `node_modules`) and
 * incremental `npm install`s that change packages invalidate it.
 */

import { execSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

const stamp = "node_modules/.postinstall-stamp";

const treeHash = () =>
    createHash("sha256")
        .update(readFileSync("node_modules/.package-lock.json"))
        .digest("hex");

if (process.argv.includes("--if-needed")) {
    try {
        if (readFileSync(stamp, "utf8") === treeHash()) process.exit(0);
    } catch {}
    console.log(
        "Dependencies changed since last postinstall, running npm run postinstall",
    );
}

const run = (cmd) => {
    console.log(`> ${cmd}`);
    execSync(cmd, { stdio: "inherit" });
};

run(
    "npm rebuild --ignore-scripts=false ffmpeg-static onnxruntime-node electron-winstaller",
);
run("npm exec -- electron-builder install-app-deps");
run("node scripts/vips.js");

writeFileSync(stamp, treeHash());
