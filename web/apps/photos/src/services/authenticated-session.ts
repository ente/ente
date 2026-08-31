import { clientPackageName, desktopAppVersion, isDesktop } from "ente-base/app";
import { apiOrigin } from "ente-base/origins";
import { openSession, type Session } from "ente-photos-wasm";

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
        const opening = openSession({
            baseUrl,
            authToken,
            masterKeyB64,
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
    }

    const entry = current;
    const session = await entry.opening;
    if (current !== entry) {
        throw new Error("Authenticated session was cleared");
    }
    session.updateAuthToken(authToken);
    return session;
};

export const clearAuthenticatedSession = () => {
    generation++;
    // In-flight calls may still borrow the handle; wasm-bindgen finalizes it.
    current = undefined;
};
