/**
 * @file This main process code and interface for dealing with the various
 * utility processes that we create.
 */

import type { Endpoint } from "comlink";
import {
    MessageChannelMain,
    type BrowserWindow,
    type UtilityProcess,
} from "electron";
import { app, utilityProcess } from "electron/main";
import path from "node:path";
import type { UtilityProcessType } from "../../types/ipc";
import log, { processUtilityProcessLogMessage } from "../log";
import { messagePortMainEndpoint } from "../utils/comlink";

/**
 * Terminate any existing utility processes if they're running.
 *
 * This function is called during the logout sequence.
 */
export const terminateUtilityProcesses = () => {
    terminateMLProcessIfRunning();
    terminateFFmpegProcessIfRunning();
};

/** The active ML utility process, if any. */
let _utilityProcessML: UtilityProcess | undefined;

/** The active FFmpeg utility process, if any. */
let _utilityProcessFFmpeg: UtilityProcess | undefined;

/**
 * A promise to a comlink {@link Endpoint} that can be used to communicate with
 * the active ffmpeg utility process (if any).
 */
let _utilityProcessFFmpegEndpoint: Promise<Endpoint> | undefined;

/**
 * Create a new utility process of the given {@link type}, terminating the older
 * ones (if any).
 *
 * Currently the only type is "ml". The following note explains the reasoning
 * why utility processes were used for the first workload (ML) that was handled
 * this way. Similar reasoning applies to subsequent workloads (ffmpeg) that
 * have been offloaded to utility processes in a slightly different manner to
 * avoid stutter in the UI.
 *
 * [Note: ML IPC]
 *
 * The primary reason for doing ML tasks in the Node.js layer is so that we can
 * use the binary ONNX runtime, which is 10-20x faster than the Wasm one that
 * can be used directly on the web layer.
 *
 * For this to work, the main and renderer process need to communicate with each
 * other. Further, in the web layer the ML indexing runs in a web worker (so as
 * to not get in the way of the main thread). So the communication has 2 hops:
 *
 *     Node.js main <-> Renderer main <-> Renderer web worker
 *
 * This naive way works, but has a problem. The Node.js main process is in the
 * code path for delivering user events to the renderer process. The ML tasks we
 * do take in the order of 100-300 ms (possibly more) for each individual
 * inference. Thus, the Node.js main process is busy for those 100-300 ms, and
 * does not forward events to the renderer, causing the UI to jitter.
 *
 * The solution for this is to spawn an Electron UtilityProcess, which we can
 * think of a regular Node.js child process. This frees up the Node.js main
 * process, and would remove the jitter.
 * https://www.electronjs.org/docs/latest/tutorial/process-model
 *
 * It would seem that this introduces another hop in our IPC
 *
 *     Node.js utility process <-> Node.js main <-> ...
 *
 * but here we can use the special bit about Electron utility processes that
 * separates them from regular Node.js child processes: their support for
 * message ports. https://www.electronjs.org/docs/latest/tutorial/message-ports
 *
 * As a brief summary, a MessagePort is a web feature that allows two contexts
 * to communicate. A pair of message ports is called a message channel. The cool
 * thing about these is that we can pass these ports themselves over IPC.
 *
 * > One caveat here is that the message ports can only be passed using the
 * > `postMessage` APIs, not the usual send/invoke APIs.
 *
 * So we
 *
 * 1. In the utility process create a message channel.
 * 2. Spawn a utility process, and send one port of the pair to it.
 * 3. Send the other port of the pair to the renderer.
 *
 * The renderer will forward that port to the web worker that is coordinating
 * the ML indexing on the web layer. Thereafter, the utility process and web
 * worker can directly talk to each other!
 *
 *     Node.js utility process <-> Renderer web worker
 *
 * The RPC protocol is handled using comlink on both ends. The port itself needs
 * to be relayed using `postMessage`.
 */
export const triggerCreateUtilityProcess = (
    type: UtilityProcessType,
    window: BrowserWindow,
) => triggerCreateMLUtilityProcess(window);

const terminateMLProcessIfRunning = () => {
    if (_utilityProcessML) {
        log.debug(() => "Terminating running ML utility process");
        _utilityProcessML.kill();
        _utilityProcessML = undefined;
    }
};

export const triggerCreateMLUtilityProcess = (window: BrowserWindow) => {
    terminateMLProcessIfRunning();

    const { port1, port2 } = new MessageChannelMain();

    const child = utilityProcess.fork(path.join(__dirname, "ml-worker.js"));
    const userDataPath = app.getPath("userData");
    child.postMessage(/* MLWorkerInitData */ { userDataPath }, [port1]);

    window.webContents.postMessage("utilityProcessPort/ml", undefined, [port2]);

    handleMessagesFromMLUtilityProcess(child);

    _utilityProcessML = child;
};

/**
 * Handle messages posted from the utility process.
 *
 * [Note: Using Electron APIs in UtilityProcess]
 *
 * Only a small subset of the Electron APIs are available to a UtilityProcess.
 * As of writing (Jul 2024, Electron 30), only the following are available:
 *
 * - net
 * - systemPreferences
 *
 * In particular, `app` is not available.
 *
 * We structure our code so that it doesn't need anything apart from `net`.
 *
 * For the other cases,
 *
 * -  Additional parameters to the utility process are passed alongwith the
 *    initial message where we provide it the message port.
 *
 * -  When we need to communicate from the utility process to the main process,
 *    we use the `parentPort` in the utility process.
 */
const handleMessagesFromMLUtilityProcess = (child: UtilityProcess) => {
    child.on("message", (m: unknown) => {
        if (processUtilityProcessLogMessage("[ml-worker]", m)) {
            return;
        }
        log.info("Ignoring unknown message from ML utility process", m);
    });
};

/**
 * A comlink endpoint that can be used to communicate with the ffmpeg utility
 * process. If there is no ffmpeg utility process, a new one is created on
 * demand.
 *
 * See [Note: ML IPC] for a general outline of why utility processes are needed
 * (tl;dr; to avoid stutter on the UI).
 *
 * In the case of ffmpeg, the IPC flow is a bit different: the utility process
 * is not exposed to the web layer, and is internal to the node layer. The
 * reason for this difference is that we need to create temporary files etc, and
 * doing it a utility process requires access to the `app` module which are not
 * accessible (See: [Note: Using Electron APIs in UtilityProcess]).
 *
 * There could've been possible reasonable workarounds, but the architecture
 * we've adopted of three layers:
 *
 *     Renderer (web) <-> Node.js main <-> Node.js ffmpeg utility process
 *
 * The temporary file creation etc is handled in the Node.js main process, and
 * paths to the files are forwarded to the ffmpeg utility process to act on.
 *
 * @returns an endpoint that can be used to communicate with the utility
 * process. The utility process is expected to expose an object that conforms to
 * the {@link ElectronFFmpegWorkerNode} interface on this endpoint.
 */
export const ffmpegUtilityProcessEndpoint = () =>
    (_utilityProcessFFmpegEndpoint ??= createFFmpegUtilityProcessEndpoint());

const terminateFFmpegProcessIfRunning = () => {
    if (_utilityProcessFFmpeg) {
        log.debug(() => "Terminating running FFmpeg utility process");
        _utilityProcessFFmpeg.kill();
        _utilityProcessFFmpeg = undefined;
        _utilityProcessFFmpegEndpoint = undefined;
    }
};

const createFFmpegUtilityProcessEndpoint = () => {
    if (_utilityProcessFFmpeg) {
        throw new Error("FFmpeg utility process is already running");
    }

    // Promise.withResolvers is currently in the node available to us.
    let resolve: ((endpoint: Endpoint) => void) | undefined;
    const promise = new Promise<Endpoint>((r) => (resolve = r));

    const { port1, port2 } = new MessageChannelMain();

    const child = utilityProcess.fork(path.join(__dirname, "ffmpeg-worker.js"));
    // Send a handle to the port (one end of the message channel) to the utility
    // process (alongwith any other init data). The utility process will reply
    // with an "ack" when it get it.
    const appVersion = app.getVersion();
    child.postMessage(/* FFmpegWorkerInitData */ { appVersion }, [port1]);

    child.on("message", (m: unknown) => {
        if (m && typeof m == "object" && "method" in m) {
            switch (m.method) {
                case "ack":
                    resolve!(messagePortMainEndpoint(port2));
                    return;
            }
        }

        if (processUtilityProcessLogMessage("[ffmpeg-worker]", m)) {
            return;
        }

        log.info("Ignoring unknown message from ffmpeg utility process", m);
    });

    _utilityProcessFFmpeg = child;

    // Resolve with the other end of the message channel (once we get an "ack"
    // from the utility process).
    return promise;
};
