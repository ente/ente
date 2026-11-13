import { clientPackageName, desktopAppVersion, isDesktop } from "ente-base/app";
import { apiOrigin } from "ente-base/origins";
import { savedAuthToken } from "ente-base/token";
import { ensureLocalUser, ensureSavedKeyAttributes } from "./user";

interface Session {
    free(): void;
    updateAuthToken(authToken: string): void;
}

interface SessionInput {
    baseUrl: string;
    authToken: string;
    userID: number;
    masterKeyB64: string;
    keyAttributes: ReturnType<typeof ensureSavedKeyAttributes>;
    clientPackage: string;
    clientVersion: string | undefined;
}

export const createAuthenticatedSessionCache = <T extends Session>(
    openSession: (input: SessionInput) => Promise<T>,
    masterKeyFromSession: () => Promise<string | undefined>,
    onOpen?: (session: T) => void,
) => {
    let current: { key: string; opening: Promise<T> } | undefined;
    let generation = 0;

    const open = async (
        userID: number,
        authToken: string,
        masterKeyB64?: string,
    ) => {
        const startedGeneration = generation;
        const baseUrl = await apiOrigin();
        if (startedGeneration !== generation) {
            throw new Error("Authenticated session was cleared");
        }
        const key = `${baseUrl}:${userID}`;
        if (current?.key !== key) {
            const opening = (async () => {
                const keyAttributes = ensureSavedKeyAttributes();
                const masterKey =
                    masterKeyB64 ?? (await masterKeyFromSession());
                if (startedGeneration !== generation) {
                    throw new Error("Authenticated session was cleared");
                }
                if (!masterKey) throw new Error("Missing current master key");
                return openSession({
                    baseUrl,
                    authToken,
                    userID,
                    masterKeyB64: masterKey,
                    keyAttributes,
                    clientPackage: clientPackageName,
                    clientVersion: isDesktop ? desktopAppVersion : undefined,
                });
            })()
                .then((session) => {
                    if (current?.opening !== opening) {
                        session.free();
                        throw new Error("Authenticated session was cleared");
                    }
                    onOpen?.(session);
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
    };

    const ensure = async () => {
        const startedGeneration = generation;
        const userID = ensureLocalUser().id;
        const authToken = await savedAuthToken();
        if (startedGeneration !== generation) {
            throw new Error("Authenticated session was cleared");
        }
        if (!authToken) throw new Error("Missing auth token");
        return open(userID, authToken);
    };

    return {
        open,
        ensure,
        clear: () => {
            generation++;
            // In-flight calls may still borrow the handle; wasm-bindgen finalizes it.
            current = undefined;
        },
    };
};
