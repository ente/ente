import { recoveryKeyMnemonic as getMnemonic } from "ente-photos-wasm";
import { ensureAuthenticatedSession } from "./authenticated-session";

export const recoveryKeyMnemonic = async () =>
    getMnemonic(await ensureAuthenticatedSession());
