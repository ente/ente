import { createAuthenticatedSessionCache } from "ente-accounts/services/authenticated-session";
import { openSession } from "ente-locker-wasm";
import { masterKeyFromSession } from "./account-keys";

const sessions = createAuthenticatedSessionCache(
    openSession,
    masterKeyFromSession,
);

export const openAuthenticatedSession = sessions.open;
export const ensureAuthenticatedSession = sessions.ensure;
export const clearAuthenticatedSession = sessions.clear;
