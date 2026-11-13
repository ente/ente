import { createSessionStorage } from "ente-base/session-storage";
import { decryptBox, encryptBox, generateKey } from "ente-prelogin-wasm";

export const {
    ensureMasterKeyFromSession,
    masterKeyFromSession,
    saveMasterKeyInSessionAndSafeStore,
    stashKeyEncryptionKeyInSessionStore,
    unstashKeyEncryptionKeyFromSession,
    updateSessionFromElectronSafeStorageIfNeeded,
} = createSessionStorage({ decryptBox, encryptBox, generateKey });
