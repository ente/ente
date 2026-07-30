#!/usr/bin/env node
/**
 * Desktop platform runner for the ML indexing parity suite.
 *
 * Run the parity corpus through the desktop build of the Rust ML pipeline
 * (see [Note: ML with Rust] in the desktop app), writing results in the
 * format consumed by compare_parity_outputs.py.
 *
 * This is invoked by run_ml_parity_tests.sh, which syncs the fixture images
 * and models to local disk beforehand; this script performs no network
 * access. It smoke tests the desktop specific pieces — the napi addon and
 * the pinned ONNX Runtime library it loads — while the deep validation of
 * the shared Rust pipeline itself lives in the ente-photos crate's
 * ml_indexing integration test.
 *
 * The desktop build artifacts it needs are the addon in
 * `desktop/rust-bindings/` (built by `node scripts/napi.js build`) and the
 * ONNX Runtime library in `desktop/build/onnxruntime/` (downloaded by the
 * desktop postinstall).
 */

const fsp = require("node:fs/promises");
const path = require("node:path");
const { parseArgs } = require("node:util");

const repoRoot = path.resolve(__dirname, "..", "..", "..", "..");
const desktopDir = path.join(repoRoot, "desktop");

// The desktop build scripts own the addon naming scheme.
const { napiTriple } = require(
    path.join(desktopDir, "scripts", "napi.js"),
);

const requiredFlags = [
    "manifest",
    "ml-dir",
    "models-dir",
    "asset-lock",
    "code-revision",
    "output",
];

const parseCLIArgs = () => {
    const { values } = parseArgs({
        options: Object.fromEntries(
            requiredFlags.map((flag) => [flag, { type: "string" }]),
        ),
    });
    for (const flag of requiredFlags)
        if (!values[flag]) throw new Error(`Missing required --${flag}`);
    return values;
};

/** Load the Rust ML addon built by desktop's `scripts/napi.js`. */
const loadMLAddon = () => {
    const addonPath = path.join(
        desktopDir,
        "rust-bindings",
        `index.${napiTriple(process.platform, process.arch)}.node`,
    );
    return require(addonPath);
};

/**
 * The ONNX Runtime dynamic library downloaded by desktop's `scripts/ort.js`
 * for the current architecture, located by scanning so that this script does
 * not duplicate the pinned library version.
 */
const onnxRuntimeLibraryPath = async () => {
    const libraryDir = path.join(
        desktopDir,
        "build",
        "onnxruntime",
        process.arch,
    );
    const entries = await fsp.readdir(libraryDir, { withFileTypes: true });
    const library = entries.find(
        (entry) =>
            entry.isFile() &&
            (entry.name.startsWith("libonnxruntime.") ||
                entry.name == "onnxruntime.dll"),
    );
    if (!library)
        throw new Error(
            `No ONNX Runtime library found in ${libraryDir} (run "npm run postinstall" in desktop/)`,
        );
    return path.join(libraryDir, library.name);
};

/**
 * Resolve the models needed for indexing from the parity harness' local
 * model mirror cache, which run_ml_parity_tests.sh populates (verifying
 * against the SHA-256s in the asset lock) before invoking us.
 */
const resolveModels = async (assetLockPath, modelsDir) => {
    const assetLock = JSON.parse(await fsp.readFile(assetLockPath, "utf8"));

    const resolveModel = async (key) => {
        const spec = assetLock.models[key];
        if (!spec) throw new Error(`No model entry ${key} in ${assetLockPath}`);
        const modelPath = path.join(modelsDir, spec.file_name);
        try {
            await fsp.access(modelPath);
        } catch {
            throw new Error(
                `Model ${spec.file_name} not found in ${modelsDir}`,
            );
        }
        return {
            path: modelPath,
            fileName: spec.file_name,
            sha256: spec.sha256,
        };
    };

    return {
        faceDetection: await resolveModel("face_detection"),
        faceEmbedding: await resolveModel("face_embedding"),
        clipImage: await resolveModel("clip_image"),
    };
};

const mlModelPaths = (models) => ({
    faceDetection: models.faceDetection.path,
    faceEmbedding: models.faceEmbedding.path,
    clipImage: models.clipImage.path,
    clipText: "",
    petFaceDetection: "",
    petFaceEmbeddingDog: "",
    petFaceEmbeddingCat: "",
    petBodyDetection: "",
    petBodyEmbeddingDog: "",
    petBodyEmbeddingCat: "",
});

const analyzeFixture = async (native, fileID, imagePath, modelPaths) => {
    const result = await native.analyzeImage({
        fileId: fileID,
        imagePath,
        runFaces: true,
        runClip: true,
        runPets: false,
        generateFaceCrops: true,
        modelPaths,
    });

    // Also smoke the desktop-only face crop path: crop generation is best
    // effort, but for the parity corpus every face must get a crop.
    const faceCount = result.faces?.length ?? 0;
    const cropCount = (result.faceCrops ?? []).filter(Boolean).length;
    if (cropCount != faceCount)
        throw new Error(
            `Face crop count ${cropCount} does not match face count ${faceCount}`,
        );

    return result;
};

/** Mirror of _toParityResult in mobile's ml_parity_shared.dart. */
const toParityResult = (fileID, result, models, codeRevision, totalMS) => {
    const clip = result.clip;
    if (!clip) throw new Error(`Missing CLIP result for ${fileID}`);

    const faces = (result.faces ?? []).map((face) => {
        const [xMin, yMin, xMax, yMax] = face.detection.boxXyxy;
        return {
            box: [xMin, yMin, xMax - xMin, yMax - yMin],
            landmarks: face.detection.keypoints,
            score: face.detection.score,
            embedding: Array.from(face.embedding),
        };
    });

    return {
        file_id: fileID,
        clip: { embedding: Array.from(clip.embedding) },
        faces,
        runner_metadata: {
            platform: "desktop",
            runtime: "rust-ml",
            models: Object.fromEntries(
                Object.values(models).map((m) => [m.fileName, m.sha256]),
            ),
            code_revision: codeRevision,
            timing_ms: { total: totalMS },
        },
    };
};

const main = async () => {
    const args = parseCLIArgs();

    const native = loadMLAddon();
    native.initOrt(await onnxRuntimeLibraryPath());
    // Match the app's configuration (see ml-worker.ts); a no-op on macOS.
    native.setMlExecutionConfig(true);

    const models = await resolveModels(args["asset-lock"], args["models-dir"]);
    const modelPaths = mlModelPaths(models);

    const manifest = JSON.parse(await fsp.readFile(args.manifest, "utf8"));
    const items = manifest.items;
    if (!Array.isArray(items) || items.length == 0)
        throw new Error(`No items in manifest ${args.manifest}`);

    native.initMlRuntime(modelPaths);

    const results = [];
    const errors = [];
    try {
        for (const [index, item] of items.entries()) {
            const t = Date.now();
            try {
                const imagePath = path.resolve(args["ml-dir"], item.source);
                const result = await analyzeFixture(
                    native,
                    index + 1,
                    imagePath,
                    modelPaths,
                );
                results.push(
                    toParityResult(
                        item.file_id,
                        result,
                        models,
                        args["code-revision"],
                        Date.now() - t,
                    ),
                );
                console.log(`Analyzed ${item.file_id}`);
            } catch (e) {
                const message = e instanceof Error ? e.message : String(e);
                errors.push({
                    file_id: item.file_id,
                    error: message,
                    timing_ms: Date.now() - t,
                });
                console.log(`Failed to analyze ${item.file_id}: ${message}`);
            }
        }
    } finally {
        native.releaseMlRuntime();
        for (const { severity, message } of native.takeMlRuntimeEvents())
            console.log(`[ml-rt] ${severity}: ${message}`);
    }

    await fsp.mkdir(path.dirname(args.output), { recursive: true });
    await fsp.writeFile(
        args.output,
        JSON.stringify({
            platform: "desktop",
            results,
            ...(errors.length ? { errors } : {}),
        }),
    );

    console.log(
        `Analyzed ${results.length} of ${items.length} fixtures (${errors.length} failed)`,
    );
    if (results.length == 0) throw new Error("All fixtures failed to analyze");
};

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
