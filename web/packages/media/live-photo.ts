import { ensureArrayBufferBacked } from "ente-base/bytes";
import {
    fileNameFromComponents,
    lowercaseExtension,
    nameAndExtension,
} from "ente-base/file-name";
import JSZip, { type JSZipObject } from "jszip";
import { FileType } from "./file-type";

const maxExpandedArchiveRatio = 20;
const maxExpandedArchiveOverhead = 16 * 1024 * 1024;
const livePhotoEntryPattern = /^(image|video)(?:\.[A-Za-z0-9]{1,16})?$/;

interface ZipEntryStream {
    on(event: "data", listener: (data: Uint8Array) => void): ZipEntryStream;
    on(event: "error", listener: (error: Error) => void): ZipEntryStream;
    on(event: "end", listener: () => void): ZipEntryStream;
    pause(): ZipEntryStream;
    resume(): ZipEntryStream;
}

type StreamableZipObject = JSZipObject & {
    // JSZip's runtime exposes its browser stream helper, but its declarations
    // only include the Node stream wrapper.
    internalStream(type: "uint8array"): ZipEntryStream;
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
    "avi",
    "ogv",
    "mpg",
    "mp",
];

/**
 * Use the file extension of the given {@link fileName} to deduce if is is
 * potentially the image or the video part of a Live Photo.
 */
export const potentialFileTypeFromExtension = (
    fileName: string,
): FileType | undefined => {
    const ext = lowercaseExtension(fileName);
    if (!ext) return undefined;

    if (potentialImageExtensions.includes(ext)) return FileType.image;
    else if (potentialVideoExtensions.includes(ext)) return FileType.video;
    else return undefined;
};

/**
 * An in-memory representation of a live photo.
 */
interface LivePhoto {
    imageFileName: string;
    imageData: Uint8Array<ArrayBuffer>;
    videoFileName: string;
    videoData: Uint8Array<ArrayBuffer>;
}

/**
 * Convert a binary serialized representation of a live photo to an in-memory
 * {@link LivePhoto}.
 *
 * A live photo is a zip file containing two files - an image and a video. This
 * functions reads that zip file (blob), and return separate bytes (and
 * filenames) for the image and video parts.
 *
 * @param fileName The name of the overall live photo. Both the image and video
 * parts of the decompressed live photo use this as their name, combined with
 * their original extensions.
 *
 * @param zipBlob A blob contained the zipped data (i.e. the binary serialized
 * live photo).
 */
export const decodeLivePhoto = async (
    fileName: string,
    zipBlob: Blob,
): Promise<LivePhoto> => {
    let imageEntry, videoEntry: JSZipObject | undefined;

    const [name] = nameAndExtension(fileName);
    const zip = await JSZip.loadAsync(zipBlob, { createFolders: true });

    for (const entry of Object.values(zip.files)) {
        if (entry.dir)
            throw new Error("Live Photo archives may only contain files");

        const match = livePhotoEntryPattern.exec(entry.name);
        if (!match)
            throw new Error(
                `Unexpected Live Photo archive entry: ${entry.name}`,
            );

        if (match[1] === "image") {
            if (imageEntry)
                throw new Error("Live Photo archive contains multiple images");
            imageEntry = entry;
        } else {
            if (videoEntry)
                throw new Error("Live Photo archive contains multiple videos");
            videoEntry = entry;
        }
    }

    if (!imageEntry || !videoEntry)
        throw new Error(
            "Live Photo archive must contain one image and one video",
        );

    const maxExpandedSize =
        zipBlob.size * maxExpandedArchiveRatio + maxExpandedArchiveOverhead;
    const imageData = await readCappedEntry(imageEntry, maxExpandedSize);
    const videoData = await readCappedEntry(
        videoEntry,
        maxExpandedSize - imageData.length,
    );

    const [, imageExt] = nameAndExtension(imageEntry.name);
    const [, videoExt] = nameAndExtension(videoEntry.name);
    return {
        imageFileName: fileNameFromComponents([name, imageExt]),
        imageData,
        videoFileName: fileNameFromComponents([name, videoExt]),
        videoData,
    };
};

const readCappedEntry = (
    entry: JSZipObject,
    maxLength: number,
): Promise<Uint8Array<ArrayBuffer>> =>
    new Promise((resolve, reject) => {
        const chunks: Uint8Array[] = [];
        let length = 0;
        let settled = false;
        const stream = (entry as StreamableZipObject).internalStream(
            "uint8array",
        );

        const rejectOnce = (error: unknown) => {
            if (settled) return;
            settled = true;
            stream.pause();
            reject(
                error instanceof Error
                    ? error
                    : new Error("Failed to decode Live Photo archive"),
            );
        };

        stream
            .on("data", (chunk: Uint8Array) => {
                length += chunk.length;
                if (length > maxLength) {
                    rejectOnce(
                        new Error("Live Photo archive expands beyond limit"),
                    );
                    return;
                }
                chunks.push(chunk);
            })
            .on("error", rejectOnce)
            .on("end", () => {
                if (settled) return;
                settled = true;
                const data = new Uint8Array(length);
                let offset = 0;
                for (const chunk of chunks) {
                    data.set(chunk, offset);
                    offset += chunk.length;
                }
                resolve(ensureArrayBufferBacked(data));
            })
            .resume();
    });

/** Variant of {@link LivePhoto}, but one that allows files and data. */
interface EncodeLivePhotoInput {
    imageFileName: string;
    imageFileOrData: File | Uint8Array;
    videoFileName: string;
    videoFileOrData: File | Uint8Array;
}

/**
 * Return a binary serialized representation of a live photo.
 *
 * This function takes the (in-memory) image and video data from the
 * {@link livePhoto} object, writes them to a zip file (using the respective
 * filenames), and returns the {@link Uint8Array} that represent the bytes of
 * this zip file.
 *
 * @param livePhoto The in-mem photo to serialized.
 */
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
