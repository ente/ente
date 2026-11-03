import { execFileSync } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import ort from "../../../../desktop/scripts/ort.js";

const appDir = fileURLToPath(new URL("../", import.meta.url));
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
for (const arch of arches)
    await ort.downloadONNXRuntimeIfNeeded(platform, arch, appDir);

const destination = path.join(appDir, "src-tauri", "onnxruntime");
await fs.rm(destination, { recursive: true, force: true });
await fs.mkdir(destination, { recursive: true });
const source = (arch) => path.join(ort.installDir(appDir), arch);
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
