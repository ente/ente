#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(
    path.dirname(fileURLToPath(import.meta.url)),
    "../..",
);
const manifest = path.join(root, "rust/apps/cli/Cargo.toml");
const lockfile = path.join(root, "rust/Cargo.lock");
const source = fs.readFileSync(manifest, "utf8");
const [command = "get", version] = process.argv.slice(2);

if (command === "get") {
    console.log(source.match(/^version = "([^"]+)"$/m)[1]);
} else if (command === "set" && /^\d+\.\d+\.\d+$/.test(version)) {
    for (const [file, pattern] of [
        [manifest, /(^version = ")[^"]+(")/m],
        [lockfile, /(name = "ente-cli"\nversion = ")[^"]+(")/],
    ]) {
        const text = fs.readFileSync(file, "utf8");
        if (!pattern.test(text)) throw new Error(`No CLI version in ${file}`);
        fs.writeFileSync(
            file,
            text.replace(pattern, (_, a, b) => `${a}${version}${b}`),
        );
    }
} else {
    console.error(
        "Usage: node .github/scripts/cli-version.mjs get|set <x.y.z>",
    );
    process.exit(2);
}
