/**
 * @file Locations of the Rust ML addon and the ONNX Runtime library.
 *
 * This code runs in the main process; the resolved (absolute) paths are
 * passed to the ML utility process alongside the rest of its init data.
 *
 * [Note: ML with Rust]
 *
 * The ML indexing pipeline — image decode, preprocessing, ONNX inference,
 * postprocessing — is implemented by a Rust crate shared by all Ente clients
 * (rust/crates/photos). The desktop app talks to it through a Node native
 * addon (rust/bindings/napi/photos), which loads ONNX Runtime dynamically at
 * runtime from Ente's pinned custom builds (see [Note: ONNX Runtime binaries]
 * in scripts/ort.js).
 *
 * During development, `scripts/napi.js` (invoked by `npm run dev`) builds the
 * addon into the gitignored `rust-bindings/` directory, while ONNX Runtime is
 * loaded directly from the postinstall cache. When packaging, `beforeBuild.js`
 * stages both the addon and ONNX Runtime for the target architectures, and
 * electron-builder copies them into the app's resources directory.
 */

import path from "node:path";
import { isDev } from "../utils/electron";

/**
 * Absolute paths needed by the ML utility process to load the Rust addon.
 */
export interface MLNativePaths {
    /** The Node native addon (.node) with the Rust ML bindings. */
    addon: string;
    /** The ONNX Runtime dynamic library that the addon should load. */
    onnxRuntimeLibrary: string;
}

/**
 * The platform-arch triple that `napi build` uses when naming the built
 * addon for the current process' platform and architecture.
 */
const napiTriple = () => {
    switch (`${process.platform}-${process.arch}`) {
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
            throw new Error(
                `Unsupported platform-arch: ${process.platform}-${process.arch}`,
            );
    }
};

const onnxRuntimeLibraryName = () => {
    switch (process.platform) {
        case "darwin":
            return "libonnxruntime.1.27.0.dylib";
        case "linux":
            return "libonnxruntime.so.1.27.0";
        case "win32":
            return "onnxruntime.dll";
        default:
            throw new Error(`Unsupported platform: ${process.platform}`);
    }
};

export const mlNativePaths = (): MLNativePaths => {
    const addonName = `index.${napiTriple()}.node`;
    const addon = isDev
        ? path.resolve("rust-bindings", addonName)
        : path.join(process.resourcesPath, "napi", addonName);
    const onnxRuntimeRoot = isDev
        ? path.resolve("node_modules", ".cache", "ente-onnxruntime")
        : path.join(process.resourcesPath, "onnxruntime");
    const onnxRuntimeLibrary = path.join(
        onnxRuntimeRoot,
        process.arch,
        onnxRuntimeLibraryName(),
    );
    return { addon, onnxRuntimeLibrary };
};
