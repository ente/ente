import { net, protocol, type BrowserWindow } from "electron/main";
import { randomUUID } from "node:crypto";
import fs from "node:fs/promises";
import { Writable } from "node:stream";
import { pathToFileURL } from "node:url";
import log from "./log";
import { ffmpegUtilityProcess } from "./services/ffmpeg";
import { type FFmpegGenerateHLSPlaylistAndSegmentsResult } from "./services/ffmpeg-worker";
import { markClosableZip, openZip } from "./services/zip";
import { writeStream } from "./utils/stream";
import {
    deleteTempFile,
    deleteTempFileIgnoringErrors,
    makeFileForStreamOrPathOrZipItem,
    makeTempFilePath,
} from "./utils/temp";

// This protocol avoids contextBridge's buffer copies for large files.
export const registerStreamProtocol = (mainWindow: BrowserWindow) => {
    protocol.handle("stream", async (request: Request) => {
        try {
            return await handleStreamRequest(mainWindow, request);
        } catch (e) {
            log.error("Failed to handle stream request", e);
            return new Response("Internal stream error", { status: 500 });
        }
    });
};

const rendererOrigin = "ente://app";

const handleStreamRequest = async (
    mainWindow: BrowserWindow,
    request: Request,
): Promise<Response> => {
    // Custom-scheme requests omit Origin and Referer, so gate them by the
    // document loaded in the app's only window.
    const windowURL = mainWindow.webContents.getURL();
    if (
        windowURL != rendererOrigin &&
        !windowURL.startsWith(`${rendererOrigin}/`)
    )
        return new Response("", { status: 403 });

    const { host, searchParams } = new URL(request.url);
    if (
        request.method == "OPTIONS" &&
        host == "video" &&
        searchParams.get("op") == "generate-hls"
    ) {
        return new Response(null, {
            status: 204,
            headers: {
                "Access-Control-Allow-Origin": rendererOrigin,
                "Access-Control-Allow-Methods": "POST",
                "Access-Control-Allow-Headers": "X-Auth-Token",
            },
        });
    }

    switch (host) {
        case "read":
            return handleRead(searchParams.get("path")!);

        case "read-zip":
            return handleReadZip(
                searchParams.get("zipPath")!,
                searchParams.get("entryName")!,
            );

        case "write":
            return handleWrite(searchParams.get("path")!, request);

        case "video": {
            const op = searchParams.get("op");
            if (op) {
                switch (op) {
                    case "convert-to-mp4":
                        return handleConvertToMP4Write(request);
                    case "generate-hls":
                        return handleGenerateHLSWrite(request, searchParams);
                    default:
                        return new Response(`Unknown op ${op}`, {
                            status: 404,
                        });
                }
            }

            const token = searchParams.get("token");
            const done = searchParams.get("done") !== null;
            if (!token) {
                return new Response("Missing token", { status: 404 });
            }

            return done ? handleVideoDone(token) : handleVideoRead(token);
        }

        default:
            return new Response("", { status: 404 });
    }
};

const handleRead = async (path: string) => {
    const res = await net.fetch(pathToFileURL(path).toString());
    if (res.ok) {
        const stat = await fs.stat(path);

        const fileSize = stat.size;
        res.headers.set("Content-Length", `${fileSize}`);

        const mtimeMs = stat.mtime.getTime();
        res.headers.set("X-Last-Modified-Ms", `${mtimeMs}`);
    }
    return res;
};

const handleReadZip = async (zipPath: string, entryName: string) => {
    const zip = openZip(zipPath);
    const entry = await zip.entry(entryName);
    if (!entry) {
        markClosableZip(zipPath);
        return new Response("", { status: 404 });
    }

    const { writable, readable } = new TransformStream();
    const stream = await zip.stream(entry);

    // Node and DOM disagree about WritableStream.close's Promise return.
    // eslint-disable-next-line @typescript-eslint/no-unsafe-argument, @typescript-eslint/no-explicit-any
    const nodeWritable = Writable.fromWeb(writable as any);
    stream.pipe(nodeWritable);

    nodeWritable.on("error", (e: unknown) => {
        // Closing the response body early aborts the writable side.
        if (e instanceof Error && e.name == "AbortError") return;
        log.error("Error event for the writable end of zip stream", e);
    });

    nodeWritable.on("close", () => {
        markClosableZip(zipPath);
    });

    // node-stream-zip's parseZipTime returns epoch milliseconds.
    const modifiedMs = entry.time;

    return new Response(readable, {
        headers: {
            "Content-Type": "application/octet-stream",
            "Content-Length": `${entry.size}`,
            "X-Last-Modified-Ms": `${modifiedMs}`,
        },
    });
};

const handleWrite = async (path: string, request: Request) => {
    await writeStream(path, request.body!);
    return new Response("", { status: 200 });
};

// Chromium cannot stream both halves of one fetch. Video operations return a
// token for a second read request; a final done request releases the temp file.
const pendingVideoResults = new Map<string, string>();

export const clearPendingVideoResults = () => pendingVideoResults.clear();

const handleConvertToMP4Write = async (request: Request) => {
    const worker = await ffmpegUtilityProcess();

    const inputTempFilePath = await makeTempFilePath();
    await writeStream(inputTempFilePath, request.body!);

    const outputTempFilePath = await makeTempFilePath("mp4");
    try {
        await worker.ffmpegConvertToMP4(inputTempFilePath, outputTempFilePath);
    } catch (e) {
        log.error("Conversion to MP4 failed", e);
        await deleteTempFileIgnoringErrors(outputTempFilePath);
        throw e;
    } finally {
        await deleteTempFileIgnoringErrors(inputTempFilePath);
    }

    const token = randomUUID();
    pendingVideoResults.set(token, outputTempFilePath);
    return new Response(token, { status: 200 });
};

const handleVideoRead = async (token: string) => {
    const filePath = pendingVideoResults.get(token);
    if (!filePath)
        return new Response(`Unknown token ${token}`, { status: 404 });

    return net.fetch(pathToFileURL(filePath).toString());
};

const handleVideoDone = async (token: string) => {
    const filePath = pendingVideoResults.get(token);
    if (!filePath)
        return new Response(`Unknown token ${token}`, { status: 404 });

    await deleteTempFile(filePath);

    pendingVideoResults.delete(token);
    return new Response("", { status: 200 });
};

const handleGenerateHLSWrite = async (
    request: Request,
    params: URLSearchParams,
) => {
    const fileID = parseInt(params.get("fileID") ?? "", 10);
    const fetchURL = params.get("fetchURL");
    const authToken = request.headers.get("X-Auth-Token");
    const previewUploadV2 = params.get("previewUploadV2") == "true";
    if (!fileID || !fetchURL || !authToken)
        return new Response("Invalid generate HLS request", { status: 400 });

    let inputItem: Parameters<typeof makeFileForStreamOrPathOrZipItem>[0];
    const path = params.get("path");
    if (path) {
        inputItem = path;
    } else {
        const zipPath = params.get("zipPath");
        const entryName = params.get("entryName");
        if (zipPath && entryName) {
            inputItem = [zipPath, entryName];
        } else {
            const body = request.body;
            if (!body) throw new Error("Missing body");
            inputItem = body;
        }
    }

    const worker = await ffmpegUtilityProcess();

    const {
        path: inputFilePath,
        isFileTemporary: isInputFileTemporary,
        writeToTemporaryFile: writeToTemporaryInputFile,
    } = await makeFileForStreamOrPathOrZipItem(inputItem);

    const outputFilePathPrefix = await makeTempFilePath();
    let result: FFmpegGenerateHLSPlaylistAndSegmentsResult | undefined;
    try {
        await writeToTemporaryInputFile();

        result = await worker.ffmpegGenerateHLSPlaylistAndSegments(
            inputFilePath,
            outputFilePathPrefix,
            fileID,
            fetchURL,
            authToken,
            previewUploadV2,
        );

        if (!result) {
            return new Response(null, { status: 204 });
        }

        const { playlistPath, dimensions, videoSize, videoObjectID } = result;

        const playlistToken = randomUUID();
        pendingVideoResults.set(playlistToken, playlistPath);

        return new Response(
            JSON.stringify({
                playlistToken,
                dimensions,
                videoSize,
                videoObjectID,
            }),
            { status: 200 },
        );
    } finally {
        if (isInputFileTemporary)
            await deleteTempFileIgnoringErrors(inputFilePath);
    }
};
