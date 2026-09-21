import {
    readMasterKeyFromSession,
    type SessionStorageCrypto,
} from "ente-base/session-storage";
import { ComlinkWorker } from "ente-base/worker/comlink-worker";
import { saveKeyAttributes, saveSRPAttributes } from "./accounts-db";
import type { PasswordWorker } from "./password.worker";
import { ensureLocalUser, ensureSavedKeyAttributes } from "./user";

export const changePassword = async (
    password: string,
    decryptBox: SessionStorageCrypto["decryptBox"],
) => {
    const { email } = ensureLocalUser();
    const keyAttributes = ensureSavedKeyAttributes();
    const masterKey = await readMasterKeyFromSession(decryptBox);
    if (!masterKey) throw new Error("Master key not found in session");

    const worker = new ComlinkWorker<typeof PasswordWorker>(
        "password",
        new Worker(new URL("password.worker.ts", import.meta.url)),
    );
    try {
        const updated = await (
            await worker.remote
        ).changePassword(password, masterKey, keyAttributes, email);
        saveSRPAttributes(updated.srpAttributes);
        saveKeyAttributes(updated.keyAttributes);
    } finally {
        worker.terminate();
    }
};
