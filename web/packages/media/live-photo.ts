import { ensureArrayBufferBacked } from "ente-base/bytes";
import {
    fileNameFromComponents,
    lowercaseExtension,
    nameAndExtension,
} from "ente-base/file-name";
import JSZip from "jszip";
import { FileType } from "./file-type";

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
    let imageFileName, videoFileName: string | undefined;
    let imageData, videoData: Uint8Array<ArrayBuffer> | undefined;

    const [name] = nameAndExtension(fileName);
    const zip = await JSZip.loadAsync(zipBlob, { createFolders: true });

    for (const zipFileName in zip.files) {
        if (zipFileName.startsWith("image")) {
            const [, imageExt] = nameAndExtension(zipFileName);
            imageFileName = fileNameFromComponents([name, imageExt]);
            const bytes = await zip.files[zipFileName]?.async("uint8array");
            imageData = bytes && ensureArrayBufferBacked(bytes);
        } else if (zipFileName.startsWith("video")) {
            const [, videoExt] = nameAndExtension(zipFileName);
            videoFileName = fileNameFromComponents([name, videoExt]);
            const bytes = await zip.files[zipFileName]?.async("uint8array");
            videoData = bytes && ensureArrayBufferBacked(bytes);
        }
    }

    if (!imageFileName || !imageData)
        throw new Error(
            `Decoded live photo ${fileName} does not have an image`,
        );

    if (!videoFileName || !videoData)
        throw new Error(`Decoded live photo ${fileName} does not have a video`);

    return { imageFileName, imageData, videoFileName, videoData };
};

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
