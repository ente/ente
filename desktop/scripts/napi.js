/**
 * [Note: Packaging the N-API addon]
 *
 * This script owns the two napi-rs operations used by desktop:
 *
 * - `node scripts/napi.js dts <typeDefDir> <outPath>` renders declarations
 *   emitted by the `cargo check` performed by `cargo codegen napi`.
 * - `node scripts/napi.js build` builds the host addon into the gitignored
 *   `rust-bindings/` directory for development.
 *
 * Packaging calls {@link stageNapiAddons} from `beforeBuild.js`. Every addon
 * build goes through {@link buildNapiAddon}, which always uses Cargo's
 * release profile. This script neither downloads nor installs ONNX Runtime;
 * that is owned by `ort.js` and postinstall.
 */

const fsp = require("node:fs/promises");
const path = require("node:path");
const { execFileSync, execSync } = require("node:child_process");

const archesForTarget = (platform, arch) =>
    platform == "darwin" ? ["arm64", "x64"] : [arch];

/** napi-cli's name for the addon built for the given platform-arch. */
const napiTriple = (platform, arch) => {
    switch (`${platform}-${arch}`) {
        case "darwin-arm64":
            return "darwin-arm64";
        case "darwin-x64":
            return "darwin-x64";
        case "linux-x64":
            return "linux-x64-gnu";
        case "linux-arm64":
            return "linux-arm64-gnu";
        case "win32-x64":
            return "win32-x64-msvc";
        case "win32-arm64":
            return "win32-arm64-msvc";
        default:
            throw new Error(`Unsupported platform-arch: ${platform}-${arch}`);
    }
};

/** The Rust target triple for the given platform-arch. */
const rustTriple = (platform, arch) => {
    switch (`${platform}-${arch}`) {
        case "darwin-arm64":
            return "aarch64-apple-darwin";
        case "darwin-x64":
            return "x86_64-apple-darwin";
        case "linux-x64":
            return "x86_64-unknown-linux-gnu";
        case "linux-arm64":
            return "aarch64-unknown-linux-gnu";
        case "win32-x64":
            return "x86_64-pc-windows-msvc";
        case "win32-arm64":
            return "aarch64-pc-windows-msvc";
        default:
            throw new Error(`Unsupported platform-arch: ${platform}-${arch}`);
    }
};

/** Install the given Rust target for the active toolchain if it is missing. */
const ensureRustTarget = (target, appDir) => {
    const installed = execFileSync(
        "rustup",
        ["target", "list", "--installed"],
        { cwd: appDir, encoding: "utf8" },
    ).split(/\r?\n/);
    if (installed.includes(target)) return;

    console.log(`Installing Rust target ${target}`);
    execFileSync("rustup", ["target", "add", target], {
        cwd: appDir,
        stdio: "inherit",
    });
};

/**
 * Build the addon for the given platform-arch into `rust-bindings/`.
 *
 * The build always runs so that edits to the Rust sources cannot be missed
 * when packaging; Cargo's incremental compilation makes this cheap when
 * nothing has changed. Linux always uses napi-cli's cross toolchain, including
 * for the host architecture, to keep the addon's glibc requirement at 2.17.
 */
const buildNapiAddon = async (appDir, platform, arch) => {
    if (arch != process.arch)
        ensureRustTarget(rustTriple(platform, arch), appDir);

    const addonPath = path.join(
        appDir,
        "rust-bindings",
        `index.${napiTriple(platform, arch)}.node`,
    );

    const cmd = [
        "npm exec -- napi build",
        "--manifest-path ../rust/bindings/napi/photos/Cargo.toml",
        "--target-dir ../rust/target",
        "--release --strip --platform --no-js",
        "--dts index.d.ts",
        "--output-dir rust-bindings",
        ...(platform == "linux" || arch != process.arch
            ? [
                  `--target ${rustTriple(platform, arch)}`,
                  ...(platform == "linux" ? ["--use-napi-cross"] : []),
              ]
            : []),
    ].join(" ");
    console.log(`> ${cmd}`);
    execSync(cmd, { cwd: appDir, stdio: "inherit" });

    await fsp.access(addonPath);
    return addonPath;
};

/**
 * Ensure the release addon(s) for a package target are built and staged into
 * `build/napi/`.
 */
const stageNapiAddons = async (appDir, platform, arch) => {
    // On macOS the packaged app is universal, so both architectures must be
    // staged regardless of which arch this build pass is for.
    const arches = archesForTarget(platform, arch);

    const stageDir = path.join(appDir, "build", "napi");
    await fsp.mkdir(stageDir, { recursive: true });

    const wanted = [];
    for (const a of arches) {
        const addonPath = await buildNapiAddon(appDir, platform, a);
        wanted.push(path.basename(addonPath));
        await fsp.copyFile(
            addonPath,
            path.join(stageDir, path.basename(addonPath)),
        );
    }

    // Remove addons staged by earlier passes for other platforms or
    // architectures so that they don't get copied into this package.
    for (const entry of await fsp.readdir(stageDir))
        if (!wanted.includes(entry))
            await fsp.rm(path.join(stageDir, entry), { recursive: true });
};

/** Render the napi macro output into the declaration file used by TypeScript. */
const renderTypeDefinitions = async (typeDefDir, outPath) => {
    const { generateTypeDef } = require("@napi-rs/cli");
    const { dts } = await generateTypeDef({ typeDefDir, cwd: process.cwd() });
    await fsp.writeFile(outPath, dts);
};

const main = async () => {
    const [command, ...args] = process.argv.slice(2);
    const appDir = path.resolve(__dirname, "..");

    switch (command) {
        case "build":
            if (args.length)
                throw new Error("usage: node scripts/napi.js build");
            await buildNapiAddon(appDir, process.platform, process.arch);
            return;
        case "dts": {
            const [typeDefDir, outPath] = args;
            if (!typeDefDir || !outPath || args.length != 2)
                throw new Error(
                    "usage: node scripts/napi.js dts <typeDefDir> <outPath>",
                );
            await renderTypeDefinitions(typeDefDir, outPath);
            return;
        }
        default:
            throw new Error(
                "usage: node scripts/napi.js <build|dts <typeDefDir> <outPath>>",
            );
    }
};

module.exports = { napiTriple, stageNapiAddons };

if (require.main === module)
    main().catch((e) => {
        console.error(e);
        process.exit(1);
    });
