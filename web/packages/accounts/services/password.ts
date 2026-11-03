import {
    readMasterKeyFromSession,
    type SessionStorageCrypto,
} from "ente-base/session-storage";
import { ComlinkWorker } from "ente-base/worker/comlink-worker";
import { saveKeyAttributes, saveOriginalKeyAttributes } from "./accounts-db";
import type { PasswordWorker } from "./password.worker";
import { ensureSavedKeyAttributes } from "./user";

export const changePassword = async (
    password: string,
    decryptBox: SessionStorageCrypto["decryptBox"],
) => {
    const keyAttributes = ensureSavedKeyAttributes();
    const masterKey = await readMasterKeyFromSession(decryptBox);
    if (!masterKey) throw new Error("Master key not found in session");

    const worker = new ComlinkWorker<typeof PasswordWorker>(
        "password",
        new Worker(new URL("password.worker.ts", import.meta.url)),
    );
    try {
        const { interactiveKeyAttributes, remoteKeyAttributes } = await (
            await worker.remote
        ).changePassword(password, masterKey, keyAttributes);
        saveKeyAttributes(interactiveKeyAttributes);
        saveOriginalKeyAttributes(remoteKeyAttributes);
    } finally {
        worker.terminate();
    }
};
