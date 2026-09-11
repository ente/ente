import { createAuthenticatedRecoveryKeyOps } from "ente-accounts/services/authenticated-recovery-key";
import {
    ensureLocalUser,
    ensureSavedKeyAttributes,
} from "ente-accounts/services/user";
import { clientPackageName, desktopAppVersion, isDesktop } from "ente-base/app";
import { apiOrigin } from "ente-base/origins";
import { savedAuthToken } from "ente-base/token";
import { openSession as openLegacySession } from "ente-legacy-wasm/authenticated";
import {
    encryptBoxWithRecoveryKey,
    generateKey,
    openSession,
    type Session,
} from "ente-locker-wasm";
import { masterKeyFromSession } from "./account-keys";

const lockerSessions = sessionCache(openSession);
const legacySessions = sessionCache(openLegacySession);
let generation = 0;

export const openAuthenticatedSession = lockerSessions.open;

const savedSessionCredentials = async () => {
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
    return { userID, authToken, masterKeyB64 };
};

export const ensureAuthenticatedSession = async () => {
    const current = lockerSessions.current();
    if (current) return current;

    const { userID, authToken, masterKeyB64 } = await savedSessionCredentials();
    return lockerSessions.open(userID, authToken, masterKeyB64);
};

export const authenticatedLegacySession = async () => {
    const { userID, authToken, masterKeyB64 } = await savedSessionCredentials();
    return legacySessions.open(userID, authToken, masterKeyB64);
};

export const clearAuthenticatedSession = () => {
    generation++;
    lockerSessions.clear();
    legacySessions.clear();
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

function sessionCache<T extends Pick<Session, "free" | "updateAuthToken">>(
    open: (config: Parameters<typeof openSession>[0]) => Promise<T>,
) {
    let current: { key: string; opening: Promise<T> } | undefined;

    return {
        current: () => current?.opening,
        open: async (
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
                const opening = open({
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
                            throw new Error(
                                "Authenticated session was cleared",
                            );
                        }
                        return session;
                    })
                    .catch((error: unknown) => {
                        if (current?.opening === opening) current = undefined;
                        throw error;
                    });
                current = { key, opening };
            }

            const entry = current;
            const session = await entry.opening;
            if (current !== entry) {
                throw new Error("Authenticated session was cleared");
            }
            session.updateAuthToken(authToken);
            return session;
        },
        clear: () => {
            // In-flight calls may still borrow the handle; wasm-bindgen finalizes it.
            current = undefined;
        },
    };
}
