import type { Electron, ElectronMLWorker, ZipItem } from "ente-base/types/ipc";
import { z } from "zod";
import type { FileSystemUploadItem } from "../services/upload";

declare global {
    interface RequestInit {
        // Chromium requires this for streamed request bodies.
        duplex?: "half";
    }
}

// Electron arguments prove these are desktop calls.
// The native protocol handlers do not otherwise use them.
export const readStream = async (
    _: Electron | ElectronMLWorker,
    pathOrZipItem: string | ZipItem,
): Promise<{ response: Response; size: number; lastModifiedMs: number }> => {
    let url: URL;
    if (typeof pathOrZipItem == "string") {
        const params = new URLSearchParams({ path: pathOrZipItem });
        url = new URL(`stream://read?${params.toString()}`);
    } else {
        const [zipPath, entryName] = pathOrZipItem;
        const params = new URLSearchParams({ zipPath, entryName });
        url = new URL(`stream://read-zip?${params.toString()}`);
    }

    const req = new Request(url, { method: "GET" });

    const res = await fetch(req);
    if (!res.ok)
        throw new Error(
            `Failed to read stream from ${url.href}: HTTP ${res.status}`,
        );

    const size = readNumericHeader(res, "Content-Length");
    const lastModifiedMs = readNumericHeader(res, "X-Last-Modified-Ms");

    return { response: res, size, lastModifiedMs };
};

const readNumericHeader = (res: Response, key: string) => {
    const valueText = res.headers.get(key);
    const value = valueText === null ? NaN : +valueText;
    if (isNaN(value))
        throw new Error(
            `Expected a numeric ${key} when reading a stream response, instead got ${valueText}`,
        );
    return value;
};

export const writeStream = async (
    _: Electron,
    path: string,
    stream: ReadableStream | null,
) => {
    const params = new URLSearchParams({ path });
    const url = new URL(`stream://write?${params.toString()}`);

    const req = new Request(url, {
        method: "POST",
        duplex: "half",
        body: stream,
    });

    const res = await fetch(req);
    if (!res.ok)
        throw new Error(
            `Failed to write stream to ${url.href}: HTTP ${res.status}`,
        );
};

export const initiateConvertToMP4 = async (
    _: Electron,
    video: Blob,
): Promise<string> => {
    const url = "stream://video?op=convert-to-mp4";
    const res = await fetch(url, { method: "POST", body: video });
    if (!res.ok)
        throw new Error(`Failed to write stream to ${url}: HTTP ${res.status}`);
    return res.text();
};

const GenerateHLSResult = z.object({
    playlistToken: z.string(),
    dimensions: z.object({ width: z.number(), height: z.number() }),
    videoSize: z.number(),
    videoObjectID: z.string(),
});

export type GenerateHLSResult = z.infer<typeof GenerateHLSResult>;

export const initiateGenerateHLS = async (
    _: Electron,
    video: FileSystemUploadItem | ReadableStream,
    fileID: number,
    fetchURL: string,
    authToken: string,
): Promise<GenerateHLSResult | undefined> => {
    const params = new URLSearchParams({
        op: "generate-hls",
        fileID: fileID.toString(),
        fetchURL,
    });

    let body: ReadableStream | null;
    if (video instanceof ReadableStream) {
        body = video;
    } else {
        body = null;
        if (typeof video == "string") {
            params.set("path", video);
        } else if (Array.isArray(video)) {
            const [zipPath, entryName] = video;
            params.set("zipPath", zipPath);
            params.set("entryName", entryName);
        } else {
            params.set("path", video.path);
        }
    }

    const url = `stream://video?${params.toString()}`;
    const res = await fetch(url, {
        method: "POST",
        headers: { "X-Auth-Token": authToken },
        duplex: "half",
        body,
    });
    if (!res.ok) throw new Error(`Failed to generate HLS: HTTP ${res.status}`);

    // 204 means the original video can be streamed as-is.
    if (res.status == 204) return undefined;

    return GenerateHLSResult.parse(await res.json());
};

export const readVideoStream = async (
    _: Electron,
    token: string,
): Promise<Response> => {
    const params = new URLSearchParams({ token });
    const url = new URL(`stream://video?${params.toString()}`);

    const req = new Request(url, { method: "GET" });

    const res = await fetch(req);
    if (!res.ok)
        throw new Error(
            `Failed to read stream from ${url.href}: HTTP ${res.status}`,
        );

    return res;
};

// Call this after readVideoStream so native temporary files are released.
export const videoStreamDone = async (
    _: Electron,
    token: string,
): Promise<void> => {
    // Native checks only for the presence of done.
    const params = new URLSearchParams({ token, done: "1" });
    const url = new URL(`stream://video?${params.toString()}`);

    const req = new Request(url, { method: "GET" });
    const res = await fetch(req);
    if (!res.ok)
        throw new Error(
            `Failed to close stream at ${url.href}: HTTP ${res.status}`,
        );
};
