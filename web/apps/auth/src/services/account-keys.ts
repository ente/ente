import { decryptBox } from "ente-auth-wasm";
import { readMasterKeyFromSession } from "ente-base/session-storage";

export const masterKeyFromSession = () => readMasterKeyFromSession(decryptBox);
