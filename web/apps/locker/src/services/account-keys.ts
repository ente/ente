import { readMasterKeyFromSession } from "ente-base/session-storage";
import { decryptBox } from "ente-locker-wasm";

export const masterKeyFromSession = () => readMasterKeyFromSession(decryptBox);
