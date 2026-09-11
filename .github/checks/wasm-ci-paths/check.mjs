import { execFileSync } from "node:child_process";
import { globSync, readFileSync, realpathSync } from "node:fs";
import { dirname, relative, resolve } from "node:path";

const root = realpathSync(process.argv[2] ?? ".");
const pathsFile = ".github/scripts/ci/paths.json";
const patterns = readJSON(resolve(root, pathsFile))["web-lint"];

if (patterns !== null) {
    if (patterns.some((pattern) => pattern.startsWith("!"))) {
        throw new Error(
            `${pathsFile}: WASM coverage does not support negated paths`,
        );
    }
    // Literal directory prefixes prove coverage of future files too.
    const prefixes = patterns
        .filter((pattern) => /^[\w./-]+\/\*\*$/.test(pattern))
        .map((pattern) => pattern.slice(0, -2));
    for (const path of wasmPaths().sort()) {
        if (
            patterns.includes(path) ||
            prefixes.some((prefix) => path.startsWith(prefix))
        )
            continue;
        console.error(
            `${pathsFile}: missing WASM dependency path ${JSON.stringify(path)}`,
        );
        process.exitCode = 1;
    }
}

function wasmPaths() {
    const { packages } = JSON.parse(
        execFileSync(
            "cargo",
            [
                "metadata",
                "--no-deps",
                "--format-version",
                "1",
                "--locked",
                "--offline",
            ],
            { cwd: resolve(root, "rust"), encoding: "utf8" },
        ),
    );
    const byName = new Map(packages.map((pkg) => [pkg.name, pkg]));
    const byDirectory = new Map(
        packages.map((pkg) => [dirname(pkg.manifest_path), pkg]),
    );
    const pending = [];
    for (const path of globSync("web/packages/wasm/*/package.json", {
        cwd: root,
    })) {
        const { name } = readJSON(resolve(root, path));
        const pkg = byName.get(name);
        if (!pkg)
            throw new Error(`${path}: no matching Cargo package for ${name}`);
        pending.push(dirname(pkg.manifest_path));
    }
    if (!pending.length) throw new Error("No Web WASM packages found");

    const directories = new Set();
    while (pending.length) {
        const directory = pending.pop();
        if (directories.has(directory)) continue;
        directories.add(directory);
        const pkg = byDirectory.get(directory);
        if (!pkg)
            throw new Error(
                `Local dependency ${directory} is outside the Rust workspace`,
            );
        for (const dependency of pkg.dependencies) {
            if (dependency.kind !== "dev" && dependency.path)
                pending.push(dependency.path);
        }
    }
    return [
        "rust/Cargo.lock",
        "rust/Cargo.toml",
        ...[...directories].map((dir) => `${relative(root, dir)}/**`),
    ];
}

function readJSON(path) {
    return JSON.parse(readFileSync(path, "utf8"));
}
