import Store, { Schema } from "electron-store";
import type { PreUploadSkippedFile, ZipItem } from "../../types/ipc";

export interface UploadStatusStore {
    collectionName?: string;
    filePaths?: string[];
    zipItems?: ZipItem[];
    preUploadSkippedFiles?: PreUploadSkippedFile[];
    importTakeoutFavorites?: boolean;
    includePartnerSharedFiles?: boolean;
}

const uploadStatusSchema: Schema<UploadStatusStore> = {
    collectionName: { type: "string" },
    filePaths: { type: "array", items: { type: "string" } },
    zipItems: {
        type: "array",
        items: { type: "array", items: { type: "string" } },
    },
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
    importTakeoutFavorites: { type: "boolean" },
    includePartnerSharedFiles: { type: "boolean" },
};

export const uploadStatusStore = new Store({
    name: "upload-status",
    schema: uploadStatusSchema,
});
