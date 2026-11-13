import {
    fileNameFromComponents,
    lowercaseExtension,
    nameAndExtension,
} from "ente-base/file-name";
import { mergeUint8Arrays } from "ente-utils/array";
import { ensureArrayBufferBacked } from "ente-utils/bytes";
import JSZip, { type JSZipObject, type JSZipStreamHelper } from "jszip";
import { FileType } from "./file-type";

const maxExpandedArchiveRatio = 20;
const maxExpandedArchiveOverhead = 16 * 1024 * 1024;
const livePhotoEntryPattern = /^(image|video)(?:\.[a-zA-Z0-9]{1,16})?$/;

type StreamableZipObject = JSZipObject & {
    internalStream(type: "uint8array"): JSZipStreamHelper<Uint8Array>;
};

const potentialImageExtensions = [
    "heic",
    "heif",
    "jpeg",
    "jpg",
    "png",
    "gif",
    "bmp",
    "tiff",
    "webp",
];

const potentialVideoExtensions = [
    "mov",
    "mp4",
    "m4v",
    "avi",
    "wmv",
    "flv",
    "mkv",
    "webm",
    "3gp",
    "3g2",
    "ogv",
    "mpg",
    "mp",
];

export const potentialFileTypeFromExtension = (
    fileName: string,
): FileType | undefined => {
    const ext = lowercaseExtension(fileName);
    if (!ext) return undefined;

    if (potentialImageExtensions.includes(ext)) return FileType.image;
    else if (potentialVideoExtensions.includes(ext)) return FileType.video;
    else return undefined;
};

interface LivePhoto {
    imageFileName: string;
    imageData: Uint8Array<ArrayBuffer>;
    videoFileName: string;
    videoData: Uint8Array<ArrayBuffer>;
}

export const decodeLivePhoto = async (
    fileName: string,
    zipBlob: Blob,
): Promise<LivePhoto> => {
    const zip = await JSZip.loadAsync(await zipBlob.arrayBuffer());
    const entries = Object.values(zip.files);
    let imageEntry, videoEntry: JSZipObject | undefined;
    if (entries.length != 2)
        throw new Error("Live Photo must contain one image and one video");
    for (const entry of entries) {
        const match = livePhotoEntryPattern.exec(entry.name);
        if (
            entry.dir ||
            match?.[0] !== entry.name ||
            entry.unsafeOriginalName !== entry.name
        )
            throw new Error("Invalid Live Photo component name");
        if (match[1] === "image") imageEntry = entry;
        else videoEntry = entry;
    }
    if (!imageEntry || !videoEntry)
        throw new Error("Live Photo must contain one image and one video");

    const limit =
        zipBlob.size * maxExpandedArchiveRatio + maxExpandedArchiveOverhead;
    const imageData = await readLivePhotoEntry(imageEntry, limit);
    const videoData = await readLivePhotoEntry(
        videoEntry,
        limit - imageData.length,
    );
    const [name] = nameAndExtension(fileName);
    const [, imageExt] = nameAndExtension(imageEntry.name);
    const [, videoExt] = nameAndExtension(videoEntry.name);
    return {
        imageFileName: fileNameFromComponents([name, imageExt]),
        imageData,
        videoFileName: fileNameFromComponents([name, videoExt]),
        videoData,
    };
};

const readLivePhotoEntry = (
    entry: JSZipObject,
    limit: number,
): Promise<Uint8Array<ArrayBuffer>> =>
    new Promise((resolve, reject) => {
        const stream = (entry as StreamableZipObject).internalStream(
            "uint8array",
        );
        const chunks: Uint8Array[] = [];
        let length = 0;
        let settled = false;
        const fail = (error: Error) => {
            if (settled) return;
            settled = true;
            stream.pause();
            chunks.length = 0;
            reject(error);
        };
        stream
            .on("data", (chunk) => {
                if (settled) return;
                if (chunk.length > limit - length) {
                    fail(new Error("Live Photo archive expands beyond limit"));
                    return;
                }
                length += chunk.length;
                chunks.push(chunk);
            })
            .on("error", fail)
            .on("end", () => {
                if (settled) return;
                try {
                    const data = mergeUint8Arrays(chunks);
                    chunks.length = 0;
                    settled = true;
                    resolve(data);
                } catch (error) {
                    fail(error as Error);
                }
            })
            .resume();
    });

interface EncodeLivePhotoInput {
    imageFileName: string;
    imageFileOrData: File | Uint8Array;
    videoFileName: string;
    videoFileOrData: File | Uint8Array;
}

export const encodeLivePhoto = async ({
    imageFileName,
    imageFileOrData,
    videoFileName,
    videoFileOrData,
}: EncodeLivePhotoInput): Promise<Uint8Array<ArrayBuffer>> => {
    const [, imageExt] = nameAndExtension(imageFileName);
    const [, videoExt] = nameAndExtension(videoFileName);

    const zip = new JSZip();
    zip.file(fileNameFromComponents(["image", imageExt]), imageFileOrData);
    zip.file(fileNameFromComponents(["video", videoExt]), videoFileOrData);
    return ensureArrayBufferBacked(
        await zip.generateAsync({ type: "uint8array" }),
    );
};
