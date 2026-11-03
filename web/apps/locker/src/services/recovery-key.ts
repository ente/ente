import { recoveryKeyMnemonic as getMnemonic } from "ente-locker-wasm";
import { ensureAuthenticatedSession } from "./authenticated-session";

export const recoveryKeyMnemonic = async () =>
    getMnemonic(await ensureAuthenticatedSession());
