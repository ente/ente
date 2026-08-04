import { lowercaseExtension } from "ente-base/file-name";
import { KnownFileTypeInfos } from "ente-media/file-type";
import { fileTypeFromBuffer } from "file-type";

export const detectMediaMIMEType = async (file: File) => {
    const chunkSizeForTypeDetection = 4100;
    const fileChunk = file.slice(0, chunkSizeForTypeDetection);
    const chunk = new Uint8Array(await fileChunk.arrayBuffer());
    const result = await fileTypeFromBuffer(chunk);

    const mime = result?.mime;
    if (mime) {
        if (mime.startsWith("image/") || mime.startsWith("video/")) return mime;
        else throw new Error(`Detected MIME type ${mime} is not a media file`);
    }

    const ext = lowercaseExtension(file.name);
    if (!ext) return undefined;
    return KnownFileTypeInfos.find((f) => f.extension == ext)?.mimeType;
};
