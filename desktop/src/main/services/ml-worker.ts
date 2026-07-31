/**
 * @file ML related tasks. This code runs in a utility process.
 *
 * The ML pipeline itself — image decode, preprocessing, ONNX inference and
 * postprocessing — is implemented by the Rust crate shared with the mobile
 * apps, and reaches us via a Node native addon (see [Note: ML with Rust]).
 * This file loads the addon and forwards requests that arrive from the web
 * layer over our MessagePort. The addon downloads the models through the
 * shared Rust asset store.
 */

// See [Note: Using Electron APIs in UtilityProcess] about what we can and
// cannot import.

import { expose } from "comlink";
import path from "node:path";
import { z } from "zod";
import log from "../log-worker";
import { messagePortMainEndpoint } from "../utils/comlink";
import { wait } from "../utils/common";
import { fsStatMtime } from "./fs";

// The addon is loaded at runtime from the path the main process gives us, so
// this import is used only for its types (it resolves to the generated
// `rust-bindings/index.d.ts`).
import type * as MLNativeModule from "../../../rust-bindings";
import type { MLNativePaths } from "./ml-native";

log.debugString("Started ML utility process");

process.on("uncaughtException", (e, origin) => log.error(origin, e));

process.parentPort.once("message", (e) => {
    // Initialize ourselves with the data we got from our parent.
    const { mlNativePaths } = parseInitData(e.data);
    loadMLNative(mlNativePaths);
    if (_native) void warmUpClipTextEncoder(_native);
    // Expose an instance of `ElectronMLWorker` on the port we got from our
    // parent.
    expose(
        {
            fsStatMtime,
            analyzeImage,
            releaseMLRuntime,
            computeCLIPTextEmbeddingIfAvailable,
        },
        messagePortMainEndpoint(e.ports[0]!),
    );
});

/**
 * We cannot access Electron's {@link app} object within a utility process, so
 * we pass the value of `app.getPath("userData")` during initialization, and it
 * can be subsequently retrieved from here.
 */
let _userDataPath: string | undefined;

/** Equivalent to app.getPath("userData") */
const userDataPath = () => _userDataPath!;

const MLWorkerInitData = z.object({
    userDataPath: z.string(),
    mlNativePaths: z.object({
        addon: z.string(),
        onnxRuntimeLibrary: z.string(),
    }),
});

const parseInitData = (data: unknown) => {
    const initData = MLWorkerInitData.parse(data);
    _userDataPath = initData.userDataPath;
    return initData;
};

type MLNative = typeof MLNativeModule;

type MLWorkerAnalyzeImageErrorKind = "init" | "ort" | "image" | "misc";

interface MLWorkerAnalyzeImageError {
    kind: MLWorkerAnalyzeImageErrorKind;
    message: string;
}

type MLWorkerAnalyzeImageResponse =
    | { ok: true; result: MLNativeModule.AnalyzeImageResult }
    | { ok: false; error: MLWorkerAnalyzeImageError };

class CategorizedMLWorkerError extends Error {
    constructor(
        public readonly kind: MLWorkerAnalyzeImageErrorKind,
        message: string,
    ) {
        super(message);
        this.name = "CategorizedMLWorkerError";
    }
}

let _native: MLNative | undefined;
let _assetStore: MLNativeModule.AssetStore | undefined;
let _nativeLoadError: string | undefined;

/**
 * Load the Rust ML addon and point it at the ONNX Runtime library.
 *
 * A failure here (e.g. an OS version too old for the ONNX Runtime build) is
 * not fatal to the app: we remember the error, and all subsequent ML requests
 * fail with it, leaving the rest of the app functional.
 */
const loadMLNative = (paths: MLNativePaths) => {
    try {
        // eslint-disable-next-line @typescript-eslint/no-require-imports
        const native = require(paths.addon) as MLNative;
        native.initOrt(paths.onnxRuntimeLibrary);
        // Enables the guarded WebGPU path on Linux and Windows. This is a
        // no-op on macOS, where CoreML remains the preferred provider.
        native.setMlExecutionConfig(true);
        _assetStore = new native.AssetStore(
            path.join(userDataPath(), "assets"),
            path.join(userDataPath(), "models"),
        );
        _native = native;
    } catch (e) {
        _nativeLoadError = e instanceof Error ? e.message : String(e);
        log.error(`Failed to load ML addon at ${paths.addon}`, e);
    }
};

/**
 * Return the loaded addon, throwing if it (or the ONNX Runtime library it
 * needs) could not be loaded on this machine.
 */
const mlNative = () => {
    if (_native) return _native;
    throw new CategorizedMLWorkerError(
        "init",
        `ML is unavailable: ${_nativeLoadError ?? "not loaded"}`,
    );
};

const assetStore = () => {
    if (_assetStore) return _assetStore;
    throw new CategorizedMLWorkerError(
        "init",
        `ML is unavailable: ${_nativeLoadError ?? "asset store not loaded"}`,
    );
};

/**
 * Drain the runtime events (execution provider fallbacks, self-test failures)
 * buffered on the Rust side, writing each to our log at its severity.
 */
const logMLRuntimeEvents = (native: MLNative) => {
    for (const { severity, message } of native.takeMlRuntimeEvents()) {
        const s = `[ml-rt] ${message}`;
        if (severity == "severe") log.error(s);
        else if (severity == "warning") log.warn(s);
        else log.info(s);
    }
};

/**
 * The models needed for the indexing tasks enabled in the given request,
 * mapped to verified on-disk paths.
 *
 * Models for tasks that are not requested are left as empty strings, which
 * the Rust side treats as "not configured".
 */
const _indexingModelPaths = new Map<
    number,
    Promise<MLNativeModule.ModelPaths>
>();

const indexingModelPaths = (
    runFaces: boolean,
    runClip: boolean,
    runPets: boolean,
) => {
    const key =
        Number(runFaces) | (Number(runClip) << 1) | (Number(runPets) << 2);
    let promise = _indexingModelPaths.get(key);
    if (!promise) {
        promise = assetStore()
            .indexingModelPaths(runFaces, runClip, runPets)
            .catch((e: unknown) => {
                _indexingModelPaths.delete(key);
                throw e;
            });
        _indexingModelPaths.set(key, promise);
    }
    return promise;
};

/**
 * The model paths key for which the Rust runtime is currently prepared, if
 * any. Re-preparing with the same paths is skipped (the Rust side would
 * anyway no-op, this just avoids the IPC churn).
 */
let _preparedRuntimeKey: string | undefined;

const ensureMLRuntime = (
    native: MLNative,
    modelPaths: MLNativeModule.ModelPaths,
) => {
    const key = JSON.stringify(modelPaths);
    if (_preparedRuntimeKey == key) return;
    native.initMlRuntime(modelPaths);
    _preparedRuntimeKey = key;
};

/**
 * Release the (pinned) Rust ML runtime sessions. Called by the web layer when
 * indexing goes idle so that we don't hold on to the session memory.
 */
export const releaseMLRuntime = () => {
    if (!_native) return;
    _native.releaseMlRuntime();
    _preparedRuntimeKey = undefined;
    logMLRuntimeEvents(_native);
};

/**
 * The request the web layer sends us to analyze a single image. Mirrors (a
 * subset of) the addon's own request, except the image source, which we
 * convert to what the addon expects.
 */
export interface MLWorkerAnalyzeImageRequest {
    fileID: number;
    /** Path to the image on the local filesystem. */
    path?: string | undefined;
    /** The encoded image bytes (used when there is no local file). */
    bytes?: Uint8Array | undefined;
    runFaces: boolean;
    runClip: boolean;
    runPets: boolean;
    generateFaceCrops: boolean;
}

/**
 * Analyze a single image with the Rust ML pipeline, downloading any needed
 * models first.
 *
 * If the Rust side reports the on-disk model as corrupt, delete and
 * redownload it, and retry once.
 */
export const analyzeImage = async (
    req: MLWorkerAnalyzeImageRequest,
): Promise<MLWorkerAnalyzeImageResponse> => {
    try {
        return { ok: true, result: await analyzeImageOrThrow(req) };
    } catch (e) {
        return { ok: false, error: categorizeAnalyzeImageError(e) };
    }
};

const analyzeImageOrThrow = async (req: MLWorkerAnalyzeImageRequest) => {
    const native = mlNative();
    try {
        return await analyzeImageOnce(native, req);
    } catch (e) {
        if (!evictModelIfReportedCorrupt(e)) throw e;
        _preparedRuntimeKey = undefined;
        return await analyzeImageOnce(native, req);
    } finally {
        logMLRuntimeEvents(native);
    }
};

const categorizeAnalyzeImageError = (e: unknown): MLWorkerAnalyzeImageError => {
    if (e instanceof CategorizedMLWorkerError) {
        return { kind: e.kind, message: e.message };
    }

    const message = e instanceof Error ? e.message : String(e);
    const kind: MLWorkerAnalyzeImageErrorKind =
        message.startsWith("Decode: ") || message.startsWith("Image: ")
            ? "image"
            : message.startsWith("Ort: ") ||
                message.startsWith("CorruptModel: ") ||
                message.startsWith("Runtime: ")
              ? "ort"
              : "misc";
    return { kind, message };
};

const analyzeImageOnce = async (
    native: MLNative,
    req: MLWorkerAnalyzeImageRequest,
) => {
    let source;
    if (req.path !== undefined) {
        source = { imagePath: req.path };
    } else if (req.bytes) {
        source = { imageBytes: uint8ArrayToBuffer(req.bytes) };
    } else {
        throw new Error("The analyze request has neither a path nor bytes");
    }

    const modelPaths = await indexingModelPaths(
        req.runFaces,
        req.runClip,
        req.runPets,
    );
    ensureMLRuntime(native, modelPaths);
    return await native.analyzeImage({
        fileId: req.fileID,
        ...source,
        runFaces: req.runFaces,
        runClip: req.runClip,
        runPets: req.runPets,
        generateFaceCrops: req.generateFaceCrops,
        modelPaths,
    });
};

/**
 * If {@link e} is the addon's tagged "CorruptModel" error, return the path of
 * the corrupt model file it reports.
 */
const corruptModelPathFromError = (e: unknown) => {
    if (!(e instanceof Error)) return undefined;
    if (!e.message.startsWith("CorruptModel: ")) return undefined;
    return e.message.slice("CorruptModel: ".length).trim();
};

/**
 * If {@link e} is the addon's tagged "CorruptModel" error, evict the model it
 * names so that its next use downloads a fresh copy, and return `true`.
 */
const evictModelIfReportedCorrupt = (e: unknown) => {
    const corruptModelPath = corruptModelPathFromError(e);
    if (!corruptModelPath) return false;
    if (!assetStore().removeModel(corruptModelPath)) return false;
    _indexingModelPaths.clear();
    log.error(
        `Rust ML reported a corrupt model at ${corruptModelPath}, evicting it so that it gets redownloaded`,
    );
    _clipTextModelPaths = undefined;
    return true;
};

// Zero-copy view over the transferred bytes.
const uint8ArrayToBuffer = (bytes: Uint8Array) =>
    Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength);

let _clipTextModelPaths: Promise<MLNativeModule.ClipTextModelPaths> | undefined;

const clipTextModelPaths = () =>
    (_clipTextModelPaths ??= assetStore()
        .clipTextModelPaths()
        .catch((e: unknown) => {
            _clipTextModelPaths = undefined;
            throw e;
        }));

/**
 * Run a throwaway CLIP text query so that the Rust side builds and caches the
 * text encoder session before the user's first search. Mirrors the mobile
 * app's warm up (see ml_computer.dart).
 *
 * Best effort - on failure, queries build the session on demand as before.
 */
const warmUpClipTextEncoder = async (native: MLNative) => {
    try {
        const { modelPath, vocabPath } = await clipTextModelPaths();
        await native.runClipText({
            text: "warm up text encoder",
            modelPath,
            vocabPath,
        });
    } catch (e) {
        if (!evictModelIfReportedCorrupt(e))
            log.warn("Failed to warm up the CLIP text encoder", e);
    } finally {
        logMLRuntimeEvents(native);
    }
};

/**
 * Compute CLIP embeddings for a text snippet, if the model is available.
 *
 * The embedding is computed by the Rust pipeline (which also handles the
 * tokenization). If the model (or the addon itself) is not available yet, we
 * return `undefined` instead of blocking the caller on the download.
 */
export const computeCLIPTextEmbeddingIfAvailable = async (text: string) => {
    if (!_native) return undefined;
    const native = _native;

    const pathsOrSkip = await Promise.race([
        clipTextModelPaths(),
        // Wait a bit for the models to resolve the first time this code runs
        // on each app start (when they're already downloaded, resolving them
        // is quick), but don't block on a download.
        wait(50).then(() => 1 as const),
    ]);

    if (typeof pathsOrSkip == "number") {
        log.info(
            "Ignoring CLIP text embedding request because model download is pending",
        );
        return undefined;
    }

    const { modelPath, vocabPath } = pathsOrSkip;
    try {
        const { embedding } = await native.runClipText({
            text,
            modelPath,
            vocabPath,
        });
        return embedding;
    } catch (e) {
        // Don't block this query on the redownload; a subsequent query will
        // pick up the fresh copy.
        if (!evictModelIfReportedCorrupt(e)) throw e;
        return undefined;
    } finally {
        logMLRuntimeEvents(native);
    }
};
