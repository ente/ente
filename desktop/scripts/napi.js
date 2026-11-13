const fsp = require("node:fs/promises");
const path = require("node:path");
const { execFileSync, execSync } = require("node:child_process");

const archesForTarget = (platform, arch) =>
    platform == "darwin" ? ["arm64", "x64"] : [arch];

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

const stageNapiAddons = async (appDir, platform, arch) => {
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

    for (const entry of await fsp.readdir(stageDir))
        if (!wanted.includes(entry))
            await fsp.rm(path.join(stageDir, entry), { recursive: true });
};

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
