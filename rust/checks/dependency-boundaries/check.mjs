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
const apps = resolve(root, "rust/apps");
const bindings = resolve(root, "rust/bindings");
const crates = resolve(root, "rust/crates");
const framework =
    /^(?:wasm-bindgen(?:-.*)?|js-sys|web-sys|serde-wasm-bindgen|tsify(?:-.*)?|flutter_rust_bridge(?:_.*)?|uniffi(?:_.*)?|napi(?:-.*)?)$/;
const pathFromRoot = (path) => relative(root, path).split(sep).join("/");
const domain = metadata.packages.filter((pkg) =>
    pathFromRoot(pkg.manifest_path).startsWith("rust/crates/"),
);

const httpOwners = sorted("httpOwners", [
    "rust/apps/cli/Cargo.toml",
    "rust/crates/assets/Cargo.toml",
    "rust/crates/core/Cargo.toml",
    "rust/tools/location-dataset/Cargo.toml",
]);
const cryptoOwner = "rust/crates/core/Cargo.toml";
const cryptoExceptions = sorted("cryptoExceptions", [
    "hkdf rust/crates/ensu-crypto/Cargo.toml",
    "hmac rust/crates/legacy/Cargo.toml",
    "srp rust/crates/accounts/Cargo.toml",
]);
const cryptoName =
    /^(?:aes|argon2|bcrypt|chacha|crypto[-_]|curve25519|ecdsa|ed25519|hkdf|hmac|hpke|kyber|libcrux|ml-kem|p256|pbkdf|poly1305|salsa|scrypt|secp256|sodium|x25519|ring$|srp$)/;

for (const pkg of metadata.packages) {
    const manifest = pathFromRoot(pkg.manifest_path);
    for (const { name, path } of pkg.dependencies) {
        if (name === "reqwest" && !httpOwners.has(manifest)) {
            console.error(
                `${manifest}: use ente-core::http instead of a direct reqwest dependency`,
            );
            process.exitCode = 1;
        }
        if (
            cryptoName.test(name) &&
            !inside(crates, path) &&
            manifest !== cryptoOwner &&
            !cryptoExceptions.has(`${name} ${manifest}`)
        ) {
            console.error(
                `${manifest}: ${name} is a cryptographic dependency; use ente-core::crypto`,
            );
            process.exitCode = 1;
        }
    }
}

if (!domain.length) {
    console.error(`${resolve(root, "rust/crates")}: found no domain crates`);
    process.exitCode = 1;
}

for (const pkg of domain) {
    const manifest = pathFromRoot(pkg.manifest_path);
    for (const dependency of pkg.dependencies) {
        if (inside(apps, dependency.path)) {
            console.error(
                `${manifest}: dependency ${JSON.stringify(dependency.name)} crosses the Rust app boundary`,
            );
            process.exitCode = 1;
        }
        if (
            manifest === "rust/crates/core/Cargo.toml" &&
            inside(crates, dependency.path) &&
            !(
                dependency.kind === "dev" &&
                dependency.path === resolve(crates, "test-support")
            )
        ) {
            console.error(
                `${manifest}: ente-core must not depend on other domain crates (${dependency.name})`,
            );
            process.exitCode = 1;
        }
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

function sorted(name, values) {
    if (values.some((value, i) => i > 0 && values[i - 1] > value)) {
        throw new Error(`${name} must be sorted`);
    }
    return new Set(values);
}

function inside(directory, path) {
    if (!path) return false;
    const local = relative(directory, path);
    return (
        local !== ".." && !local.startsWith(`..${sep}`) && !isAbsolute(local)
    );
}
