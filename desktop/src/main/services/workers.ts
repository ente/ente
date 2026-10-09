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
import { mlNativePaths } from "./ml-native";

export const terminateUtilityProcesses = () => {
    terminateMLProcessIfRunning();
    terminateFFmpegProcessIfRunning();
};

let _utilityProcessML: UtilityProcess | undefined;

let _utilityProcessFFmpeg: UtilityProcess | undefined;

let _utilityProcessFFmpegEndpoint: Promise<Endpoint> | undefined;

// Native ML runs outside main so inference cannot block UI event delivery. A
// transferred MessagePort connects the utility process to the renderer worker.
export const triggerCreateUtilityProcess = (
    _type: UtilityProcessType,
    window: BrowserWindow,
) => triggerCreateMLUtilityProcess(window);

const terminateMLProcessIfRunning = () => {
    if (_utilityProcessML) {
        log.debug(() => "Terminating running ML utility process");
        _utilityProcessML.removeAllListeners("exit");
        _utilityProcessML.kill();
        _utilityProcessML = undefined;
    }
};

// Pipe stdio because failures before log-worker loads are otherwise invisible
// in packaged apps.
const forkWatchedUtilityProcess = (scriptName: string, logTag: string) => {
    const child = utilityProcess.fork(path.join(__dirname, scriptName), [], {
        stdio: "pipe",
    });
    child.stdout?.on("data", (chunk: Buffer) =>
        log.info(`${logTag} ${String(chunk).trimEnd()}`),
    );
    child.stderr?.on("data", (chunk: Buffer) =>
        log.warn(`${logTag} ${String(chunk).trimEnd()}`),
    );
    child.on("exit", (code) => {
        log.error(`${logTag} utility process exited with code ${code}`);
    });
    return child;
};

// Electron tears these down on quit; those exits are not failures.
app.on("before-quit", () => {
    _utilityProcessML?.removeAllListeners("exit");
    _utilityProcessFFmpeg?.removeAllListeners("exit");
});

export const triggerCreateMLUtilityProcess = (window: BrowserWindow) => {
    terminateMLProcessIfRunning();

    const { port1, port2 } = new MessageChannelMain();

    const child = forkWatchedUtilityProcess("ml-worker.js", "[ml-worker]");
    const userDataPath = app.getPath("userData");
    child.postMessage({ userDataPath, mlNativePaths: mlNativePaths() }, [
        port1,
    ]);

    window.webContents.postMessage("utilityProcessPort/ml", undefined, [port2]);

    handleMessagesFromMLUtilityProcess(child);

    _utilityProcessML = child;
};

const handleMessagesFromMLUtilityProcess = (child: UtilityProcess) => {
    child.on("message", (m: unknown) => {
        if (processUtilityProcessLogMessage("[ml-worker]", m)) {
            return;
        }
        log.info("Ignoring unknown message from ML utility process", m);
    });
};

// FFmpeg file setup stays in main because Electron's app API is unavailable in
// utility processes.
export const ffmpegUtilityProcessEndpoint = () =>
    (_utilityProcessFFmpegEndpoint ??= createFFmpegUtilityProcessEndpoint());

const terminateFFmpegProcessIfRunning = () => {
    if (_utilityProcessFFmpeg) {
        log.debug(() => "Terminating running FFmpeg utility process");
        _utilityProcessFFmpeg.removeAllListeners("exit");
        _utilityProcessFFmpeg.kill();
        _utilityProcessFFmpeg = undefined;
        _utilityProcessFFmpegEndpoint = undefined;
    }
};

const createFFmpegUtilityProcessEndpoint = () => {
    if (_utilityProcessFFmpeg) {
        throw new Error("FFmpeg utility process is already running");
    }

    let resolve: ((endpoint: Endpoint) => void) | undefined;
    let reject: ((e: Error) => void) | undefined;
    const promise = new Promise<Endpoint>((res, rej) => {
        resolve = res;
        reject = rej;
    });

    const { port1, port2 } = new MessageChannelMain();

    const child = forkWatchedUtilityProcess(
        "ffmpeg-worker.js",
        "[ffmpeg-worker]",
    );

    const appVersion = app.getVersion();
    const ffmpegPath = path.join(
        app.isPackaged
            ? process.resourcesPath
            : path.join(app.getAppPath(), "build"),
        "ffmpeg",
        process.platform == "win32" ? "ffmpeg.exe" : "ffmpeg",
    );
    child.postMessage({ appVersion, ffmpegPath }, [port1]);

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

    child.on("exit", () => {
        reject?.(new Error("The FFmpeg utility process exited"));
        _utilityProcessFFmpeg = undefined;
        _utilityProcessFFmpegEndpoint = undefined;
    });

    return promise;
};
