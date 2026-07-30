/**
 * @file ML related tasks. This code runs in a utility process.
 *
 * The ML pipeline itself — image decode, preprocessing, ONNX inference and
 * postprocessing — is implemented by the Rust crate shared with the mobile
 * apps, and reaches us via a Node native addon (see [Note: ML with Rust]).
 * This file downloads the models the pipeline needs, loads the addon, and
 * forwards requests that arrive from the web layer over our MessagePort.
 */

// See [Note: Using Electron APIs in UtilityProcess] about what we can and
// cannot import.

import { expose } from "comlink";
import { net } from "electron/main";
import { existsSync } from "fs";
import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import fs from "node:fs/promises";
import path from "node:path";
import { z } from "zod";
import log from "../log-worker";
import { messagePortMainEndpoint } from "../utils/comlink";
import { wait } from "../utils/common";
import { writeStream } from "../utils/stream";
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
 * The ML models (and the CLIP tokenizer vocabulary) used by the Rust
 * pipeline, identified by their name in the models.ente.com bucket. These are
 * the same assets that the mobile apps use (see ml_model_assets.dart).
 *
 * Fresh downloads are verified against the pinned SHA-256; copies already on
 * disk are revalidated with only a cheap size check (a corrupt model that
 * nevertheless retains the expected size gets caught by the Rust side, which
 * reports it back to us for eviction and redownload).
 */
const modelSpecs = {
    faceDetection: {
        name: "yolov5s_face_640_640_static_b1.onnx",
        byteSize: 32355091,
        sha256: "e047647409403d52696035ecd445792173e50d7fbdcccac97b958a585db9aa3d",
    },
    faceEmbedding: {
        name: "mobilefacenet_portable_static_b1.onnx",
        byteSize: 5278803,
        sha256: "0763fc33f54e138476194da95987e133b3e976075a6b1d3e1b2caedb251b1a36",
    },
    clipImage: {
        name: "mobileclip_s2_image_gelu_opset20.onnx",
        byteSize: 143057352,
        sha256: "205a430af825e501c5138e5bb9abea942482a7a4fd4a680e98e47cf0830dce7e",
    },
    clipText: {
        name: "mobileclip_s2_text_opset18_quant.onnx",
        byteSize: 67144712,
        sha256: "d92f33dfcff83077fc2e0d3414250710efbb51795dfd89767bdbefb5fdc47322",
    },
    clipTextVocab: {
        name: "bpe_simple_vocab_16e6.txt",
        byteSize: 3194984,
        sha256: "67603cfda2e032ad77b5f8808af37789d590db664b26df8705d2bf8b3c553fc8",
    },
    petFaceDetection: {
        name: "yolov5s_pet_face_fp16_V2.onnx",
        byteSize: 14758020,
        sha256: "7876d97992eeb5f3a9f3b35eff5e0e133012928172a8b005093108d8c3ad2d1c",
    },
    petFaceEmbeddingDog: {
        name: "dog_face_embedding128.onnx",
        byteSize: 4141071,
        sha256: "fb04d781eb1f7adf6ce3432dc0c5873f16cc051b5c98c14c754afb39e2b92462",
    },
    petFaceEmbeddingCat: {
        name: "cat_face_embedding128.onnx",
        byteSize: 4141071,
        sha256: "32b10694a27f6404d2beaddbd64f07ad555f72dccb12ee60a7afe5dcf6aad6cd",
    },
    petBodyDetection: {
        name: "yolov5s_object_fp16.onnx",
        byteSize: 14987107,
        sha256: "113f0c18632eb2c4f6deebcd40eb01c676492e9b43923c2d336e1b4012fce9ef",
    },
    petBodyEmbeddingDog: {
        name: "dog_body_embedding192.onnx",
        byteSize: 4569361,
        sha256: "1d85aa20358137e30f11c2d0baa9a2248b9997928d501fe15365d1fc57522770",
    },
    petBodyEmbeddingCat: {
        name: "cat_body_embedding192.onnx",
        byteSize: 4569361,
        sha256: "62fb5891e61be69a96510d8ec56e7525a9541b0283e54574d27c86c9b4a26ddf",
    },
} as const;

type ModelSpec = (typeof modelSpecs)[keyof typeof modelSpecs];

/** Return the path where the given {@link modelName} is meant to be saved */
const modelSavePath = (modelName: string) =>
    path.join(userDataPath(), "models", modelName);

/**
 * Cached promises to the on-disk paths of verified models, so that each model
 * is downloaded and verified at most once per process. Multiple parallel
 * calls for the same model await the same promise.
 */
const _verifiedModelPaths = new Map<string, Promise<string>>();

/** The single cleanup attempt shared by all model loads in this process. */
let _oldModelsCleanup: Promise<void> | undefined;

const modelPath = (spec: ModelSpec) => {
    let promise = _verifiedModelPaths.get(spec.name);
    if (!promise) {
        promise = modelPathDownloadingIfNeeded(spec).catch((e: unknown) => {
            // Allow a later call to retry the download.
            _verifiedModelPaths.delete(spec.name);
            throw e;
        });
        _verifiedModelPaths.set(spec.name, promise);
    }
    return promise;
};

/**
 * Forget the cached verification of the model at {@link modelPath} and delete
 * it from disk, so that the next use downloads a fresh copy. Used when the
 * Rust side reports the on-disk model as corrupt.
 */
const evictModel = async (modelPath: string) => {
    const name = path.basename(modelPath);
    _verifiedModelPaths.delete(name);
    await fs.rm(modelPath, { force: true });
};

/**
 * Download the model described by {@link spec} if we don't already have it.
 *
 * An existing on-disk copy is revalidated with only a cheap size check so
 * that resolving already downloaded models stays fast; fresh downloads are
 * verified against the pinned SHA-256.
 *
 * @returns the path to the model on the local machine.
 */
const modelPathDownloadingIfNeeded = async (spec: ModelSpec) => {
    const savePath = modelSavePath(spec.name);

    await cleanupOldModelsIfNeeded();

    if (existsSync(savePath)) {
        const size = (await fs.stat(savePath)).size;
        if (size == spec.byteSize) return savePath;
        log.error(
            `The size ${size} of model ${spec.name} does not match the expected size, downloading again`,
        );
    } else {
        log.info(`ML model ${spec.name} not found, downloading`);
    }

    await downloadModelVerifyingSHA256(savePath, spec);
    return savePath;
};

/**
 * Download the model described by {@link spec} to {@link savePath}, verifying
 * the SHA-256 of the downloaded contents and retrying once on mismatch.
 */
const downloadModelVerifyingSHA256 = async (
    savePath: string,
    spec: ModelSpec,
) => {
    await downloadModel(savePath, spec.name);
    if ((await computeFileSHA256(savePath)) == spec.sha256) return;

    log.error(
        `The SHA-256 of the downloaded model ${spec.name} does not match the expected value, downloading again`,
    );
    await downloadModel(savePath, spec.name);
    if ((await computeFileSHA256(savePath)) == spec.sha256) return;

    // Don't leave the bad download behind: were it to happen to pass the size
    // check, a later call would use it without noticing.
    await fs.rm(savePath, { force: true });
    throw new Error(
        `The SHA-256 of the downloaded model ${spec.name} does not match the expected value`,
    );
};

const computeFileSHA256 = (filePath: string) =>
    new Promise<string>((resolve, reject) => {
        const hash = createHash("sha256");
        const stream = createReadStream(filePath);
        stream.on("error", reject);
        stream.on("data", (chunk) => hash.update(chunk));
        stream.on("end", () => resolve(hash.digest("hex")));
    });

/**
 * Cleanup old models.
 *
 * This code runs at most once in each utility process, before its first model
 * is resolved. This is a good time to delete previously existent but now
 * unused models and reclaim their disk space.
 */
const cleanupOldModelsIfNeeded = () =>
    (_oldModelsCleanup ??= cleanupOldModels().catch((e: unknown) => {
        // Removing obsolete cache files is best effort and must not prevent the
        // current models from loading. Retry on the next process start.
        log.warn("Failed to clean up old ML models", e);
    }));

const cleanupOldModels = async () => {
    const oldModelNames = [
        "clip-image-vit-32-float32.onnx",
        "clip-text-vit-32-uint8.onnx",
        "mobileclip_s2_image.onnx",
        "mobileclip_s2_image_opset18_rgba_sim.onnx",
        "mobileclip_s2_image_opset18_rgba_opt.onnx",
        "mobileclip_s2_text_int32.onnx",
        "yolov5s_face_640_640_dynamic.onnx",
        "yolov5s_face_opset18_rgba_opt.onnx",
        "yolov5s_face_opset18_rgba_opt_nosplits.onnx",
        "mobilefacenet_opset15.onnx",
    ];

    for (const modelName of oldModelNames) {
        const modelPath = modelSavePath(modelName);
        if (existsSync(modelPath)) {
            log.info(`Removing unused ML model at ${modelPath}`);
            await fs.rm(modelPath, { force: true });
        }
    }
};

const downloadModel = async (saveLocation: string, name: string) => {
    // `mkdir -p` the directory where we want to save the model.
    const saveDir = path.dirname(saveLocation);
    await fs.mkdir(saveDir, { recursive: true });
    // Download.
    log.info(`Downloading ML model from ${name}`);
    const url = `https://models.ente.com/${name}`;
    const res = await net.fetch(url);
    if (!res.ok) throw new Error(`Failed to fetch ${url}: HTTP ${res.status}`);
    const body = res.body;
    if (!body) throw new Error(`Received an null response for ${url}`);
    // Save.
    await writeStream(saveLocation, body);
    log.info(`Downloaded ML model ${name}`);
};

/**
 * The subset of {@link modelSpecs} needed for the indexing related tasks that
 * are enabled in the given request, mapped to verified on-disk paths.
 *
 * Models for tasks that are not requested are left as empty strings, which
 * the Rust side treats as "not configured".
 */
const indexingModelPaths = async (
    runFaces: boolean,
    runClip: boolean,
    runPets: boolean,
): Promise<MLNativeModule.ModelPaths> => {
    const [faceDetection, faceEmbedding] = runFaces
        ? await Promise.all([
              modelPath(modelSpecs.faceDetection),
              modelPath(modelSpecs.faceEmbedding),
          ])
        : ["", ""];
    const clipImage = runClip ? await modelPath(modelSpecs.clipImage) : "";
    const [
        petFaceDetection,
        petFaceEmbeddingDog,
        petFaceEmbeddingCat,
        petBodyDetection,
        petBodyEmbeddingDog,
        petBodyEmbeddingCat,
    ] = runPets
        ? await Promise.all([
              modelPath(modelSpecs.petFaceDetection),
              modelPath(modelSpecs.petFaceEmbeddingDog),
              modelPath(modelSpecs.petFaceEmbeddingCat),
              modelPath(modelSpecs.petBodyDetection),
              modelPath(modelSpecs.petBodyEmbeddingDog),
              modelPath(modelSpecs.petBodyEmbeddingCat),
          ])
        : ["", "", "", "", "", ""];

    return {
        faceDetection,
        faceEmbedding,
        clipImage,
        // The CLIP text session is managed lazily by the Rust side when
        // serving text queries; it is not part of the indexing runtime.
        clipText: "",
        petFaceDetection,
        petFaceEmbeddingDog,
        petFaceEmbeddingCat,
        petBodyDetection,
        petBodyEmbeddingDog,
        petBodyEmbeddingCat,
    };
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
        if (!(await evictModelIfReportedCorrupt(e))) throw e;
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
 * the corrupt model file it reports (but only if that path is under our
 * models directory, as a safety check before we delete it).
 */
const corruptModelPathFromError = (e: unknown) => {
    if (!(e instanceof Error)) return undefined;
    if (!e.message.startsWith("CorruptModel: ")) return undefined;
    const corruptPath = e.message.slice("CorruptModel: ".length).trim();
    const modelsDir = path.join(userDataPath(), "models") + path.sep;
    return corruptPath.startsWith(modelsDir) ? corruptPath : undefined;
};

/**
 * If {@link e} is the addon's tagged "CorruptModel" error, evict the model it
 * names so that its next use downloads a fresh copy, and return `true`.
 */
const evictModelIfReportedCorrupt = async (e: unknown) => {
    const corruptModelPath = corruptModelPathFromError(e);
    if (!corruptModelPath) return false;
    log.error(
        `Rust ML reported a corrupt model at ${corruptModelPath}, evicting it so that it gets redownloaded`,
    );
    await evictModel(corruptModelPath);
    return true;
};

// Zero-copy view over the transferred bytes.
const uint8ArrayToBuffer = (bytes: Uint8Array) =>
    Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength);

/**
 * Run a throwaway CLIP text query so that the Rust side builds and caches the
 * text encoder session before the user's first search. Mirrors the mobile
 * app's warm up (see ml_computer.dart).
 *
 * Best effort - on failure, queries build the session on demand as before.
 */
const warmUpClipTextEncoder = async (native: MLNative) => {
    try {
        const [model, vocab] = await Promise.all([
            modelPath(modelSpecs.clipText),
            modelPath(modelSpecs.clipTextVocab),
        ]);
        await native.runClipText({
            text: "warm up text encoder",
            modelPath: model,
            vocabPath: vocab,
        });
    } catch (e) {
        if (!(await evictModelIfReportedCorrupt(e)))
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
        Promise.all([
            modelPath(modelSpecs.clipText),
            modelPath(modelSpecs.clipTextVocab),
        ]),
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

    const [clipTextModelPath, vocabPath] = pathsOrSkip;
    try {
        const { embedding } = await native.runClipText({
            text,
            modelPath: clipTextModelPath,
            vocabPath,
        });
        return embedding;
    } catch (e) {
        // Don't block this query on the redownload; a subsequent query will
        // pick up the fresh copy.
        if (!(await evictModelIfReportedCorrupt(e))) throw e;
        return undefined;
    } finally {
        logMLRuntimeEvents(native);
    }
};
