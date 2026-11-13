import Store, { Schema } from "electron-store";
import { type FolderWatch } from "../../types/ipc";

interface WatchStore {
    mappings?: FolderWatch[];
}

const watchStoreSchema: Schema<WatchStore> = {
    mappings: {
        type: "array",
        items: {
            type: "object",
            properties: {
                collectionMapping: { type: "string" },
                folderPath: { type: "string" },
                syncedFiles: {
                    type: "array",
                    items: {
                        type: "object",
                        properties: {
                            path: { type: "string" },
                            uploadedFileID: { type: "number" },
                            collectionID: { type: "number" },
                        },
                    },
                },
                ignoredFiles: { type: "array", items: { type: "string" } },
            },
        },
    },
};

export const watchStore = new Store({
    name: "watch-status",
    schema: watchStoreSchema,
});
