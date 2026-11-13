import { z } from "zod";
import log from "./log";

export const clearSessionStorage = () => sessionStorage.clear();

export const haveMasterKeyInSession = () =>
    !!sessionStorage.getItem("encryptionKey");

export const clearStashedKeyEncryptionKeyFromSession = () =>
    sessionStorage.removeItem("keyEncryptionKey");

const SessionKeyData = z.object({
    encryptedData: z.string(),
    key: z.string(),
    nonce: z.string(),
});

type SessionKeyData = z.infer<typeof SessionKeyData>;

export interface SessionStorageCrypto {
    decryptBox: (
        box: { encryptedData: string; nonce: string },
        key: string,
    ) => Promise<string>;
    encryptBox: (
        data: string,
        key: string,
    ) => Promise<{ encryptedData: string; nonce: string }>;
    generateKey: () => Promise<string>;
}

export const readMasterKeyFromSession = async (
    decryptBox: SessionStorageCrypto["decryptBox"],
) => {
    const value = sessionStorage.getItem("encryptionKey");
    if (!value) return undefined;

    const { encryptedData, key, nonce } = SessionKeyData.parse(
        JSON.parse(value),
    );
    return decryptBox({ encryptedData, nonce }, key);
};

export const createSessionStorage = ({
    decryptBox,
    encryptBox,
    generateKey,
}: SessionStorageCrypto) => {
    const masterKeyFromSession = () => readMasterKeyFromSession(decryptBox);

    const ensureMasterKeyFromSession = async () => {
        const key = await masterKeyFromSession();
        if (!key) throw new Error("Master key not found in session");
        return key;
    };

    const sessionKeyData = async (keyData: string): Promise<SessionKeyData> => {
        const key = await generateKey();
        const box = await encryptBox(keyData, key);
        return { key, ...box };
    };

    const saveKeyInSessionStore = async (keyName: string, keyData: string) => {
        sessionStorage.setItem(
            keyName,
            JSON.stringify(await sessionKeyData(keyData)),
        );
    };

    const saveMasterKeyInSessionAndSafeStore = async (masterKey: string) => {
        await saveKeyInSessionStore("encryptionKey", masterKey);
        try {
            await globalThis.electron?.saveMasterKeyInSafeStorage(masterKey);
        } catch (e) {
            log.warn("Failed to save master key in safe storage", e);
        }
    };

    const updateSessionFromElectronSafeStorageIfNeeded = async () => {
        const electron = globalThis.electron;
        if (!electron || haveMasterKeyInSession()) return;

        let masterKey: string | undefined;
        try {
            masterKey = await electron.masterKeyFromSafeStorage();
        } catch (e) {
            log.warn("Failed to read master key from safe storage", e);
        }

        if (masterKey) await saveKeyInSessionStore("encryptionKey", masterKey);
    };

    const stashKeyEncryptionKeyInSessionStore = (kek: string) =>
        saveKeyInSessionStore("keyEncryptionKey", kek);

    const unstashKeyEncryptionKeyFromSession = async () => {
        const value = sessionStorage.getItem("keyEncryptionKey");
        if (!value) return undefined;

        clearStashedKeyEncryptionKeyFromSession();

        const { encryptedData, key, nonce } = SessionKeyData.parse(
            JSON.parse(value),
        );
        return decryptBox({ encryptedData, nonce }, key);
    };

    return {
        ensureMasterKeyFromSession,
        masterKeyFromSession,
        saveMasterKeyInSessionAndSafeStore,
        stashKeyEncryptionKeyInSessionStore,
        unstashKeyEncryptionKeyFromSession,
        updateSessionFromElectronSafeStorageIfNeeded,
    };
};
