import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { isAbsolute, relative, resolve, sep } from "node:path";

const requestedRoot = resolve(process.argv[2]);
const metadata = JSON.parse(
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
        { cwd: resolve(requestedRoot, "rust"), encoding: "utf8" },
    ),
);
const root = resolve(metadata.workspace_root, "..");
const bindings = resolve(root, "rust/bindings");
const framework =
    /^(?:wasm-bindgen(?:-.*)?|js-sys|web-sys|serde-wasm-bindgen|tsify(?:-.*)?|flutter_rust_bridge(?:_.*)?|uniffi(?:_.*)?|napi(?:-.*)?)$/;
const pathFromRoot = (path) => relative(root, path).split(sep).join("/");
const domain = metadata.packages.filter((pkg) =>
    pathFromRoot(pkg.manifest_path).startsWith("rust/crates/"),
);

const httpOwners = new Set([
    "rust/apps/cli-next/Cargo.toml",
    "rust/crates/assets/Cargo.toml",
    "rust/crates/core/Cargo.toml",
    "rust/tools/location-dataset/Cargo.toml",
]);
if ([...httpOwners].some((path, i, paths) => i > 0 && paths[i - 1] > path)) {
    throw new Error("httpOwners must be sorted");
}

for (const pkg of metadata.packages) {
    const manifest = pathFromRoot(pkg.manifest_path);
    if (httpOwners.has(manifest)) continue;
    for (const dependency of pkg.dependencies) {
        if (dependency.name !== "reqwest") continue;
        console.error(
            `${manifest}: use ente-core::http instead of a direct reqwest dependency`,
        );
        process.exitCode = 1;
    }
}

if (!domain.length) {
    console.error(`${resolve(root, "rust/crates")}: found no domain crates`);
    process.exitCode = 1;
}

for (const pkg of domain) {
    const manifest = pathFromRoot(pkg.manifest_path);
    for (const dependency of pkg.dependencies) {
        if (
            !framework.test(dependency.name) &&
            !inside(bindings, dependency.path)
        )
            continue;
        console.error(
            `${manifest}: dependency ${JSON.stringify(dependency.name)} crosses the Rust binding boundary`,
        );
        process.exitCode = 1;
    }
}

const registered = new Set(
    domain.map((pkg) => pathFromRoot(pkg.manifest_path)),
);
for (const manifest of git(
    "ls-files",
    "--cached",
    "--others",
    "--exclude-standard",
    "-z",
    "--",
    "rust/crates/**/Cargo.toml",
)
    .split("\0")
    .filter((path) => path && existsSync(resolve(root, path)))) {
    if (registered.has(manifest)) continue;
    console.error(
        `${manifest}: domain crate is not registered in the Cargo workspace`,
    );
    process.exitCode = 1;
}

for (const path of git(
    "ls-files",
    "--cached",
    "--others",
    "--exclude-standard",
    "-z",
    "--",
    "rust/bindings/wasm/lib/src",
    "rust/bindings/frb/lib/src",
)
    .split("\0")
    .filter(
        (path) => path.endsWith(".rs") && existsSync(resolve(root, path)),
    )) {
    const source = readFileSync(resolve(root, path), "utf8");
    const declarations = [
        ...source.matchAll(
            /^\s*pub\s+(?:async\s+)?(?:struct|enum|type|fn)\s+([A-Za-z_][A-Za-z0-9_]*)/gm,
        ),
    ].map((match) => match[1]);
    const error = declarations.find((name) => name.endsWith("Error"));
    if (!error || declarations[0] === error) continue;
    console.error(
        `${path}: ${declarations[0]} precedes ${error}; put boundary errors before exported types and functions`,
    );
    process.exitCode = 1;
}

function git(...args) {
    return execFileSync("git", args, { cwd: root, encoding: "utf8" });
}

function inside(directory, path) {
    if (!path) return false;
    const local = relative(directory, path);
    return (
        local !== ".." && !local.startsWith(`..${sep}`) && !isAbsolute(local)
    );
}
