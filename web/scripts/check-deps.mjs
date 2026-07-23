import { existsSync, statSync } from "node:fs";

const lock = new URL("../package-lock.json", import.meta.url);
const installed = new URL(
    "../node_modules/.package-lock.json",
    import.meta.url,
);

if (
    !existsSync(installed) ||
    statSync(installed).mtimeMs < statSync(lock).mtimeMs
) {
    console.error("Error: web dependencies are missing or stale.");
    console.error("Run:");
    console.error('  (cd "$(git rev-parse --show-toplevel)/web" && npm ci)');
    process.exit(1);
}
