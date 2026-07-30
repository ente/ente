/**
 * [Note: ONNX Runtime binaries]
 *
 * The Rust ML addon (see [Note: ML with Rust]) loads ONNX Runtime dynamically
 * at runtime. We use Ente's pinned custom builds — CoreML-enabled on macOS and
 * WebGPU-capable elsewhere — published at
 * https://github.com/laurens-pilot/ort-packaging/releases
 *
 * This script is the only place that downloads those builds. Postinstall runs
 * it once to acquire both architectures for the host platform. The extracted
 * libraries are kept under `node_modules/.cache/ente-onnxruntime/`, where the
 * development app loads them directly.
 *
 * During packaging, `beforeBuild.js` calls {@link stageONNXRuntime} to copy the
 * already-installed libraries needed by the current target into
 * `build/onnxruntime/`. That step performs no network access.
 */

const crypto = require("node:crypto");
const fsp = require("node:fs/promises");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const ortVersion = "1.27.0-r4";

const ortReleaseURL = `https://github.com/laurens-pilot/ort-packaging/releases/download/ort-${ortVersion}`;

/**
 * SHA-256 checksums of the release assets, pinned here so that the library we
 * package cannot change without a corresponding (reviewed) change to this
 * file. When bumping {@link ortVersion}, update these with the values from the
 * release's `.sha256` sidecar files after verifying them against the built
 * archives.
 */
const ortAssetSHA256s = {
    "darwin-arm64":
        "dbb243c3b43963fda6c9475a978d0954b69490d386bc3ecb54a471b2a13ba043",
    "darwin-x64":
        "d655686380c1976a9067a48d82645a381e4bc4bdfcc44c88f300befc24c4ae8e",
    "linux-arm64":
        "0b0367bddd96fb0263781022f715ec531a9856e14d8ed91beea80da8d9bb6a2e",
    "linux-x64":
        "d417b8d92498f3e754e23fbeac0751f13375061c6c31cc83e869f33a37fca8ad",
    "win32-arm64":
        "9e3179a985e08700b37f15af7049bca4fc007cb4d5a7e2ff1d81df10e330544e",
    "win32-x64":
        "0534f35981fe3174379c7e80f93977edd990ce67c40f6cbdde1e6890eb798911",
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

/** Download and extract one pinned ONNX Runtime build, if it is not current. */
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
    // tar is available on all the platforms we build on (bsdtar on macOS and
    // Windows, GNU tar on Linux), and handles both .tar.gz and .zip.
    execFileSync("tar", ["-xf", asset], { cwd: outDir });
    await fsp.rm(archivePath);
    await fsp.writeFile(stampPath, asset);
};

/**
 * Copy the already-installed ONNX Runtime libraries required by a build target
 * into the resources staging directory. This deliberately never downloads.
 */
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

/** Acquire every architecture needed by desktop packaging on this platform. */
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
