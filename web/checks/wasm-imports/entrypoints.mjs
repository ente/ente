import { globSync, readFileSync } from "node:fs";
import { rawWasmPath } from "./eslint.config.mjs";

const payload = new RegExp(rawWasmPath);
for (const path of globSync("packages/wasm/*/package.json")) {
    const manifest = JSON.parse(readFileSync(path, "utf8"));
    const target = ["main", "module", "browser", "exports"]
        .flatMap((key) => runtimeTargets(manifest[key]))
        .find((target) => payload.test(target));
    if (target) {
        console.error(
            `${path}: runtime entrypoint ${target} bypasses the wrapper`,
        );
        process.exitCode = 1;
    }
}

function runtimeTargets(value) {
    if (typeof value === "string") return [value];
    return Object.entries(value ?? {}).flatMap(([key, target]) =>
        key === "types" ? [] : runtimeTargets(target),
    );
}
