const crypto = require("node:crypto");
const fs = require("node:fs");
const fsp = require("node:fs/promises");
const path = require("node:path");

const vipsVersion = "8.18.7-1";

const vipsAssets = {
    "linux-x64": {
        name: "vips-x64",
        sha256: "23080fc90f113d3689d6c50e6e8c1f3f080813242c109d2b720fee002153f034",
        size: 19507632,
    },
    "linux-arm64": {
        name: "vips-arm64",
        sha256: "6c8f9c7d33a3995acda6d63e3aed1ddd4fb353217b63a7b17fa73debb0a6b111",
        size: 18719728,
    },
    "win32-x64": {
        name: "vips-x86_64.exe",
        sha256: "91f5b1299b59452cff1762e7f4b1700fc4fd096306af76af1df394238265ff0b",
        size: 31219200,
    },
    "win32-arm64": {
        name: "vips-aarch64.exe",
        sha256: "3dce2a96420d908903d685b4a4efd525a71b6eed7cfa2c54787a4185dea3e40b",
        size: 21212672,
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
