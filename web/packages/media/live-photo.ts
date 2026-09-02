import {
    fileNameFromComponents,
    lowercaseExtension,
    nameAndExtension,
} from "ente-base/file-name";
import { ensureArrayBufferBacked } from "ente-utils/bytes";
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
