#!/usr/bin/env node

"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs/promises");
const path = require("node:path");
const readline = require("node:readline");
const { BrowserWindow, MessageChannelMain } = require("electron");
const { app, utilityProcess } = require("electron/main");
const { wrap } = require("comlink");

const MODEL_FILE_NAMES = {
    clip: "mobileclip_s2_image_opset18_rgba_opt.onnx",
    face_detection: "yolov5s_face_opset18_rgba_opt_nosplits.onnx",
    face_embedding: "mobilefacenet_opset15.onnx",
};
const HOST_RESPONSE_PREFIX = "__ML_PARITY_JSON__";

const SCRIPT_DIR = __dirname;
const DESKTOP_DIR = path.resolve(SCRIPT_DIR, "..");
const REPO_ROOT = path.resolve(DESKTOP_DIR, "..");
const COMPILED_ML_WORKER_PATH = path.join(
    REPO_ROOT,
    "desktop",
    "app",
    "main",
    "services",
    "ml-worker.js",
);
const COMPILED_IMAGE_SERVICE_PATH = path.join(
    REPO_ROOT,
    "desktop",
    "app",
    "main",
    "services",
    "image.js",
);

const messagePortMainEndpoint = (mp) => {
    const listeners = new WeakMap();
    return {
        postMessage: (message, transfer) => {
            mp.postMessage(message, transfer ?? []);
        },
        addEventListener: (_event, handler) => {
            const listener = (data) =>
                "handleEvent" in handler
                    ? handler.handleEvent({ data })
                    : handler(data);
            mp.on("message", (data) => {
                listener(data);
            });
            listeners.set(handler, listener);
        },
        removeEventListener: (_event, handler) => {
            const listener = listeners.get(handler);
            if (!listener) {
                return;
            }
            mp.off("message", listener);
            listeners.delete(handler);
        },
        start: mp.start.bind(mp),
    };
};

const toBase64FromTypedArray = (array) =>
    Buffer.from(array.buffer, array.byteOffset, array.byteLength).toString(
        "base64",
    );

const uint8ClampedArrayFromBase64 = (payload) => {
    const bytes = Buffer.from(payload, "base64");
    const array = new Uint8ClampedArray(bytes.byteLength);
    array.set(bytes);
    return array;
};

const float32ArrayFromBase64 = (payload) => {
    const bytes = Buffer.from(payload, "base64");
    if (bytes.byteLength % 4 !== 0) {
        throw new Error(
            `Float32 payload byte length ${bytes.byteLength} is not divisible by 4`,
        );
    }
    const array = new Float32Array(bytes.byteLength / 4);
    new Uint8Array(array.buffer).set(bytes);
    return array;
};

let _convertToJPEG;
const getConvertToJPEG = () => {
    if (_convertToJPEG) {
        return _convertToJPEG;
    }
    const imageService = require(COMPILED_IMAGE_SERVICE_PATH);
    if (!imageService || typeof imageService.convertToJPEG !== "function") {
        throw new Error(
            `convertToJPEG export not found in ${COMPILED_IMAGE_SERVICE_PATH}`,
        );
    }
    _convertToJPEG = imageService.convertToJPEG;
    return _convertToJPEG;
};

const DEFAULT_DECODE_HELPER_SOURCE = `async (imageBlob) => {
    const imageBitmap = await createImageBitmap(imageBlob);

    const { width, height } = imageBitmap;

    // Use an OffscreenCanvas to get the bitmap's data.
    const offscreenCanvas = new OffscreenCanvas(width, height);
    const ctx = offscreenCanvas.getContext("2d");
    ctx.drawImage(imageBitmap, 0, 0, width, height);
    const imageData = ctx.getImageData(0, 0, width, height);

    return { bitmap: imageBitmap, data: imageData };
}`;

const ensureDecodeWindowScript = async (decodeWindow, decodeHelperSource) => {
    await decodeWindow.webContents.executeJavaScript(
        `
(() => {
  const decodeHelperSource = ${JSON.stringify(decodeHelperSource)};

  if (
    typeof globalThis.__mlParityCreateImageBitmapAndData !== "function" ||
    globalThis.__mlParityDecodeHelperSource !== decodeHelperSource
  ) {
    const helper = eval("(" + decodeHelperSource + ")");
    if (typeof helper !== "function") {
      throw new Error("Decode helper source did not evaluate to a function");
    }
    globalThis.__mlParityCreateImageBitmapAndData = helper;
    globalThis.__mlParityDecodeHelperSource = decodeHelperSource;
    globalThis.__mlParityDecodeFile = undefined;
  }

  if (typeof globalThis.__mlParityDecodeFile === "function") return;
  globalThis.__mlParityDecodeFile = async (filePath, mimeType) => {
    const fs = require("node:fs/promises");
    const bytes = await fs.readFile(filePath);
    const blob = mimeType ? new Blob([bytes], { type: mimeType }) : new Blob([bytes]);
    const { bitmap, data } = await globalThis.__mlParityCreateImageBitmapAndData(blob);
    try {
      return {
        width: data.width,
        height: data.height,
        rgba_base64: Buffer.from(data.data.buffer).toString("base64"),
      };
    } finally {
      if (bitmap && typeof bitmap.close === "function") bitmap.close();
    }
  };
})();
        `,
        true,
    );
};

const rgbaBase64FromPath = async (
    decodeWindow,
    decodeHelperSource,
    filePath,
    mimeType,
) => {
    if (!decodeWindow || decodeWindow.isDestroyed()) {
        throw new Error("Decode window is unavailable");
    }
    if (!decodeWindow.webContents || decodeWindow.webContents.isDestroyed()) {
        throw new Error("Decode window webContents is unavailable");
    }

    await ensureDecodeWindowScript(decodeWindow, decodeHelperSource);
    const invocation = `globalThis.__mlParityDecodeFile(${JSON.stringify(filePath)}, ${JSON.stringify(mimeType ?? null)})`;
    return decodeWindow.webContents.executeJavaScript(invocation, true);
};

const sha256ForFile = async (filePath) => {
    const contents = await fs.readFile(filePath);
    return crypto.createHash("sha256").update(contents).digest("hex");
};

const modelMetadata = async (userDataPath) => {
    const modelsDir = path.join(userDataPath, "models");
    const result = {};

    await fs.mkdir(modelsDir, { recursive: true });

    for (const [modelName, fileName] of Object.entries(MODEL_FILE_NAMES)) {
        const filePath = path.join(modelsDir, fileName);
        try {
            await fs.access(filePath);
            const sha256 = await sha256ForFile(filePath);
            result[modelName] = `${fileName}:sha256:${sha256}`;
        } catch {
            result[modelName] = `${fileName}:missing`;
        }
    }

    return result;
};

const sendResponse = (payload) => {
    process.stdout.write(`${HOST_RESPONSE_PREFIX}${JSON.stringify(payload)}\n`);
};

const createWorkerState = async () => {
    await app.whenReady();

    try {
        await fs.access(COMPILED_ML_WORKER_PATH);
    } catch {
        throw new Error(
            "Compiled desktop ML worker not found. Run `npm --prefix desktop exec -- tsc -p desktop/tsconfig.json` first.",
        );
    }
    try {
        await fs.access(COMPILED_IMAGE_SERVICE_PATH);
    } catch {
        throw new Error(
            "Compiled desktop image service not found. Run `npm --prefix desktop exec -- tsc -p desktop/tsconfig.json` first.",
        );
    }

    const userDataPath =
        process.env.ML_PARITY_USER_DATA_DIR?.trim() || app.getPath("userData");
    await fs.mkdir(userDataPath, { recursive: true });

    const { port1, port2 } = new MessageChannelMain();
    const child = utilityProcess.fork(COMPILED_ML_WORKER_PATH);
    child.postMessage({ userDataPath }, [port1]);

    const decodeWindow = new BrowserWindow({
        show: false,
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false,
            sandbox: false,
        },
    });
    await decodeWindow.loadURL("about:blank");
    await ensureDecodeWindowScript(decodeWindow, DEFAULT_DECODE_HELPER_SOURCE);

    child.on("message", (message) => {
        if (
            message &&
            typeof message === "object" &&
            "method" in message &&
            message.method === "log"
        ) {
            return;
        }
        process.stderr.write(
            `[ml_parity_host] utility-process message: ${JSON.stringify(message)}\n`,
        );
    });

    child.on("exit", (code, signal) => {
        process.stderr.write(
            `[ml_parity_host] utility process exited code=${code ?? "null"} signal=${signal ?? "null"}\n`,
        );
    });

    const worker = wrap(messagePortMainEndpoint(port2));

    return {
        child,
        decodeHelperSource: DEFAULT_DECODE_HELPER_SOURCE,
        decodeWindow,
        worker,
        userDataPath,
    };
};

let workerStatePromise;

const getWorkerState = () => {
    workerStatePromise ??= createWorkerState();
    return workerStatePromise;
};

const handleRequest = async (request) => {
    if (!request || typeof request !== "object") {
        throw new Error("Invalid request payload");
    }

    const { method, params } = request;
    const state = await getWorkerState();

    switch (method) {
        case "decodeImage": {
            if (!params || typeof params.file_path !== "string") {
                throw new Error("decodeImage requires params.file_path");
            }
            const mimeType =
                typeof params.mime_type === "string" && params.mime_type.trim()
                    ? params.mime_type.trim()
                    : undefined;
            return rgbaBase64FromPath(
                state.decodeWindow,
                state.decodeHelperSource,
                params.file_path,
                mimeType,
            );
        }
        case "setDecodeHelperSource": {
            if (
                !params ||
                typeof params.source !== "string" ||
                !params.source.trim()
            ) {
                throw new Error("setDecodeHelperSource requires params.source");
            }
            state.decodeHelperSource = params.source;
            await ensureDecodeWindowScript(
                state.decodeWindow,
                state.decodeHelperSource,
            );
            return { ok: true };
        }
        case "convertToJPEG": {
            if (!params || typeof params.input_base64 !== "string") {
                throw new Error("convertToJPEG requires params.input_base64");
            }
            const input = new Uint8Array(
                Buffer.from(params.input_base64, "base64"),
            );
            const output = await getConvertToJPEG()(input);
            return { output_base64: Buffer.from(output).toString("base64") };
        }
        case "computeCLIPImageEmbedding": {
            if (!params || typeof params.input_base64 !== "string") {
                throw new Error(
                    "computeCLIPImageEmbedding requires params.input_base64",
                );
            }
            if (!Array.isArray(params.input_shape)) {
                throw new Error(
                    "computeCLIPImageEmbedding requires params.input_shape",
                );
            }
            const input = uint8ClampedArrayFromBase64(params.input_base64);
            const output = await state.worker.computeCLIPImageEmbedding(
                input,
                params.input_shape,
            );
            return { output_base64: toBase64FromTypedArray(output) };
        }
        case "detectFaces": {
            if (!params || typeof params.input_base64 !== "string") {
                throw new Error("detectFaces requires params.input_base64");
            }
            if (!Array.isArray(params.input_shape)) {
                throw new Error("detectFaces requires params.input_shape");
            }
            const input = uint8ClampedArrayFromBase64(params.input_base64);
            const output = await state.worker.detectFaces(
                input,
                params.input_shape,
            );
            return { output_base64: toBase64FromTypedArray(output) };
        }
        case "computeFaceEmbeddings": {
            if (!params || typeof params.input_base64 !== "string") {
                throw new Error(
                    "computeFaceEmbeddings requires params.input_base64",
                );
            }
            const input = float32ArrayFromBase64(params.input_base64);
            const output = await state.worker.computeFaceEmbeddings(input);
            return { output_base64: toBase64FromTypedArray(output) };
        }
        case "modelMetadata": {
            return modelMetadata(state.userDataPath);
        }
        case "shutdown": {
            return { ok: true };
        }
        default:
            throw new Error(`Unsupported method '${String(method)}'`);
    }
};

const shutdown = async () => {
    try {
        const state = await workerStatePromise;
        if (state.decodeWindow && !state.decodeWindow.isDestroyed()) {
            state.decodeWindow.destroy();
        }
        state.child.kill();
    } catch {
        // Ignore shutdown failures.
    }

    try {
        await app.quit();
    } catch {
        process.exit(0);
    }
};

const rl = readline.createInterface({
    input: process.stdin,
    crlfDelay: Infinity,
});

rl.on("line", async (line) => {
    if (!line.trim()) {
        return;
    }

    let request;
    try {
        request = JSON.parse(line);
    } catch (error) {
        sendResponse({
            id: null,
            ok: false,
            error: `Failed to parse request JSON: ${String(error)}`,
        });
        return;
    }

    const id = request.id ?? null;

    try {
        const result = await handleRequest(request);
        sendResponse({ id, ok: true, result });
        if (request.method === "shutdown") {
            setTimeout(() => {
                void shutdown();
            }, 0);
        }
    } catch (error) {
        sendResponse({
            id,
            ok: false,
            error: error instanceof Error ? error.message : String(error),
        });
    }
});

rl.on("close", () => {
    void shutdown();
});

process.on("SIGINT", () => {
    void shutdown();
});

process.on("SIGTERM", () => {
    void shutdown();
});
