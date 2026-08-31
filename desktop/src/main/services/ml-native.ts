import path from "node:path";
import { isDev } from "../utils/electron";

export interface MLNativePaths {
    addon: string;
    onnxRuntimeLibrary: string;
}

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
            return "libonnxruntime.1.28.1.dylib";
        case "linux":
            return "libonnxruntime.so.1.28.1";
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
