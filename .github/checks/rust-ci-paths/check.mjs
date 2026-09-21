import { execFileSync } from "node:child_process";
import { globSync, readFileSync, realpathSync } from "node:fs";
import { dirname, relative, resolve } from "node:path";

const root = realpathSync(process.argv[2] ?? ".");
const pathsFile = ".github/scripts/ci/paths.json";
const workflows = readJSON(resolve(root, pathsFile));
const bindings = {
    "android-lint": "uniffi",
    "apple-lint": "uniffi",
    "desktop-lint": "napi",
    "mobile-lint": "frb",
};
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

for (const [workflow, patterns] of Object.entries(workflows)) {
    if (
        !["web-lint", "rust-cli-test"].includes(workflow) &&
        !bindings[workflow]
    )
        continue;
    if (patterns === null) continue;
    if (patterns.some((pattern) => pattern.startsWith("!"))) {
        throw new Error(
            `${pathsFile}: ${workflow} coverage does not support negated paths`,
        );
    }
    const roots = workflow === "web-lint" ? wasmRoots() : nativeRoots(workflow);
    // Literal directory prefixes prove coverage of future files too.
    const prefixes = patterns
        .filter((pattern) => /^[\w./-]+\/\*\*$/.test(pattern))
        .map((pattern) => pattern.slice(0, -2));
    const includeTests = ["mobile-lint", "rust-cli-test"].includes(workflow);
    for (const path of dependencyPaths(roots, includeTests).sort()) {
        if (
            patterns.includes(path) ||
            prefixes.some((prefix) => path.startsWith(prefix))
        )
            continue;
        console.error(
            `${pathsFile}: ${workflow} missing Rust dependency path ${JSON.stringify(path)}`,
        );
        process.exitCode = 1;
    }
}

function wasmRoots() {
    const pending = [];
    for (const path of globSync("web/packages/wasm/*/package.json", {
        cwd: root,
    })) {
        const { name, scripts } = readJSON(resolve(root, path));
        if (!scripts?.build) continue;
        const pkg = byName.get(name);
        if (!pkg)
            throw new Error(`${path}: no matching Cargo package for ${name}`);
        pending.push(dirname(pkg.manifest_path));
    }
    if (!pending.length) throw new Error("No Web WASM packages found");

    return pending;
}

function nativeRoots(workflow) {
    if (workflow === "rust-cli-test")
        return [resolve(root, "rust/apps/cli-next")];
    return [
        ...globSync(`rust/bindings/${bindings[workflow]}/*/Cargo.toml`, {
            cwd: root,
        }).map((path) => dirname(resolve(root, path))),
        resolve(root, "rust/tools/codegen"),
    ];
}

function dependencyPaths(pending, includeTests) {
    const tested = new Set(includeTests ? pending : []);
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
            if (
                dependency.path &&
                (dependency.kind !== "dev" || tested.has(directory))
            )
                pending.push(dependency.path);
        }
    }
    return [
        "rust/.cargo/config.toml",
        "rust/Cargo.lock",
        "rust/Cargo.toml",
        ...[...directories].map((dir) => `${relative(root, dir)}/**`),
    ];
}

function readJSON(path) {
    return JSON.parse(readFileSync(path, "utf8"));
}
