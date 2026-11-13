import { createSessionStorage } from "ente-base/session-storage";
import { decryptBox, encryptBox, generateKey } from "ente-photos-wasm";

export const {
    ensureMasterKeyFromSession,
    masterKeyFromSession,
    updateSessionFromElectronSafeStorageIfNeeded,
} = createSessionStorage({ decryptBox, encryptBox, generateKey });
