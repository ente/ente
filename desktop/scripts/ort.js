const crypto = require("node:crypto");
const fsp = require("node:fs/promises");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const ortVersion = "1.31.0-r1";

// Our packaging enables CoreML on macOS and WebGPU elsewhere.
const ortReleaseURL = `https://github.com/ente/ort-packaging/releases/download/ort-${ortVersion}`;

// When changing ortVersion, verify the archives and update these from the
// release's .sha256 sidecars.
const ortAssetSHA256s = {
    "darwin-arm64":
        "287567756b9aa6aae1a8a0cb85f5deaf5bd30e9a14a33a8dd0def569e773542f",
    "darwin-x64":
        "26f8d498f103795b2a7eaf865827670cae7420f77ba138575b5aa291224a80ee",
    "linux-arm64":
        "98d35a7f3240ffe96af478bf0e0d05c7febeed53cf968d13ca5b0dc15eb15aaa",
    "linux-x64":
        "7d634d98b5eaaca72ee27c306c82f1dd9f32b3139ae6bb8ddfeaec429afc21fd",
    "win32-arm64":
        "024870ea204767cf712ea76a03af7d65e25b3fa3cf94b8c5714ae1d726ed34d3",
    "win32-x64":
        "f582247d2bc903d57288bfc35b592187520bb9fa223b74953654003049c78d00",
};

const ortAssetName = (platform, arch) => {
    switch (platform) {
        case "darwin":
            return `onnxruntime-coreml-macos-${arch}-${ortVersion}.tar.gz`;
        case "linux":
            return `onnxruntime-webgpu-linux-${arch}-${ortVersion}.tar.gz`;
        case "win32":
            return `onnxruntime-webgpu-windows-${arch}-${ortVersion}.zip`;
        default:
            throw new Error(`Unsupported platform: ${platform}`);
    }
};

const archesForTarget = (platform, arch) =>
    platform == "darwin" ? ["arm64", "x64"] : [arch];

const installDir = (appDir) =>
    path.join(appDir, "node_modules", ".cache", "ente-onnxruntime");

const downloadONNXRuntimeIfNeeded = async (platform, arch, appDir) => {
    const asset = ortAssetName(platform, arch);
    const outDir = path.join(installDir(appDir), arch);
    const stampPath = path.join(outDir, ".ente-ort-stamp");

    try {
        if ((await fsp.readFile(stampPath, "utf8")) == asset) return;
    } catch {}

    const expected = ortAssetSHA256s[`${platform}-${arch}`];
    if (!expected) throw new Error(`No pinned SHA-256 for ${platform}-${arch}`);

    console.log(`Downloading ${asset}`);
    const res = await fetch(`${ortReleaseURL}/${asset}`);
    if (!res.ok)
        throw new Error(`Failed to download ${asset}: HTTP ${res.status}`);
    const archive = Buffer.from(await res.arrayBuffer());

    const actual = crypto.createHash("sha256").update(archive).digest("hex");
    if (actual != expected)
        throw new Error(
            `SHA-256 mismatch for ${asset}: expected ${expected}, got ${actual}`,
        );

    await fsp.rm(outDir, { recursive: true, force: true });
    await fsp.mkdir(outDir, { recursive: true });
    const archivePath = path.join(outDir, asset);
    await fsp.writeFile(archivePath, archive);
    // Windows ships bsdtar, which also extracts zip archives.
    execFileSync("tar", ["-xf", asset], { cwd: outDir });
    await fsp.rm(archivePath);
    await fsp.writeFile(stampPath, asset);
};

const stageONNXRuntime = async (platform, arch, appDir) => {
    const arches = archesForTarget(platform, arch);
    const sourceRoot = installDir(appDir);
    const stageRoot = path.join(appDir, "build", "onnxruntime");

    for (const a of arches) {
        const expected = ortAssetName(platform, a);
        const stampPath = path.join(sourceRoot, a, ".ente-ort-stamp");
        let actual;
        try {
            actual = await fsp.readFile(stampPath, "utf8");
        } catch {
            throw new Error(
                `ONNX Runtime for ${platform}-${a} is not installed (run "npm run postinstall" first)`,
            );
        }
        if (actual != expected)
            throw new Error(
                `Installed ONNX Runtime for ${platform}-${a} is stale (run "npm run postinstall" again)`,
            );
    }

    await fsp.rm(stageRoot, { recursive: true, force: true });
    await fsp.mkdir(stageRoot, { recursive: true });
    for (const a of arches)
        await fsp.cp(path.join(sourceRoot, a), path.join(stageRoot, a), {
            recursive: true,
            verbatimSymlinks: true,
        });
};

const installONNXRuntime = async (platform, appDir) => {
    for (const arch of ["arm64", "x64"])
        await downloadONNXRuntimeIfNeeded(platform, arch, appDir);
};

const main = () => {
    const appDir = path.resolve(__dirname, "..");
    return installONNXRuntime(process.platform, appDir);
};

module.exports = { stageONNXRuntime };

if (require.main === module)
    main().catch((e) => {
        console.error(e);
        process.exit(1);
    });
