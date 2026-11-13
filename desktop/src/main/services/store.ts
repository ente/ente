import { safeStorage } from "electron/main";
import type { PersistedAppLockConfig } from "../../types/ipc";
import { safeStorageStore } from "../stores/safe-storage";
import { uploadStatusStore } from "../stores/upload-status";
import { userPreferences } from "../stores/user-preferences";
import { watchStore } from "../stores/watch";

// User preferences belong to the person or device, not the signed-in account.
export const clearStores = () => {
    safeStorageStore.clear();
    uploadStatusStore.clear();
    watchStore.clear();
};

// macOS Keychain entry: "ente Safe Storage".
export const saveMasterKeyInSafeStorage = (masterKey: string) => {
    const encryptedKeyBuffer = safeStorage.encryptString(masterKey);
    const encryptedKey = Buffer.from(encryptedKeyBuffer).toString("base64");
    safeStorageStore.set("encryptionKey", encryptedKey);
};

export const masterKeyFromSafeStorage = (): string | undefined => {
    const encryptedKey = safeStorageStore.get("encryptionKey");
    if (!encryptedKey) return undefined;
    const encryptedKeyBuffer = Buffer.from(encryptedKey, "base64");
    return safeStorage.decryptString(encryptedKeyBuffer);
};

const saveAppLockConfigStringInSafeStorage = (value: string) => {
    const encryptedValueBuffer = safeStorage.encryptString(value);
    const encryptedValue = Buffer.from(encryptedValueBuffer).toString("base64");
    safeStorageStore.set("appLockConfig", encryptedValue);
};

const appLockConfigStringFromSafeStorage = (): string | undefined => {
    const encryptedValue = safeStorageStore.get("appLockConfig");
    if (!encryptedValue) return undefined;
    const encryptedValueBuffer = Buffer.from(encryptedValue, "base64");
    return safeStorage.decryptString(encryptedValueBuffer);
};

const parsePersistedAppLockConfig = (json: string): PersistedAppLockConfig => {
    const parsed: unknown = JSON.parse(json);
    if (!parsed || typeof parsed !== "object") {
        throw new Error("Invalid persisted app lock config");
    }

    const { enabled, lockType, autoLockTimeMs } = parsed as Record<
        string,
        unknown
    >;
    if (
        typeof enabled !== "boolean" ||
        (lockType !== "pin" &&
            lockType !== "password" &&
            lockType !== "device" &&
            lockType !== "none") ||
        typeof autoLockTimeMs !== "number" ||
        !Number.isFinite(autoLockTimeMs)
    ) {
        throw new Error("Invalid persisted app lock config");
    }

    return { enabled, lockType, autoLockTimeMs };
};

export const saveAppLockConfigInSafeStorage = (
    config: PersistedAppLockConfig,
) => {
    saveAppLockConfigStringInSafeStorage(JSON.stringify(config));
};

export const appLockConfigFromSafeStorage = ():
    | PersistedAppLockConfig
    | undefined => {
    const config = appLockConfigStringFromSafeStorage();

    if (!config) return undefined;

    return parsePersistedAppLockConfig(config);
};

export const clearAppLockConfigFromSafeStorage = () => {
    safeStorageStore.delete("appLockConfig");
};

export const lastShownChangelogVersion = (): number | undefined =>
    userPreferences.get("lastShownChangelogVersion");

export const setLastShownChangelogVersion = (version: number) =>
    userPreferences.set("lastShownChangelogVersion", version);

// A missing value preserves the legacy default without migrating the store.
export const shouldHideDockIcon = (): boolean =>
    process.platform == "darwin" &&
    userPreferences.get("hideDockIcon") !== false;

export const setShouldHideDockIcon = (hide: boolean) =>
    userPreferences.set("hideDockIcon", hide);
