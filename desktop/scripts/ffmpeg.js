const crypto = require("node:crypto");
const { createReadStream } = require("node:fs");
const fs = require("node:fs/promises");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const StreamZip = require("node-stream-zip");

const release = "9.0.2";
const checksums = {
    "darwin-universal": {
        archive:
            "ba2f10d5433ae4b22f482ea2cee85d50819455e1e63b5aa1ecf6201ad2f2b7c9",
        ffmpeg: "1fc24088a740634a52d7a74bc90fa8178778ba38451f156f32fb3540af6eb70b",
        ffprobe:
            "ce7c0146fbd67abe36a24ed7bb52f1cc581bff5421714f81ad88328c49650cd6",
    },
    "linux-x64": {
        archive:
            "7cf14c99d674d5f2ad2897f83f2b00307f66dba6c2f4fa854601a0521bc47886",
        ffmpeg: "b45af6ffd68a62e4265bc71aeef4f5aa2708682dc4d540c9d3ef9a2308745c70",
        ffprobe:
            "38b4b2a0839930c7ebfdcf11327b1e2b359e70135389134f160aed41352547ef",
    },
    "linux-arm64": {
        archive:
            "00dd72f0f0ac4805d90b3c01a667909f04d6f821f90189791e1dea59cf8507ba",
        ffmpeg: "332e0978b77b74cac50d7243458b4f894b04404f845c5104a40dc9bfb7040c69",
        ffprobe:
            "57d187e0937c5aad150da819d50adcba057fbdd30532e6d3bf447eb9c9edeacc",
    },
    "windows-x64": {
        archive:
            "0d772b1676871c480a8f140c45507c68e3077013d42792088c8db55f1611aba2",
        ffmpeg: "1576d072c63730c353b96bc47f4436ecbf64b4cad05cde9e97926ffd2f7a6c6d",
        ffprobe:
            "a90b435381118dd1c1232608ee76fe995ffc3c53179ac2acb89869f50e79b15b",
    },
    "windows-arm64": {
        archive:
            "4f6df97fcd471adeac97079e271617e0fee322610faeca89f6590c323a5af654",
        ffmpeg: "82c270d2119c68b6f6f409ce1b0a5200cdcc9bef4c5fa4f6f4b0ee60c605e8ca",
        ffprobe:
            "13108f929ff858a7e06530338a9eeecc0b9226b908a1c5631ce14b417fb2fdca",
    },
};

const fileSHA256 = async (file) => {
    const hash = crypto.createHash("sha256");
    for await (const chunk of createReadStream(file)) hash.update(chunk);
    return hash.digest("hex");
};

const ensureFFmpeg = async (platform, arch, appDir) => {
    const target =
        platform == "darwin"
            ? "darwin-universal"
            : `${platform == "win32" ? "windows" : platform}-${arch}`;
    const expected = checksums[target];
    if (!expected) throw new Error(`No pinned FFmpeg archive for ${target}`);

    const out = path.join(appDir, "build", "ffmpeg");
    const stamp = path.join(out, ".archive-sha256");
    const binaries = ["ffmpeg", "ffprobe"].map((name) => ({
        name: platform == "win32" ? `${name}.exe` : name,
        sha256: expected[name],
    }));
    try {
        if ((await fs.readFile(stamp, "utf8")) == expected.archive) {
            const valid = await Promise.all(
                binaries.map(async ({ name, sha256 }) => {
                    const file = path.join(out, name);
                    return (
                        (await fs.lstat(file)).isFile() &&
                        (await fileSHA256(file)) == sha256
                    );
                }),
            );
            if (valid.every(Boolean)) {
                await Promise.all(
                    binaries.map(({ name }) =>
                        fs.chmod(path.join(out, name), 0o755),
                    ),
                );
                return;
            }
        }
    } catch (e) {
        if (e.code != "ENOENT") throw e;
    }

    const asset = `${target}-ffmpeg.${platform == "win32" ? "zip" : "tar.gz"}`;
    console.log(`Downloading ${asset} (${release})`);
    const response = await fetch(
        `https://github.com/ente/ffmpeg-packaging/releases/download/${release}/${asset}`,
    );
    if (!response.ok)
        throw new Error(`Failed to download ${asset}: HTTP ${response.status}`);
    const archive = Buffer.from(await response.arrayBuffer());
    const actual = crypto.createHash("sha256").update(archive).digest("hex");
    if (actual != expected.archive)
        throw new Error(`SHA-256 mismatch for ${asset}: ${actual}`);

    await fs.mkdir(path.dirname(out), { recursive: true });
    const stage = await fs.mkdtemp(path.join(path.dirname(out), ".ffmpeg-"));
    try {
        const archivePath = path.join(stage, asset);
        await fs.writeFile(archivePath, archive);
        if (platform == "win32") {
            const zip = new StreamZip.async({ file: archivePath });
            try {
                await zip.extract(null, stage);
            } finally {
                await zip.close();
            }
        } else {
            execFileSync("tar", ["-xf", archivePath, "-C", stage]);
        }
        await fs.unlink(archivePath);
        for (const { name } of binaries)
            await fs.chmod(path.join(stage, name), 0o755);
        await fs.writeFile(
            path.join(stage, ".archive-sha256"),
            expected.archive,
        );
        await fs.rm(out, { recursive: true, force: true });
        await fs.rename(stage, out);
    } finally {
        await fs.rm(stage, { recursive: true, force: true });
    }
};

module.exports = { ensureFFmpeg };

if (require.main === module)
    ensureFFmpeg(
        process.platform,
        process.arch,
        path.resolve(__dirname, ".."),
    ).catch((e) => {
        console.error(e);
        process.exit(1);
    });
