import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { metadataHash } from "ente-media/file-metadata";
export const suppressSharedFilesSavedByUser = (
    files: EnteFile[],
    currentUserID: number | undefined,
    activeCollection: Collection | undefined,
) => {
    if (!currentUserID || activeCollection) return files;

    const ownedFileKeys = new Set<string>();
    for (const file of files) {
        if (file.ownerID != currentUserID) continue;
        const hash = metadataHash(file.metadata);
        if (!hash) continue;
        ownedFileKeys.add(`${hash}:${file.metadata.fileType}`);
    }

    if (!ownedFileKeys.size) return files;

    return files.filter((file) => {
        if (file.ownerID == currentUserID) return true;

        const hash = metadataHash(file.metadata);
        if (!hash) return true;

        return !ownedFileKeys.has(`${hash}:${file.metadata.fileType}`);
    });
};
