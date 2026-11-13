import { recoveryKeyMnemonic as getMnemonic } from "ente-auth-wasm";
import { ensureAuthenticatedSession } from "./authenticated-session";

export const recoveryKeyMnemonic = async () =>
    getMnemonic(await ensureAuthenticatedSession());
