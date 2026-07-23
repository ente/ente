/**
 * @file stream data to-from renderer using a custom protocol handler.
 */
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

/**
 * Register a protocol handler that we use for streaming large files between the
 * main (Node.js) and renderer (Chromium) processes.
 *
 * [Note: IPC streams]
 *
 * When running without node integration, there is no direct way to pass streams
 * across IPC. And passing the entire contents of the file is not feasible for
 * large video files because of the memory pressure the copying would entail.
 *
 * As an alternative, we register a custom protocol handler that can provides a
 * bi-directional stream. The renderer can stream data to the node side by
 * streaming the request. The node side can stream to the renderer side by
 * streaming the response.
 *
 * The stream is not full duplex - while both reads and writes can be streamed,
 * they need to be streamed separately.
 *
 * See also: [Note: Transferring large amount of data over IPC]
 *
 * Depends on {@link registerPrivilegedSchemes}.
 */
export const registerStreamProtocol = (mainWindow: BrowserWindow) => {
    protocol.handle("stream", (request: Request) => {
        try {
            return handleStreamRequest(mainWindow, request);
        } catch (e) {
            log.error(`Failed to handle stream request for ${request.url}`, e);
            return new Response(String(e), { status: 500 });
        }
    });
};

const rendererOrigin = "ente://app";

const handleStreamRequest = async (
    mainWindow: BrowserWindow,
    request: Request,
): Promise<Response> => {
    // Electron strips Origin/Referer from custom-scheme requests, so we cannot
    // identify the caller from the request itself. Instead gate on the main
    // window's current URL: only honor stream requests while our own renderer
    // (and not, say, a payment page it navigated to) is the loaded document.
    const windowURL = mainWindow.webContents.getURL();
    if (
        windowURL != rendererOrigin &&
        !windowURL.startsWith(`${rendererOrigin}/`)
    )
        return new Response("", { status: 403 });

    const url = request.url;
    // The request URL contains the command to run as the host, and the
    // pathname of the file(s) as the search params.
    const { host, searchParams } = new URL(url);
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
        // net.fetch already seems to add "Content-Type" and "Last-Modified"
        // headers, but I couldn't find documentation for this. In any case,
        // since we already are stat-ting the file for the "Content-Length", we
        // explicitly add the "X-Last-Modified-Ms" too,
        //
        // 1. Guaranteeing its presence,
        //
        // 2. Having it be in the exact format we want (no string <-> date
        //    conversions),
        //
        // 3. Retaining milliseconds.

        const stat = await fs.stat(path);

        // Add the file's size as the Content-Length header.
        const fileSize = stat.size;
        res.headers.set("Content-Length", `${fileSize}`);

        // Add the file's last modified time (as epoch milliseconds).
        // See: [Note: Integral last modified time]
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

    // zip.stream returns an "old style" NodeJS.ReadableStream. We then write it
    // to the writable end of the web stream pipe, the readable end of which is
    // relayed back to the renderer as the response.
    const { writable, readable } = new TransformStream();
    const stream = await zip.stream(entry);

    // Silence a type error about the Promise<void> returned by the close method
    // of writable as not being assignable to Promise<undefined> which started
    // appearing after updating to TypeScript 5.8.
    //
    // eslint-disable-next-line @typescript-eslint/no-unsafe-argument, @typescript-eslint/no-explicit-any
    const nodeWritable = Writable.fromWeb(writable as any);
    stream.pipe(nodeWritable);

    nodeWritable.on("error", (e: unknown) => {
        // If the renderer process closes the network connection (say when it
        // only needs the content-length and doesn't care about the body), we
        // get an AbortError. Handle them here otherwise they litter the logs
        // with unhandled exceptions.
        if (e instanceof Error && e.name == "AbortError") return;
        log.error("Error event for the writable end of zip stream", e);
    });

    nodeWritable.on("close", () => {
        markClosableZip(zipPath);
    });

    // While it is documented that entry.time is the modification time,
    // the units are not mentioned. By seeing the source code, we can
    // verify that it is indeed epoch milliseconds. See `parseZipTime`
    // in the node-stream-zip source,
    // https://github.com/antelle/node-stream-zip/blob/master/node_stream_zip.js
    const modifiedMs = entry.time;

    return new Response(readable, {
        headers: {
            // We don't know the exact type, but it doesn't really matter, just
            // set it to a generic binary content-type so that the browser
            // doesn't tinker with it thinking of it as text.
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

/**
 * A map from token to file paths generated as a result of stream://video
 * requests we have received.
 */
const pendingVideoResults = new Map<string, string>();

/**
 * Clear any in-memory state for in-flight streamed video processing requests.
 * Meant to be called during logout.
 */
export const clearPendingVideoResults = () => pendingVideoResults.clear();

/**
 * [Note: Convert to MP4]
 *
 * When we want to convert a video to MP4, if we were to send the entire
 * contents of the video from the renderer to the main process over IPC, it just
 * causes the renderer to run out of memory and restart when the videos are very
 * large. So we need to stream the original video renderer → main and then
 * stream back the converted video renderer ← main.
 *
 * Currently Chromium does not support bi-directional streaming ("full" duplex
 * mode for the Web fetch API). So we need to simulate that using two different
 * streaming requests.
 *
 *     renderer → main  stream://video?op=convert-to-mp4
 *                      → request.body is the original video
 *                      ← response is [token]
 *
 *     renderer → main  stream://video?token=<token>
 *                      ← response.body is the converted video
 *
 *     renderer → main  stream://video?token=<token>&done
 *                      ← 200 OK
 *
 * Note that the conversion itself is not streaming. The conversion still
 * happens in a single invocation of ffmpeg, we are just streaming the data
 * across the IPC boundary to allow us to pass large amounts of data without
 * running out of memory.
 *
 * See also: [Note: IPC streams]
 */
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

/**
 * Generate a HLS playlist for the given video.
 *
 * See: [Note: Convert to MP4] for the general architecture of commands that do
 * renderer <-> main I/O using streams.
 *
 * The difference here is that we the conversion generates two streams^ - one
 * for the HLS playlist itself, and one for the file containing the encrypted
 * and transcoded video chunks. The video stream we write to the pre-signed
 * object upload URL(s), and then we return a JSON object containing the token
 * for the playlist, and other metadata for use by the renderer.
 *
 * ^ if the video doesn't require a stream to be generated (e.g. it is very
 *   small and already uses a compatible codec) then a HTT 204 is returned and
 *   no stream is generated.
 */
const handleGenerateHLSWrite = async (
    request: Request,
    params: URLSearchParams,
) => {
    const fileID = parseInt(params.get("fileID") ?? "", 10);
    const fetchURL = params.get("fetchURL");
    const authToken = params.get("authToken");
    if (!fileID || !fetchURL || !authToken) throw new Error("Missing params");

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
        );

        if (!result) {
            // This video doesn't require stream generation.
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
