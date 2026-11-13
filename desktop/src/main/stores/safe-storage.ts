import Store, { Schema } from "electron-store";

interface SafeStorageStore {
    encryptionKey?: string;
    appLockConfig?: string;
}

const safeStorageSchema: Schema<SafeStorageStore> = {
    encryptionKey: { type: "string" },
    appLockConfig: { type: "string" },
};

export const safeStorageStore = new Store({
    name: "safeStorage",
    schema: safeStorageSchema,
});
