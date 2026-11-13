import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync, statSync, utimesSync, writeFileSync } from "node:fs";

const restore = process.argv[2] === "restore";
const manifest = "rust/target/source-mtimes.json";
const mtimes = restore ? JSON.parse(readFileSync(manifest, "utf8")) : {};
const paths = execFileSync("git", ["ls-files", "-z", "--", "rust"], {
    encoding: "utf8",
})
    .split("\0")
    .filter(Boolean);

for (const path of paths) {
    const stat = statSync(path);
    const hash = createHash("sha256")
        .update(readFileSync(path))
        .update(String(stat.mode))
        .digest("hex");
    if (restore) {
        // Preserve real timestamps so older feature builds remain stale.
        const mtime = hash === mtimes[path]?.[0] ? mtimes[path][1] : Date.now();
        utimesSync(path, stat.atime, mtime / 1000);
    } else {
        mtimes[path] = [hash, stat.mtimeMs];
    }
}

if (!restore) writeFileSync(manifest, JSON.stringify(mtimes));
