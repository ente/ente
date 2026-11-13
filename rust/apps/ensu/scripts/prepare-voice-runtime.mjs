import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const appDir = fileURLToPath(new URL("../", import.meta.url));
const ortVersion = "1.31.0-r1";
const ortReleaseURL = `https://github.com/ente/ort-packaging/releases/download/ort-${ortVersion}`;
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

const target =
    process.env.TAURI_ENV_TARGET_TRIPLE ?? process.env.CARGO_BUILD_TARGET;
const platform = target?.includes("windows")
    ? "win32"
    : target?.includes("linux")
      ? "linux"
      : target?.includes("darwin")
        ? "darwin"
        : process.platform;
const arches =
    platform === "darwin"
        ? ["arm64", "x64"]
        : [
              target?.startsWith("aarch64")
                  ? "arm64"
                  : target?.startsWith("x86_64")
                    ? "x64"
                    : process.arch,
          ];
const assetPrefix = {
    darwin: "onnxruntime-coreml-macos",
    linux: "onnxruntime-webgpu-linux",
    win32: "onnxruntime-webgpu-windows",
}[platform];
const source = (arch) =>
    path.join(appDir, "node_modules", ".cache", "ente-onnxruntime", arch);

for (const arch of arches) {
    const expected = ortAssetSHA256s[`${platform}-${arch}`];
    if (!expected) throw new Error(`No pinned SHA-256 for ${platform}-${arch}`);
    const extension = platform === "win32" ? "zip" : "tar.gz";
    const asset = `${assetPrefix}-${arch}-${ortVersion}.${extension}`;
    const directory = source(arch);
    const stamp = path.join(directory, ".ente-ort-stamp");
    try {
        if ((await fs.readFile(stamp, "utf8")) === asset) continue;
    } catch {}

    console.log(`Downloading ${asset}`);
    const response = await fetch(`${ortReleaseURL}/${asset}`);
    if (!response.ok)
        throw new Error(`Failed to download ${asset}: HTTP ${response.status}`);
    const archive = Buffer.from(await response.arrayBuffer());
    const actual = createHash("sha256").update(archive).digest("hex");
    if (actual !== expected)
        throw new Error(
            `SHA-256 mismatch for ${asset}: expected ${expected}, got ${actual}`,
        );

    await fs.rm(directory, { recursive: true, force: true });
    await fs.mkdir(directory, { recursive: true });
    const archivePath = path.join(directory, asset);
    await fs.writeFile(archivePath, archive);
    execFileSync("tar", ["-xf", asset], { cwd: directory });
    await fs.rm(archivePath);
    await fs.writeFile(stamp, asset);
}

const destination = path.join(appDir, "src-tauri", "onnxruntime");
await fs.rm(destination, { recursive: true, force: true });
await fs.mkdir(destination, { recursive: true });
if (platform === "darwin") {
    execFileSync("lipo", [
        "-create",
        ...arches.map((arch) =>
            path.join(source(arch), "libonnxruntime.dylib"),
        ),
        "-output",
        path.join(destination, "libonnxruntime.dylib"),
    ]);
} else {
    const directory = path.join(destination, arches[0]);
    await fs.mkdir(directory, { recursive: true });
    const library =
        platform === "win32"
            ? /^onnxruntime(?:_providers_shared)?\.dll$/
            : /^libonnxruntime(?:_providers_shared)?\.so(?:\.\d+)*$/;
    for (const file of await fs.readdir(source(arches[0]), {
        recursive: true,
    })) {
        const name = path.basename(file);
        if (!library.test(name)) continue;
        await fs.cp(
            path.join(source(arches[0]), file),
            path.join(directory, name),
            { verbatimSymlinks: true },
        );
    }
}
for (const name of ["ONNXRUNTIME-LICENSE", "ThirdPartyNotices.txt"]) {
    await fs.copyFile(
        path.join(source(arches[0]), name),
        path.join(destination, name),
    );
}
