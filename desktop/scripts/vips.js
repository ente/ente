const crypto = require("node:crypto");
const fs = require("node:fs");
const fsp = require("node:fs/promises");
const path = require("node:path");

const vipsVersion = "8.18.7";

const vipsAssets = {
    "linux-x64": {
        name: "vips-x64",
        sha256: "4ae75c23c74537e12e1c1a009f1c46a0fb71ca1df435601a89994b3611f28b72",
        size: 19536800,
    },
    "linux-arm64": {
        name: "vips-arm64",
        sha256: "cb86d43a90eb5c5485c692198fe2a33aa20497566e658c31297c3a944d68ddcc",
        size: 18720208,
    },
    "win32-x64": {
        name: "vips-x86_64.exe",
        sha256: "4be37eaf58ccc4a40774de4e12e6293a086878f1bc9b0ce8bfcef7181fe666e7",
        size: 31252992,
    },
    "win32-arm64": {
        name: "vips-aarch64.exe",
        sha256: "5df2275a63969d0e87efe0162f18f5a80dec34ebdf5bcccc3cb74efb25f8e06d",
        size: 21235712,
    },
};

const fileSHA256 = async (file) => {
    const hash = crypto.createHash("sha256");
    for await (const chunk of fs.createReadStream(file)) hash.update(chunk);
    return hash.digest("hex");
};

const downloadVipsIfNeeded = async (asset, out) => {
    try {
        const stat = await fsp.lstat(out);
        if (
            stat.isFile() &&
            stat.size == asset.size &&
            (await fileSHA256(out)) == asset.sha256
        ) {
            await fsp.chmod(out, "744");
            return;
        }
    } catch (e) {
        if (e.code != "ENOENT") throw e;
    }

    console.log(`Downloading ${asset.name}`);
    const res = await fetch(
        `https://github.com/ente/libvips-packaging/releases/download/v${vipsVersion}/${asset.name}`,
    );
    if (!res.ok)
        throw new Error(`Failed to download ${asset.name}: HTTP ${res.status}`);

    await fsp.mkdir(path.dirname(out), { recursive: true });
    const tempDir = await fsp.mkdtemp(path.join(path.dirname(out), ".vips-"));
    try {
        const tempFile = path.join(tempDir, "vips");
        const file = await fsp.open(tempFile, "wx", 0o600);
        const hash = crypto.createHash("sha256");
        let size = 0;
        try {
            for await (const chunk of res.body) {
                size += chunk.length;
                if (size > asset.size)
                    throw new Error(
                        `Download of ${asset.name} exceeds its pinned size`,
                    );
                hash.update(chunk);
                await file.writeFile(chunk);
            }
        } finally {
            await file.close();
        }
        if (size != asset.size)
            throw new Error(
                `Unexpected download size for ${asset.name}: ${size}`,
            );
        const actual = hash.digest("hex");
        if (actual != asset.sha256)
            throw new Error(
                `SHA-256 mismatch for ${asset.name}: expected ${asset.sha256}, got ${actual}`,
            );

        await fsp.chmod(tempFile, "744");
        await fsp.rename(tempFile, out);
    } finally {
        await fsp.rm(tempDir, { recursive: true, force: true });
    }
};

const ensureVips = async (platform, arch, appDir) => {
    // macOS uses sips.
    if (platform == "darwin") return;

    const asset = vipsAssets[`${platform}-${arch}`];
    if (!asset)
        throw new Error(`Unsupported libvips target: ${platform}-${arch}`);
    const out = path.join(
        appDir,
        "build",
        platform == "win32" ? "vips.exe" : "vips",
    );
    await downloadVipsIfNeeded(asset, out);
};

module.exports = { ensureVips };

if (require.main === module)
    ensureVips(
        process.platform,
        process.arch,
        path.resolve(__dirname, ".."),
    ).catch((e) => {
        console.error(e);
        process.exit(1);
    });
