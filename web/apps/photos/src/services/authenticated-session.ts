import { createAuthenticatedRecoveryKeyOps } from "ente-accounts/services/authenticated-recovery-key";
import {
    ensureLocalUser,
    ensureSavedKeyAttributes,
} from "ente-accounts/services/user";
import { clientPackageName, desktopAppVersion, isDesktop } from "ente-base/app";
import { apiOrigin } from "ente-base/origins";
import { masterKeyFromSession } from "ente-base/session";
import { savedAuthToken } from "ente-base/token";
import {
    bindCollectionKeyOpener,
    unbindCollectionKeyOpener,
} from "ente-new/photos/services/collection";
import {
    encryptBoxWithRecoveryKey,
    generateKey,
    openCollectionKey,
    openSession,
    type Session,
} from "ente-photos-wasm";

let current: { key: string; opening: Promise<Session> } | undefined;
let generation = 0;

export const openAuthenticatedSession = async (
    userID: number,
    authToken: string,
    masterKeyB64: string,
) => {
    const startedGeneration = generation;
    const baseUrl = await apiOrigin();
    if (startedGeneration !== generation) {
        throw new Error("Authenticated session was cleared");
    }
    const key = `${baseUrl}:${userID}`;
    if (current?.key !== key) {
        const keyAttributes = ensureSavedKeyAttributes();
        const opening = openSession({
            baseUrl,
            authToken,
            userID,
            masterKeyB64,
            keyAttributes,
            clientPackage: clientPackageName,
            clientVersion: isDesktop ? desktopAppVersion : undefined,
        })
            .then((session) => {
                if (current?.opening !== opening) {
                    session.free();
                    throw new Error("Authenticated session was cleared");
                }
                return session;
            })
            .catch((error: unknown) => {
                if (current?.opening === opening) current = undefined;
                throw error;
            });
        current = { key, opening };
        bindCollectionKeyOpener(async (input) =>
            openCollectionKey(
                await (current?.opening ?? ensureAuthenticatedSession()),
                input.ownerID,
                input.encryptedKey,
                input.keyDecryptionNonce,
            ),
        );
    }

    const entry = current;
    const session = await entry.opening;
    if (current !== entry) {
        throw new Error("Authenticated session was cleared");
    }
    session.updateAuthToken(authToken);
    return session;
};

export const ensureAuthenticatedSession = async () => {
    const startedGeneration = generation;
    const userID = ensureLocalUser().id;
    const [authToken, masterKeyB64] = await Promise.all([
        savedAuthToken(),
        masterKeyFromSession(),
    ]);
    if (startedGeneration !== generation) {
        throw new Error("Authenticated session was cleared");
    }
    if (!masterKeyB64) throw new Error("Missing current master key");
    if (!authToken) throw new Error("Missing auth token");
    return openAuthenticatedSession(userID, authToken, masterKeyB64);
};

export const clearAuthenticatedSession = () => {
    generation++;
    unbindCollectionKeyOpener();
    // In-flight calls may still borrow the handle; wasm-bindgen finalizes it.
    current = undefined;
};

export const {
    encryptWithRecoveryKey,
    generatePasskeyRecovery,
    recoveryKeyMnemonic,
} = createAuthenticatedRecoveryKeyOps({
    ensureSession: ensureAuthenticatedSession,
    encryptBox: encryptBoxWithRecoveryKey,
    generateKey,
});
