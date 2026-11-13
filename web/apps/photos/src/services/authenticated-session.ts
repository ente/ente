import { createAuthenticatedSessionCache } from "ente-accounts/services/authenticated-session";
import { masterKeyFromSession } from "ente-new/photos/services/account-keys";
import {
    bindCollectionKeyOpener,
    unbindCollectionKeyOpener,
} from "ente-new/photos/services/collection";
import { openCollectionKey, openSession } from "ente-photos-wasm";

const sessions = createAuthenticatedSessionCache(
    openSession,
    masterKeyFromSession,
    (session) =>
        bindCollectionKeyOpener((input) =>
            openCollectionKey(
                session,
                input.ownerID,
                input.encryptedKey,
                input.keyDecryptionNonce,
            ),
        ),
);

export const openAuthenticatedSession = sessions.open;
export const ensureAuthenticatedSession = sessions.ensure;

export const clearAuthenticatedSession = () => {
    sessions.clear();
    unbindCollectionKeyOpener();
};
