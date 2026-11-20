import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

const paths = JSON.parse(
    readFileSync(
        new URL("../../scripts/ci/paths.json", import.meta.url),
        "utf8",
    ),
);
const patterns = [
    ...paths["mobile-lint"].filter((path) => path.startsWith("rust/")),
    ".github/actions/restore-frb-outputs/**",
    ".github/actions/setup-flutter/**",
    ".github/workflows/mobile-lint.yml",
    ".github/workflows/warm-caches.yml",
    "mobile/apps/*/flutter_rust_bridge.yaml",
    "mobile/packages/frb/pubspec.yaml",
    "mobile/pubspec.lock",
];
const index = execFileSync("git", [
    "ls-files",
    "-s",
    "--",
    ...patterns.map((pattern) => `:(top,glob)${pattern}`),
]);
const hash = createHash("sha256").update(index).digest("hex");
console.log(`version=${process.env.ImageOS}-${hash}`);
