import { execSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { ensureFFmpeg } from "./ffmpeg.js";
import { ensureVips } from "./vips.js";

const stamp = "node_modules/.postinstall-stamp";

// npm's hidden lockfile represents the dependency tree installed in node_modules.
const treeHash = () =>
    createHash("sha256")
        .update(readFileSync("node_modules/.package-lock.json"))
        .digest("hex");

await ensureVips(process.platform, process.arch, process.cwd());
await ensureFFmpeg(process.platform, process.arch, process.cwd());

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

run("node scripts/patch-electron-builder.mjs");
run("npm rebuild --ignore-scripts=false electron-winstaller");
run("npm exec -- electron-builder install-app-deps");
run("node scripts/ort.js");

writeFileSync(stamp, treeHash());
