import { isNamedError, namedError } from "ente-base/error";
import { lowercaseExtension } from "ente-base/file-name";
import {
    FileType,
    KnownFileTypeInfos,
    KnownNonMediaFileExtensions,
    type FileTypeInfo,
} from "ente-media/file-type";
import { fileTypeFromBuffer } from "file-type";

export const detectFileTypeInfo = async (file: File): Promise<FileTypeInfo> =>
    detectFileTypeInfoFromChunk(() => readInitialChunkOfFile(file), file.name);

export const detectFileTypeInfoFromChunk = async (
    readInitialChunk: () => Promise<Uint8Array | undefined>,
    fileNameOrPath: string,
): Promise<FileTypeInfo> => {
    try {
        const typeResult = await detectFileTypeFromBuffer(
            (await readInitialChunk())!,
        );

        const mimeType = typeResult.mime;

        let fileType: FileType;
        if (mimeType.startsWith("image/")) {
            fileType = FileType.image;
        } else if (mimeType.startsWith("video/")) {
            fileType = FileType.video;
        } else {
            throw fileTypeNotSupportedError(
                `Unsupported file format (MIME type ${mimeType})`,
            );
        }

        return { fileType, extension: typeResult.ext, mimeType };
    } catch (e) {
        const extension = lowercaseExtension(fileNameOrPath);
        const known = KnownFileTypeInfos.find((f) => f.extension == extension);
        if (known) return known;

        if (extension && KnownNonMediaFileExtensions.includes(extension)) {
            throw fileTypeNotSupportedError(
                `Unsupported file format (extension ${extension})`,
                { cause: e },
            );
        }

        throw e;
    }
};

export const isFileTypeNotSupportedError = (e: unknown) =>
    isNamedError(e, "file_type_not_supported");

const fileTypeNotSupportedError = (message: string, options?: ErrorOptions) =>
    namedError("file_type_not_supported", message, options);

const readInitialChunkOfFile = async (file: File) => {
    const chunkSizeForTypeDetection = 4100;
    const chunk = file.slice(0, chunkSizeForTypeDetection);
    return new Uint8Array(await chunk.arrayBuffer());
};

const detectFileTypeFromBuffer = async (buffer: Uint8Array) => {
    const result = await fileTypeFromBuffer(buffer);
    if (!result)
        throw Error("Could not deduce file type from the file's contents");
    return result;
};
