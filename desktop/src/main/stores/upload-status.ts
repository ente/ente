import Store, { Schema } from "electron-store";
import type { PreUploadSkippedFile, ZipItem } from "../../types/ipc";

export interface UploadStatusStore {
    /**
     * The collection to which we're uploading, or the root collection.
     *
     * Not all pending uploads will have an associated collection.
     */
    collectionName?: string;
    /**
     * Paths to regular files that are pending upload.
     */
    filePaths?: string[];
    /**
     * Each item is the path to a zip file and the name of an entry within it.
     */
    zipItems?: ZipItem[];
    /**
     * @deprecated Legacy paths to zip files, now subsumed into zipItems.
     */
    zipPaths?: string[];
    /**
     * Files that were skipped because either we could not open them (zip files)
     * or they are hidden dot files.
     */
    preUploadSkippedFiles?: PreUploadSkippedFile[];
}

const uploadStatusSchema: Schema<UploadStatusStore> = {
    collectionName: { type: "string" },
    filePaths: { type: "array", items: { type: "string" } },
    zipItems: {
        type: "array",
        items: { type: "array", items: { type: "string" } },
    },
    zipPaths: { type: "array", items: { type: "string" } },
    preUploadSkippedFiles: {
        type: "array",
        items: {
            type: "object",
            required: ["name", "type"],
            properties: {
                name: { type: "string" },
                type: { type: "string", enum: ["hiddenFile", "failedZip"] },
            },
        },
    },
};

export const uploadStatusStore = new Store({
    name: "upload-status",
    schema: uploadStatusSchema,
});
