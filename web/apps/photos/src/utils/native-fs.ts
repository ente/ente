import { joinPath, nameAndExtension } from "ente-base/file-name";
import {
    exportMetadataDirectoryName,
    exportTrashDirectoryName,
} from "ente-gallery/export-dirs";
import sanitize from "sanitize-filename";

export const sanitizeFilename = (s: string) =>
    sanitize(s, { replacement: "_" });

export const safeDirectoryName = async (
    directoryPath: string,
    name: string,
    exists: (path: string) => Promise<boolean>,
): Promise<string> => {
    const specialDirectoryNames = [
        exportTrashDirectoryName,
        exportMetadataDirectoryName,
    ];

    let result = sanitizeFilename(name);
    let count = 1;
    while (
        (await exists(joinPath(directoryPath, result))) ||
        specialDirectoryNames.includes(result)
    ) {
        result = `${sanitizeFilename(name)}(${count})`;
        count++;
    }
    return result;
};

export const safeFileName = async (
    directoryPath: string,
    name: string,
    exists: (path: string) => Promise<boolean>,
) => {
    let result = sanitizeFilename(name);
    let count = 1;
    while (await exists(joinPath(directoryPath, result))) {
        const [fn, ext] = nameAndExtension(sanitizeFilename(name));
        if (ext) result = `${fn}(${count}).${ext}`;
        else result = `${fn}(${count})`;
        count++;
    }
    return result;
};
