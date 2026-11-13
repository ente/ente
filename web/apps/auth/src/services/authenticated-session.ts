import { createAuthenticatedSessionCache } from "ente-accounts/services/authenticated-session";
import { openSession } from "ente-auth-wasm";
import { masterKeyFromSession } from "./account-keys";

const sessions = createAuthenticatedSessionCache(
    openSession,
    masterKeyFromSession,
);

export const ensureAuthenticatedSession = sessions.ensure;
export const clearAuthenticatedSession = sessions.clear;
